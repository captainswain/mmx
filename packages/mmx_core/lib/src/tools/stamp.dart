import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/topology.dart';
import '../mesh/tri_mesh.dart';

/// Procedural stamp patterns for the Stamp tool. Meshmixer stamps displace the
/// surface with a height map; these are analytic equivalents that need no
/// texture assets, plus a deterministic noise pattern.
enum StampPattern { circle, ring, star, grid, noise }

/// Surface displacement stamping: vertices inside the brush footprint are
/// pushed along their normals by the pattern height times a radial falloff.
class StampTool {
  static TriMesh apply(
    TriMesh mesh, {
    required List<double> center,
    required double radius,
    required double height,
    StampPattern pattern = StampPattern.circle,
    bool preserveBoundary = true,
  }) {
    final work = mesh.clone();
    final topo = MeshTopology(work);
    final boundary = <int>{};
    if (preserveBoundary) {
      for (final e in topo.boundaryEdges()) {
        boundary.add(e[0]);
        boundary.add(e[1]);
      }
    }
    final normals = _vertexNormals(work, topo);
    final cx = center[0], cy = center[1], cz = center[2];
    final positions = Float32List.fromList(work.positions);
    for (var v = 0; v < work.vertexCount; v++) {
      if (boundary.contains(v)) continue;
      final dx = work.vx(v) - cx;
      final dy = work.vy(v) - cy;
      final dz = work.vz(v) - cz;
      final d = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d > radius) continue;
      final t = d / radius;
      final falloff = (1 - t * t) * (1 - t * t);
      final h = _pattern(pattern, t, dx, dy, dz, radius);
      if (h == 0) continue;
      positions[v * 3] += normals[v * 3] * h * height * falloff;
      positions[v * 3 + 1] += normals[v * 3 + 1] * h * height * falloff;
      positions[v * 3 + 2] += normals[v * 3 + 2] * h * height * falloff;
    }
    work.positions = positions;
    return work;
  }

  static double _pattern(StampPattern pattern, double t, double dx, double dy,
      double dz, double radius) {
    switch (pattern) {
      case StampPattern.circle:
        // Smooth dome, flat at the rim.
        return t < 0.75 ? math.sqrt(1 - (t / 0.75) * (t / 0.75)) : 0;
      case StampPattern.ring:
        final band = (t - 0.65) / 0.2;
        return band.abs() < 1 ? 1 - band.abs() : 0;
      case StampPattern.star:
        final ang = math.atan2(dy, dx);
        final lobes = 0.5 + 0.5 * math.cos(5 * ang);
        return t < 0.8 ? lobes * (1 - t / 0.8) : 0;
      case StampPattern.grid:
        final cell = 2 * math.pi * 6 * t;
        return (0.5 + 0.5 * math.cos(cell)) * (1 - t);
      case StampPattern.noise:
        // Deterministic hash of the direction, so repeated stamps match.
        final h = (math.sin(dx * 12.9898 + dy * 78.233 + dz * 37.719) *
                43758.5453) %
            1.0;
        return (h.abs() * 2 - 1) * (1 - t);
    }
  }

  static Float32List _vertexNormals(TriMesh mesh, MeshTopology topo) {
    final n = Float32List(mesh.vertexCount * 3);
    for (var f = 0; f < mesh.faceCount; f++) {
      final ia = mesh.indices[f * 3], ib = mesh.indices[f * 3 + 1],
          ic = mesh.indices[f * 3 + 2];
      final ax = mesh.vx(ia), ay = mesh.vy(ia), az = mesh.vz(ia);
      final ux = mesh.vx(ib) - ax, uy = mesh.vy(ib) - ay, uz = mesh.vz(ib) - az;
      final wx = mesh.vx(ic) - ax, wy = mesh.vy(ic) - ay, wz = mesh.vz(ic) - az;
      final nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
      for (final v in <int>[ia, ib, ic]) {
        n[v * 3] += nx;
        n[v * 3 + 1] += ny;
        n[v * 3 + 2] += nz;
      }
    }
    for (var v = 0; v < mesh.vertexCount; v++) {
      final l = math.sqrt(n[v * 3] * n[v * 3] +
          n[v * 3 + 1] * n[v * 3 + 1] +
          n[v * 3 + 2] * n[v * 3 + 2]);
      if (l > 1e-12) {
        n[v * 3] /= l;
        n[v * 3 + 1] /= l;
        n[v * 3 + 2] /= l;
      } else {
        n[v * 3 + 2] = 1;
      }
    }
    return n;
  }
}
