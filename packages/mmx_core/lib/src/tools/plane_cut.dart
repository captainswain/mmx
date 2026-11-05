import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import '../repair/holes.dart';

/// Plane cutting and slicing.
///
/// Mirrors Meshmixer's Plane Cut tool parameters: "Cut Type: Cut (Discard
/// Half) | Slice (Keep Both) | Slice Groups", "Fill Type: No Fill | Minimal
/// Fill | Remeshed Fill | Fixed Fill", plus plane offset/rotation.
class PlaneCut {
  static TriMesh cut(
    TriMesh mesh, {
    required List<double> point,
    required List<double> normal,
    bool keepPositive = true,
    bool fill = true,
    HoleFillMode fillMode = HoleFillMode.flatMinimal,
    bool sliceBoth = false,
  }) {
    final nx = normal[0], ny = normal[1], nz = normal[2];
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl < 1e-12) return mesh;
    final ux = nx / nl, uy = ny / nl, uz = nz / nl;
    final px = point[0], py = point[1], pz = point[2];
    final sign = keepPositive ? 1.0 : -1.0;

    double side(int v) =>
        sign *
        ((mesh.vx(v) - px) * ux +
            (mesh.vy(v) - py) * uy +
            (mesh.vz(v) - pz) * uz);

    final builderPos = <double>[...mesh.positions];
    final indices = <int>[];
    final n = mesh.vertexCount;
    // Cache of split points on edges (edge key -> vertex id).
    final splitCache = <int, int>{};

    int splitVertex(int a, int b) {
      final key = a < b ? a * n + b : b * n + a;
      final cached = splitCache[key];
      if (cached != null) return cached;
      final da = side(a), db = side(b);
      final t = da / (da - db);
      final id = builderPos.length ~/ 3;
      builderPos.add(mesh.vx(a) + (mesh.vx(b) - mesh.vx(a)) * t);
      builderPos.add(mesh.vy(a) + (mesh.vy(b) - mesh.vy(a)) * t);
      builderPos.add(mesh.vz(a) + (mesh.vz(b) - mesh.vz(a)) * t);
      splitCache[key] = id;
      return id;
    }

    for (var f = 0; f < mesh.faceCount; f++) {
      final v0 = mesh.indices[f * 3],
          v1 = mesh.indices[f * 3 + 1],
          v2 = mesh.indices[f * 3 + 2];
      final s0 = side(v0), s1 = side(v1), s2 = side(v2);
      final eps = 1e-9;
      final pos = <int>[], neg = <int>[], on = <int>[];
      for (final pair in <List<int>>[
        <int>[v0, 0],
        <int>[v1, 1],
        <int>[v2, 2],
      ]) {
        final v = pair[0];
        final s = <double>[s0, s1, s2][pair[1]];
        if (s > eps) {
          pos.add(v);
        } else if (s < -eps) {
          neg.add(v);
        } else {
          on.add(v);
        }
      }
      if (neg.isEmpty) {
        // Fully on the positive side.
        indices.addAll(<int>[v0, v1, v2]);
        continue;
      }
      if (pos.isEmpty) continue; // fully on the negative side, discarded
      // Emit the positive part.
      if (pos.length == 1 && neg.length == 2) {
        final p = pos[0];
        final s1v = splitVertex(p, neg[0]);
        final s2v = splitVertex(p, neg[1]);
        indices.addAll(<int>[p, s1v, s2v]);
      } else if (pos.length == 2 && neg.length == 1) {
        final a = pos[0], b = pos[1], c = neg[0];
        final s1v = splitVertex(a, c);
        final s2v = splitVertex(b, c);
        indices.addAll(<int>[a, b, s2v]);
        indices.addAll(<int>[a, s2v, s1v]);
      } else if (on.isNotEmpty && pos.isNotEmpty) {
        // Degenerate case: vertex on the plane.
        if (pos.length == 2 && on.length == 1) {
          indices.addAll(<int>[pos[0], pos[1], on[0]]);
        } else if (pos.length == 1 && on.length == 2) {
          indices.addAll(<int>[pos[0], on[0], on[1]]);
        }
      }
    }

    var out =
        TriMesh(Float32List.fromList(builderPos), Uint32List.fromList(indices));
    out.removeDegenerateFaces();
    out.compact();
    if (fill) {
      out = HoleFiller.fill(out, mode: fillMode);
    }
    if (sliceBoth) {
      final other = cut(mesh,
          point: point,
          normal: normal,
          keepPositive: false,
          fill: fill,
          fillMode: fillMode);
      out = _merge(out, other);
    }
    return out;
  }

  /// Assigns a new face group to triangles on one side of the plane without
  /// changing geometry (Meshmixer's Plane Cut "Slice Groups" mode).
  static TriMesh sliceGroups(
    TriMesh mesh, {
    required List<double> point,
    required List<double> normal,
    int groupId = 1,
    int? negativeGroupId,
  }) {
    final nx = normal[0], ny = normal[1], nz = normal[2];
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl < 1e-12) return mesh;
    final ux = nx / nl, uy = ny / nl, uz = nz / nl;
    final px = point[0], py = point[1], pz = point[2];
    final groups = Uint16List.fromList(
        mesh.faceGroups ?? List<int>.filled(mesh.faceCount, 0));
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = mesh.indices[f * 3];
      final b = mesh.indices[f * 3 + 1];
      final c = mesh.indices[f * 3 + 2];
      final cx = (mesh.vx(a) + mesh.vx(b) + mesh.vx(c)) / 3.0;
      final cy = (mesh.vy(a) + mesh.vy(b) + mesh.vy(c)) / 3.0;
      final cz = (mesh.vz(a) + mesh.vz(b) + mesh.vz(c)) / 3.0;
      final side = (cx - px) * ux + (cy - py) * uy + (cz - pz) * uz;
      if (side > 0) {
        groups[f] = groupId;
      } else if (negativeGroupId != null) {
        groups[f] = negativeGroupId;
      }
    }
    return TriMesh(mesh.positions, mesh.indices, faceGroups: groups);
  }

  /// Splits the mesh into shells separated by the plane without discarding
  /// either side.
  static TriMesh slice(TriMesh mesh,
      {required List<double> point, required List<double> normal}) {
    final positive =
        cut(mesh, point: point, normal: normal, keepPositive: true, fill: true);
    final negative = cut(mesh,
        point: point, normal: normal, keepPositive: false, fill: true);
    return _merge(positive, negative);
  }

  static TriMesh _merge(TriMesh a, TriMesh b) {
    final positions = Float32List(a.positions.length + b.positions.length);
    positions.setAll(0, a.positions);
    positions.setAll(a.positions.length, b.positions);
    final indices = Uint32List(a.indices.length + b.indices.length);
    indices.setAll(0, a.indices);
    final offset = a.vertexCount;
    for (var i = 0; i < b.indices.length; i++) {
      indices[a.indices.length + i] = b.indices[i] + offset;
    }
    return TriMesh(positions, indices);
  }
}
