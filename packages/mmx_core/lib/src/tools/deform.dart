import 'dart:math' as math;

import '../mesh/tri_mesh.dart';

/// Soft-move/handle deformation: displaces vertices near a handle with a
/// smooth falloff, the kernel operation behind Meshmixer's Warp/Handle tools.
class SoftMove {
  static TriMesh apply(
    TriMesh mesh, {
    required List<double> center,
    required List<double> offset,
    double radius = 1.0,
  }) {
    if (radius <= 0) return mesh.clone();
    final out = mesh.clone();
    final r2 = radius * radius;
    for (var v = 0; v < out.vertexCount; v++) {
      final dx = out.vx(v) - center[0];
      final dy = out.vy(v) - center[1];
      final dz = out.vz(v) - center[2];
      final d2 = dx * dx + dy * dy + dz * dz;
      if (d2 >= r2) continue;
      final t = 1.0 - d2 / r2;
      final w = t * t * (3.0 - 2.0 * t);
      out.positions[v * 3] += offset[0] * w;
      out.positions[v * 3 + 1] += offset[1] * w;
      out.positions[v * 3 + 2] += offset[2] * w;
    }
    return out;
  }

  /// Radial bend around an axis, approximating the Warp brush.
  static TriMesh bend(
    TriMesh mesh, {
    required List<double> center,
    required List<double> axis,
    double angle = math.pi / 4,
    double radius = 1.0,
  }) {
    final len =
        math.sqrt(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
    if (len < 1e-20 || radius <= 0) return mesh.clone();
    final ax = axis[0] / len, ay = axis[1] / len, az = axis[2] / len;
    final out = mesh.clone();
    for (var v = 0; v < out.vertexCount; v++) {
      final dx = out.vx(v) - center[0];
      final dy = out.vy(v) - center[1];
      final dz = out.vz(v) - center[2];
      final d = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d >= radius) continue;
      final w = 1.0 - d / radius;
      final theta = angle * w;
      // Rodrigues rotation around the axis.
      final c = math.cos(theta), s = math.sin(theta);
      final dot = dx * ax + dy * ay + dz * az;
      final rx = dx * c + (ay * dz - az * dy) * s + ax * dot * (1 - c);
      final ry = dy * c + (az * dx - ax * dz) * s + ay * dot * (1 - c);
      final rz = dz * c + (ax * dy - ay * dx) * s + az * dot * (1 - c);
      out.positions[v * 3] = center[0] + rx;
      out.positions[v * 3 + 1] = center[1] + ry;
      out.positions[v * 3 + 2] = center[2] + rz;
    }
    return out;
  }
}
