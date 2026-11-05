import 'dart:math' as math;

import '../mesh/tri_mesh.dart';

/// A scene pivot: a point and an orientation used by transforms and stamps.
/// Meshmixer stores pivots as `PivotSO` records; this is the kernel-side model
/// used by the app when a pivot is created interactively.
class Pivot {
  final List<double> position;
  final List<double> normal;

  const Pivot({required this.position, required this.normal});

  static Pivot atPoint(List<double> point, {List<double>? normal}) => Pivot(
        position: <double>[point[0], point[1], point[2]],
        normal: _normalize(normal ?? <double>[0, 1, 0]),
      );

  /// Creates a pivot at a vertex using the average normal of its incident
  /// faces. Falls back to +Y when the normal is degenerate.
  static Pivot atVertex(TriMesh mesh, int vertex) {
    var nx = 0.0, ny = 0.0, nz = 0.0;
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = mesh.indices[f * 3];
      final b = mesh.indices[f * 3 + 1];
      final c = mesh.indices[f * 3 + 2];
      if (a != vertex && b != vertex && c != vertex) continue;
      final ux = mesh.vx(b) - mesh.vx(a);
      final uy = mesh.vy(b) - mesh.vy(a);
      final uz = mesh.vz(b) - mesh.vz(a);
      final wx = mesh.vx(c) - mesh.vx(a);
      final wy = mesh.vy(c) - mesh.vy(a);
      final wz = mesh.vz(c) - mesh.vz(a);
      nx += uy * wz - uz * wy;
      ny += uz * wx - ux * wz;
      nz += ux * wy - uy * wx;
    }
    return Pivot(
      position: <double>[mesh.vx(vertex), mesh.vy(vertex), mesh.vz(vertex)],
      normal: _normalize(<double>[nx, ny, nz]),
    );
  }

  static List<double> _normalize(List<double> v) {
    final l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l < 1e-20) return <double>[0, 1, 0];
    return <double>[v[0] / l, v[1] / l, v[2] / l];
  }
}
