import 'dart:math' as math;

/// Orbit camera for the viewport. Yaw/pitch/distance/target plus perspective
/// parameters; produces column-major view and projection matrices.
class Camera {
  double yaw;
  double pitch;
  double distance;
  List<double> target;
  double fovDegrees;
  double near;
  double far;

  Camera({
    this.yaw = 0.6,
    this.pitch = 0.35,
    this.distance = 3.0,
    List<double>? target,
    this.fovDegrees = 45,
    this.near = 0.01,
    this.far = 10000,
  }) : target = target ?? <double>[0, 0, 0];

  Camera clone() => Camera(
        yaw: yaw,
        pitch: pitch,
        distance: distance,
        target: List<double>.from(target),
        fovDegrees: fovDegrees,
        near: near,
        far: far,
      );

  /// Camera position in world space.
  List<double> position() {
    final cp = math.cos(pitch);
    return <double>[
      target[0] + distance * cp * math.sin(yaw),
      target[1] + distance * math.sin(pitch),
      target[2] + distance * cp * math.cos(yaw),
    ];
  }

  void orbit(double dYaw, double dPitch) {
    yaw += dYaw;
    pitch = (pitch + dPitch).clamp(-1.55, 1.55);
  }

  void pan(double dx, double dy) {
    // Pan in the camera's right/up plane, scaled by distance.
    final right = <double>[math.cos(yaw), 0, -math.sin(yaw)];
    final up = <double>[0, 1, 0];
    final s = distance * 0.0015;
    target[0] += (-right[0] * dx + up[0] * dy) * s;
    target[1] += (-right[1] * dx + up[1] * dy) * s;
    target[2] += (-right[2] * dx + up[2] * dy) * s;
  }

  void zoom(double factor) {
    distance = (distance * factor).clamp(near * 4, far * 0.5);
  }

  /// Column-major view matrix.
  List<double> viewMatrix() {
    final eye = position();
    final f = _normalize(<double>[
      target[0] - eye[0],
      target[1] - eye[1],
      target[2] - eye[2],
    ]);
    final upWorld = <double>[0, 1, 0];
    final s = _normalize(_cross(f, upWorld));
    final u = _cross(s, f);
    return <double>[
      s[0],
      u[0],
      -f[0],
      0,
      s[1],
      u[1],
      -f[1],
      0,
      s[2],
      u[2],
      -f[2],
      0,
      -_dot(s, eye),
      -_dot(u, eye),
      _dot(f, eye),
      1,
    ];
  }

  /// Column-major perspective projection.
  List<double> projectionMatrix(double aspect) {
    final f = 1.0 / math.tan(fovDegrees * math.pi / 360.0);
    final nf = 1.0 / (near - far);
    return <double>[
      f / aspect,
      0,
      0,
      0,
      0,
      f,
      0,
      0,
      0,
      0,
      (far + near) * nf,
      -1,
      0,
      0,
      2 * far * near * nf,
      0,
    ];
  }

  /// Convenience: projection * view.
  List<double> viewProjection(double aspect) =>
      _multiply(projectionMatrix(aspect), viewMatrix());

  /// Frames the given world-space bounding box.
  void frame(double minX, double minY, double minZ, double maxX, double maxY,
      double maxZ) {
    target = <double>[(minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2];
    final dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
    final r = math.sqrt(dx * dx + dy * dy + dz * dz) / 2;
    distance = math.max(r * 2.6, 0.1);
    near = math.max(distance * 0.001, 0.001);
    far = distance * 20;
  }

  static List<double> _normalize(List<double> v) {
    final l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l < 1e-12) return <double>[0, 0, 1];
    return <double>[v[0] / l, v[1] / l, v[2] / l];
  }

  static List<double> _cross(List<double> a, List<double> b) => <double>[
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];

  static double _dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  static List<double> _multiply(List<double> a, List<double> b) {
    final out = List<double>.filled(16, 0);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[k * 4 + row] * b[col * 4 + k];
        }
        out[col * 4 + row] = s;
      }
    }
    return out;
  }

  /// Builds a world-space ray through the given screen pixel.
  Ray screenToRay(double sx, double sy, double width, double height) {
    final inv = _invert(viewProjection(width / height));
    List<double> unproject(double z) {
      final nx = sx / width * 2 - 1;
      final ny = 1 - sy / height * 2;
      final x = inv[0] * nx + inv[4] * ny + inv[8] * z + inv[12];
      final y = inv[1] * nx + inv[5] * ny + inv[9] * z + inv[13];
      final zz = inv[2] * nx + inv[6] * ny + inv[10] * z + inv[14];
      final w = inv[3] * nx + inv[7] * ny + inv[11] * z + inv[15];
      final iw = w.abs() < 1e-12 ? 1e12 : 1 / w;
      return <double>[x * iw, y * iw, zz * iw];
    }

    final nearPoint = unproject(-1);
    final farPoint = unproject(1);
    final dir = _normalize(<double>[
      farPoint[0] - nearPoint[0],
      farPoint[1] - nearPoint[1],
      farPoint[2] - nearPoint[2],
    ]);
    return Ray(nearPoint, dir);
  }

  /// General 4x4 inverse (cofactor expansion).
  static List<double> _invert(List<double> m) {
    final a = List<double>.from(m);
    final inv = List<double>.filled(16, 0);
    inv[0] = a[5] * a[10] * a[15] -
        a[5] * a[11] * a[14] -
        a[9] * a[6] * a[15] +
        a[9] * a[7] * a[14] +
        a[13] * a[6] * a[11] -
        a[13] * a[7] * a[10];
    inv[4] = -a[4] * a[10] * a[15] +
        a[4] * a[11] * a[14] +
        a[8] * a[6] * a[15] -
        a[8] * a[7] * a[14] -
        a[12] * a[6] * a[11] +
        a[12] * a[7] * a[10];
    inv[8] = a[4] * a[9] * a[15] -
        a[4] * a[11] * a[13] -
        a[8] * a[5] * a[15] +
        a[8] * a[7] * a[13] +
        a[12] * a[5] * a[11] -
        a[12] * a[7] * a[9];
    inv[12] = -a[4] * a[9] * a[14] +
        a[4] * a[10] * a[13] +
        a[8] * a[5] * a[14] -
        a[8] * a[6] * a[13] -
        a[12] * a[5] * a[10] +
        a[12] * a[6] * a[9];
    inv[1] = -a[1] * a[10] * a[15] +
        a[1] * a[11] * a[14] +
        a[9] * a[2] * a[15] -
        a[9] * a[3] * a[14] -
        a[13] * a[2] * a[11] +
        a[13] * a[3] * a[10];
    inv[5] = a[0] * a[10] * a[15] -
        a[0] * a[11] * a[14] -
        a[8] * a[2] * a[15] +
        a[8] * a[3] * a[14] +
        a[12] * a[2] * a[11] -
        a[12] * a[3] * a[10];
    inv[9] = -a[0] * a[9] * a[15] +
        a[0] * a[11] * a[13] +
        a[8] * a[1] * a[15] -
        a[8] * a[3] * a[13] -
        a[12] * a[1] * a[11] +
        a[12] * a[3] * a[9];
    inv[13] = a[0] * a[9] * a[14] -
        a[0] * a[10] * a[13] -
        a[8] * a[1] * a[14] +
        a[8] * a[2] * a[13] +
        a[12] * a[1] * a[10] -
        a[12] * a[2] * a[9];
    inv[2] = a[1] * a[6] * a[15] -
        a[1] * a[7] * a[14] -
        a[5] * a[2] * a[15] +
        a[5] * a[3] * a[14] +
        a[13] * a[2] * a[7] -
        a[13] * a[3] * a[6];
    inv[6] = -a[0] * a[6] * a[15] +
        a[0] * a[7] * a[14] +
        a[4] * a[2] * a[15] -
        a[4] * a[3] * a[14] -
        a[12] * a[2] * a[7] +
        a[12] * a[3] * a[6];
    inv[10] = a[0] * a[5] * a[15] -
        a[0] * a[7] * a[13] -
        a[4] * a[1] * a[15] +
        a[4] * a[3] * a[13] +
        a[12] * a[1] * a[7] -
        a[12] * a[3] * a[5];
    inv[14] = -a[0] * a[5] * a[14] +
        a[0] * a[6] * a[13] +
        a[4] * a[1] * a[14] -
        a[4] * a[2] * a[13] -
        a[12] * a[1] * a[6] +
        a[12] * a[2] * a[5];
    inv[3] = -a[1] * a[6] * a[11] +
        a[1] * a[7] * a[10] +
        a[5] * a[2] * a[11] -
        a[5] * a[3] * a[10] -
        a[9] * a[2] * a[7] +
        a[9] * a[3] * a[6];
    inv[7] = a[0] * a[6] * a[11] -
        a[0] * a[7] * a[10] -
        a[4] * a[2] * a[11] +
        a[4] * a[3] * a[10] +
        a[8] * a[2] * a[7] -
        a[8] * a[3] * a[6];
    inv[11] = -a[0] * a[5] * a[11] +
        a[0] * a[7] * a[9] +
        a[4] * a[1] * a[11] -
        a[4] * a[3] * a[9] -
        a[8] * a[1] * a[7] +
        a[8] * a[3] * a[5];
    inv[15] = a[0] * a[5] * a[10] -
        a[0] * a[6] * a[9] -
        a[4] * a[1] * a[10] +
        a[4] * a[2] * a[9] +
        a[8] * a[1] * a[6] -
        a[8] * a[2] * a[5];
    final det = a[0] * inv[0] + a[1] * inv[4] + a[2] * inv[8] + a[3] * inv[12];
    if (det.abs() < 1e-18) return m;
    final id = 1.0 / det;
    for (var i = 0; i < 16; i++) {
      inv[i] *= id;
    }
    return inv;
  }
}

class Ray {
  final List<double> origin;
  final List<double> direction;
  Ray(this.origin, this.direction);
}
