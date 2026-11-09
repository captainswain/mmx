import 'dart:math' as math;
import 'dart:typed_data';

import '../geom/bbox.dart';
import '../mesh/tri_mesh.dart';
import '../repair/holes.dart';
import '../spatial/bvh.dart';
import '../tools/modify.dart';
import 'surface_nets.dart';
import 'voxel.dart';

enum SolidMode { blocky, fast, accurate }

enum BooleanOp { union, intersection, difference }

class SolidResult {
  final TriMesh mesh;
  final int gridResolution;
  final double cellSize;
  final int elapsedMs;
  SolidResult(this.mesh, this.gridResolution, this.cellSize, this.elapsedMs);
}

/// Converts triangle soup into watertight solids and performs grid-based CSG.
///
/// Mirrors the shipped "Convert To Solid" / boolean / hollow tool stack
/// (MeshToSolid, ImplicitPolygonizer, SurfaceOffset, MeshBoolean) including the
/// Blocky / Fast / Accurate routines and the Smoothing / Grid Resolution /
/// Mesh Resolution / Reduce Percentage controls exposed in the UI.
class Solidifier {
  static VoxelGrid _gridFor(BBox bounds, int resolution, double padCells) {
    if (resolution < 8 ||
        resolution > 256 ||
        !padCells.isFinite ||
        padCells < 0) {
      throw ArgumentError('Resolution must be 8–256 and padding finite');
    }
    if (bounds.isEmpty) return VoxelGrid(8, 8, 8, 1, -4, -4, -4);
    final extent =
        math.max(bounds.extentX, math.max(bounds.extentY, bounds.extentZ));
    if (extent <= 0) {
      return VoxelGrid(
          8, 8, 8, 1.0, bounds.minX - 4, bounds.minY - 4, bounds.minZ - 4);
    }
    final cell = extent / resolution;
    final pad = padCells * cell;
    final nx = ((bounds.extentX + 2 * pad) / cell).ceil() + 1;
    final ny = ((bounds.extentY + 2 * pad) / cell).ceil() + 1;
    final nz = ((bounds.extentZ + 2 * pad) / cell).ceil() + 1;
    return VoxelGrid(nx, ny, nz, cell, bounds.minX - pad, bounds.minY - pad,
        bounds.minZ - pad);
  }

  static SolidResult makeSolid(
    TriMesh mesh, {
    SolidMode mode = SolidMode.accurate,
    int resolution = 128,
    double offset = 0,
    int smoothing = 0,
    double minThickness = 0,
    bool closeHoles = true,
  }) {
    if (resolution < 8 ||
        resolution > 256 ||
        !offset.isFinite ||
        smoothing < 0 ||
        smoothing > 1000 ||
        !minThickness.isFinite ||
        minThickness < 0) {
      throw ArgumentError('Invalid Make Solid parameters');
    }
    if (minThickness > 0) {
      throw UnsupportedError('Make Solid cannot guarantee minimum thickness. '
          'Use hollow thickness for an SDF shell, or measure the output independently.');
    }
    final sw = Stopwatch()..start();
    var work = mesh;
    if (closeHoles) {
      work = HoleFiller.fill(work, maxLoopLength: work.bounds().diagonal * 0.5);
    }
    final effectiveResolution = switch (mode) {
      SolidMode.blocky => math.max(24, (resolution * 0.45).round()),
      SolidMode.fast => math.max(40, (resolution * 0.7).round()),
      SolidMode.accurate => resolution,
    };
    final effectiveSmoothing = switch (mode) {
      SolidMode.blocky => smoothing,
      SolidMode.fast => math.max(smoothing, 1),
      SolidMode.accurate => smoothing,
    };
    final bounds = work.bounds();
    final extent =
        math.max(bounds.extentX, math.max(bounds.extentY, bounds.extentZ));
    final cell = extent <= 0 ? 1.0 : extent / effectiveResolution;
    // Pad has to cover the offset, otherwise the grown surface is clipped by
    // the grid boundary and the result silently shrinks.
    final padCells = 3.0 + offset.abs() / cell;
    final grid = _gridFor(bounds, effectiveResolution, padCells);
    // The narrow band must cover the requested offset, otherwise the offset
    // surface falls outside the exact-distance region and gets clipped.
    grid.rasterize(work, bandCells: offset.abs() / grid.cellSize + 2.5);
    if (offset != 0) grid.offset(offset);
    if (effectiveSmoothing > 0) grid.smooth(effectiveSmoothing);
    var solid = SurfaceNets.polygonize(grid);
    if (solid.signedVolume() < 0) solid = _flip(solid);
    // Meshmixer's Fast mode reprojects the meshed voxel surface back onto the
    // input mesh after polygonization (see the Make Solid help page).
    if (mode == SolidMode.fast && work.vertexCount > 0) {
      final bvh = TriangleBVH.build(work);
      final pos = Float32List.fromList(solid.positions);
      for (var v = 0; v < solid.vertexCount; v++) {
        final hit =
            bvh.closestPoint(pos[v * 3], pos[v * 3 + 1], pos[v * 3 + 2]);
        if (hit == null) continue;
        pos[v * 3] = hit.point[0];
        pos[v * 3 + 1] = hit.point[1];
        pos[v * 3 + 2] = hit.point[2];
      }
      solid.positions = pos;
    }
    // Keep zero-area faces: surface nets can emit them where two cells
    // collapse, and dropping them would punch holes in the solid.
    solid.removeDegenerateFaces(minArea: -1);
    solid.compact();
    sw.stop();
    return SolidResult(
        solid, effectiveResolution, grid.cellSize, sw.elapsedMilliseconds);
  }

  static SolidResult boolean(TriMesh a, TriMesh b, BooleanOp op,
      {int resolution = 160}) {
    if (resolution < 8 || resolution > 256) {
      throw ArgumentError('Resolution must be 8–256');
    }
    final sw = Stopwatch()..start();
    final exact = trivialBoolean(a, b, op);
    if (exact != null) {
      return SolidResult(exact, resolution, 0, sw.elapsedMilliseconds);
    }
    final bounds = BBox();
    bounds.addBox(a.bounds());
    bounds.addBox(b.bounds());
    final grid = _gridFor(bounds, resolution, 3.0);
    final ga = _gridFor(bounds, resolution, 3.0);
    final gb = _gridFor(bounds, resolution, 3.0);
    ga.rasterize(a, bandCells: 2.5);
    gb.rasterize(b, bandCells: 2.5);
    for (var i = 0; i < grid.values.length; i++) {
      final va = ga.values[i];
      final vb = gb.values[i];
      grid.values[i] = switch (op) {
        BooleanOp.union => math.min(va, vb),
        BooleanOp.intersection => math.max(va, vb),
        BooleanOp.difference => math.max(va, -vb),
      };
    }
    var out = SurfaceNets.polygonize(grid);
    if (out.signedVolume() < 0) out = _flip(out);
    out.removeDegenerateFaces(minArea: -1);
    out.compact();
    sw.stop();
    return SolidResult(out, resolution, grid.cellSize, sw.elapsedMilliseconds);
  }

  /// Offset surface. Positive grows, negative shrinks.
  static SolidResult offsetSolid(TriMesh mesh, double distance,
      {int resolution = 128}) {
    return makeSolid(mesh,
        resolution: resolution, offset: distance, smoothing: 1);
  }

  /// Hollow shell with escape holes.
  ///
  /// Material band = points whose distance to the surface lies in
  /// [-thickness, 0]; escape holes are subtracted as capped cylinders.
  static SolidResult hollow(
    TriMesh mesh, {
    double thickness = 2.0,
    int holes = 3,
    double holeRadius = 3.0,
    int resolution = 128,
    bool openTop = false,
    double minThickness = 0.0,
  }) {
    if (!thickness.isFinite ||
        thickness <= 0 ||
        !minThickness.isFinite ||
        minThickness < 0 ||
        holes < 0 ||
        holes > 1000 ||
        !holeRadius.isFinite ||
        holeRadius <= 0) {
      throw ArgumentError('Invalid hollow parameters');
    }
    thickness = math.max(thickness, minThickness);
    final sw = Stopwatch()..start();
    final bounds = mesh.bounds();
    final grid = _gridFor(bounds, resolution, 3.0);
    // Band must span the wall thickness: beyond the band the field is a far
    // constant, which would otherwise truncate the shell.
    grid.rasterize(mesh, bandCells: thickness / grid.cellSize + 2.5);
    final d = grid.values;
    for (var i = 0; i < d.length; i++) {
      final v = d[i];
      d[i] = math.max(v, -thickness - v);
    }
    if (openTop) {
      // Remove a cap band above the top of the model.
      final top = bounds.maxY - thickness;
      for (var i = 0; i < grid.nx; i++) {
        for (var k = 0; k < grid.nz; k++) {
          for (var j = 0; j < grid.ny; j++) {
            final wy = grid.originY + j * grid.cellSize;
            if (wy < top) continue;
            final idx = grid.index(i, j, k);
            if (d[idx] < 0) d[idx] = grid.cellSize;
          }
        }
      }
    }
    if (holes > 0) {
      _drillEscapeHoles(grid, bounds, holes, holeRadius, thickness);
    }
    var out = SurfaceNets.polygonize(grid);
    if (out.signedVolume() < 0) out = _flip(out);
    out.removeDegenerateFaces(minArea: -1);
    out.compact();
    sw.stop();
    return SolidResult(out, resolution, grid.cellSize, sw.elapsedMilliseconds);
  }

  /// Drills radial escape holes around the lower part of the shell.
  static void _drillEscapeHoles(
      VoxelGrid grid, BBox bounds, int count, double radius, double thickness) {
    final cx = (bounds.minX + bounds.maxX) / 2;
    final cz = (bounds.minZ + bounds.maxZ) / 2;
    final y = bounds.minY + math.max(thickness * 1.5, bounds.extentY * 0.08);
    for (var h = 0; h < count; h++) {
      final angle = 2 * math.pi * h / count;
      final dx = math.cos(angle), dz = math.sin(angle);
      // Cylinder axis points inward from outside the bounding box.
      final startX = cx + dx * (bounds.extentX * 0.6);
      final startZ = cz + dz * (bounds.extentZ * 0.6);
      final len = math.max(bounds.extentX, bounds.extentZ) * 0.8;
      for (var i = 0; i < grid.nx; i++) {
        final px = grid.originX + i * grid.cellSize;
        for (var j = 0; j < grid.ny; j++) {
          final py = grid.originY + j * grid.cellSize;
          for (var k = 0; k < grid.nz; k++) {
            final pz = grid.originZ + k * grid.cellSize;
            final qx = px - startX, qy = py - y, qz = pz - startZ;
            final along = qx * dx + qz * dz;
            if (along < 0 || along > len) continue;
            final perpX = qx - along * dx;
            final perpZ = qz - along * dz;
            final radial = math.sqrt(perpX * perpX + qy * qy + perpZ * perpZ);
            final idx = grid.index(i, j, k);
            if (radial < radius && grid.values[idx] < 0) {
              grid.values[idx] = radius - radial; // positive => carved out
            }
          }
        }
      }
    }
  }

  static TriMesh _flip(TriMesh m) {
    final idx = Uint32List(m.indices.length);
    for (var f = 0; f < m.faceCount; f++) {
      idx[f * 3] = m.indices[f * 3];
      idx[f * 3 + 1] = m.indices[f * 3 + 2];
      idx[f * 3 + 2] = m.indices[f * 3 + 1];
    }
    return TriMesh(m.positions, idx,
        faceGroups: m.faceGroups, vertexColors: m.vertexColors);
  }
}

/// Exact empty, identical and strictly disjoint set operations. Returns null
/// when surface classification or voxelization is required.
TriMesh? trivialBoolean(TriMesh a, TriMesh b, BooleanOp op) {
  if (a.validate().isNotEmpty || b.validate().isNotEmpty) {
    throw ArgumentError('Invalid boolean operand');
  }
  if (a.faceCount == 0 || b.faceCount == 0) {
    return switch (op) {
      BooleanOp.union => (a.faceCount == 0 ? b : a).clone(),
      BooleanOp.intersection => TriMesh.empty(),
      BooleanOp.difference => a.clone(),
    };
  }
  bool same(List<num> x, List<num> y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  if (same(a.positions, b.positions) && same(a.indices, b.indices)) {
    return op == BooleanOp.difference ? TriMesh.empty() : a.clone();
  }
  final aa = a.bounds(), bb = b.bounds();
  final disjoint = aa.maxX < bb.minX ||
      bb.maxX < aa.minX ||
      aa.maxY < bb.minY ||
      bb.maxY < aa.minY ||
      aa.maxZ < bb.minZ ||
      bb.maxZ < aa.minZ;
  if (!disjoint) return null;
  return switch (op) {
    BooleanOp.union => Modify.combine([a, b]),
    BooleanOp.intersection => TriMesh.empty(),
    BooleanOp.difference => a.clone(),
  };
}
