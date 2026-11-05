import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import 'complex.dart';

/// A mesh with a per-vertex UV coordinate set.
class UvMesh {
  final TriMesh mesh;
  final Float32List uv;

  const UvMesh(this.mesh, this.uv);
}

/// Planar UV unwrapping, the simple projection Meshmixer uses for
/// "Unwrap: Planar" on a face group or shell.
class Unwrap {
  /// Projects [mesh] onto the plane perpendicular to [axis] and normalizes the
  /// result into 0..1. [axis] is 0 (x), 1 (y) or 2 (z).
  static UvMesh planar(TriMesh mesh, {int axis = 1}) {
    if (mesh.vertexCount == 0) return UvMesh(mesh, Float32List(0));
    final b = mesh.bounds();
    final minX = b.minX, minY = b.minY, minZ = b.minZ;
    final ex = b.extentX == 0 ? 1.0 : b.extentX;
    final ey = b.extentY == 0 ? 1.0 : b.extentY;
    final ez = b.extentZ == 0 ? 1.0 : b.extentZ;
    final uv = Float32List(mesh.vertexCount * 2);
    for (var v = 0; v < mesh.vertexCount; v++) {
      final x = mesh.vx(v), y = mesh.vy(v), z = mesh.vz(v);
      double u, w;
      switch (axis) {
        case 0:
          u = (z - minZ) / ez;
          w = (y - minY) / ey;
        case 2:
          u = (x - minX) / ex;
          w = (y - minY) / ey;
        default:
          u = (x - minX) / ex;
          w = (z - minZ) / ez;
      }
      uv[v * 2] = u.clamp(0.0, 1.0);
      uv[v * 2 + 1] = w.clamp(0.0, 1.0);
    }
    return UvMesh(mesh, uv);
  }

  /// Unwraps each connected shell separately, so overlapping shells do not
  /// share a single planar projection.
  static List<UvMesh> perComponent(TriMesh mesh, {int axis = 1}) {
    return ComplexTools.split(mesh)
        .map((part) => planar(part, axis: axis))
        .toList();
  }
}
