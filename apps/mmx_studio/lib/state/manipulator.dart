import 'dart:typed_data';
import 'dart:math' as math;

import 'package:mmx_core/mmx_core.dart';

enum ManipulatorMode { none, translate, rotate, scale, pivot }

List<double> transformPoint(Float64List m, List<double> p) => [
  for (var i = 0; i < 3; i++)
    m[i] * p[0] + m[i + 4] * p[1] + m[i + 8] * p[2] + m[i + 12],
];

/// Inverse affine point transform, including nonuniform scaling and shear.
/// Reject singular transforms instead of silently corrupting a local pivot.
List<double> inverseTransformPoint(Float64List m, List<double> p) {
  final a = m[0], b = m[4], c = m[8];
  final d = m[1], e = m[5], f = m[9];
  final g = m[2], h = m[6], i = m[10];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  final scale = m.take(12).fold<double>(0, (v, n) => n.abs() > v ? n.abs() : v);
  if (!det.isFinite ||
      scale == 0 ||
      det.abs() <= scale * scale * scale * 1e-12) {
    throw const FormatException(
      'Cannot edit the pivot of a singular transform',
    );
  }
  final x = p[0] - m[12], y = p[1] - m[13], z = p[2] - m[14];
  return [
    ((e * i - f * h) * x + (c * h - b * i) * y + (b * f - c * e) * z) / det,
    ((f * g - d * i) * x + (a * i - c * g) * y + (c * d - a * f) * z) / det,
    ((d * h - e * g) * x + (b * g - a * h) * y + (a * e - b * d) * z) / det,
  ];
}

List<double> objectPivotWorld(SceneObject object) {
  final pivot = object.pivot;
  if (pivot != null) return transformPoint(object.transform, pivot.position);
  final bounds = object.mesh.bounds();
  return transformPoint(
    object.transform,
    bounds.isEmpty
        ? [0, 0, 0]
        : [
            (bounds.minX + bounds.maxX) / 2,
            (bounds.minY + bounds.maxY) / 2,
            (bounds.minZ + bounds.maxZ) / 2,
          ],
  );
}

class ManipulatorGesture {
  final SceneObject object;
  final ManipulatorMode mode;
  final int axis;
  final Float64List originalTransform;
  final Pivot? originalPivot;
  final List<double> origin;
  bool changed = false;

  ManipulatorGesture(this.object, this.mode, this.axis)
    : originalTransform = Float64List.fromList(object.transform),
      originalPivot = object.pivot == null
          ? null
          : Pivot(
              position: List<double>.from(object.pivot!.position),
              normal: List<double>.from(object.pivot!.normal),
            ),
      origin = objectPivotWorld(object);

  void preview(double amount) {
    if (!amount.isFinite) return;
    final direction = List<double>.generate(3, (i) => i == axis ? 1 : 0);
    if (mode == ManipulatorMode.pivot) {
      final world = [
        for (var i = 0; i < 3; i++) origin[i] + direction[i] * amount,
      ];
      object.pivot = Pivot(
        position: inverseTransformPoint(originalTransform, world),
        normal: originalPivot?.normal ?? [0, 1, 0],
      );
    } else {
      final delta = switch (mode) {
        ManipulatorMode.translate => translation4(
          direction[0] * amount,
          direction[1] * amount,
          direction[2] * amount,
        ),
        ManipulatorMode.rotate => rotation4(
          direction[0],
          direction[1],
          direction[2],
          amount,
        ),
        ManipulatorMode.scale => scale4(amount.clamp(.01, 100)),
        _ => identity4(),
      };
      final aroundPivot = mode == ManipulatorMode.translate
          ? delta
          : multiply4(
              translation4(origin[0], origin[1], origin[2]),
              multiply4(
                delta,
                translation4(-origin[0], -origin[1], -origin[2]),
              ),
            );
      object.transform = multiply4(aroundPivot, originalTransform);
    }
    changed = mode == ManipulatorMode.scale
        ? (amount - 1).abs() > 1e-9
        : amount.abs() > 1e-9;
  }

  void restore() {
    object.transform = Float64List.fromList(originalTransform);
    object.pivot = originalPivot;
  }
}

List<double> transformNormal(Float64List m, List<double> n) {
  final x =
      (m[5] * m[10] - m[9] * m[6]) * n[0] +
      (m[9] * m[2] - m[1] * m[10]) * n[1] +
      (m[1] * m[6] - m[5] * m[2]) * n[2];
  final y =
      (m[8] * m[6] - m[4] * m[10]) * n[0] +
      (m[0] * m[10] - m[8] * m[2]) * n[1] +
      (m[4] * m[2] - m[0] * m[6]) * n[2];
  final z =
      (m[4] * m[9] - m[8] * m[5]) * n[0] +
      (m[8] * m[1] - m[0] * m[9]) * n[1] +
      (m[0] * m[5] - m[4] * m[1]) * n[2];
  final det =
      m[0] * (m[5] * m[10] - m[9] * m[6]) +
      m[4] * (m[9] * m[2] - m[1] * m[10]) +
      m[8] * (m[1] * m[6] - m[5] * m[2]);
  final normal = [x, y, z];
  final length = math.sqrt(x * x + y * y + z * z);
  if (length == 0 || !length.isFinite) return [0, 1, 0];
  final sign = det < 0 ? -1 : 1;
  return normal.map((v) => sign * v / length).toList();
}
