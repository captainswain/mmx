import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/manipulator.dart';
import '../state/studio_state.dart';

/// Projection shared by painting, hit testing and screen-to-world dragging.
class GizmoProjection {
  final Offset origin;
  final List<Offset?> handles;
  final double worldLength;
  const GizmoProjection(this.origin, this.handles, this.worldLength);

  static GizmoProjection? forState(StudioState state, Size size) {
    final object = state.selected;
    if (object == null || size.width <= 0 || size.height <= 0) return null;
    final world = objectPivotWorld(object);
    final matrix = state.camera.viewProjection(size.width / size.height);
    Offset? project(List<double> p) {
      final w =
          matrix[3] * p[0] + matrix[7] * p[1] + matrix[11] * p[2] + matrix[15];
      if (!w.isFinite || w <= state.camera.near) return null;
      final x =
          (matrix[0] * p[0] +
              matrix[4] * p[1] +
              matrix[8] * p[2] +
              matrix[12]) /
          w;
      final y =
          (matrix[1] * p[0] +
              matrix[5] * p[1] +
              matrix[9] * p[2] +
              matrix[13]) /
          w;
      return Offset((x + 1) * size.width / 2, (1 - y) * size.height / 2);
    }

    final origin = project(world);
    if (origin == null) return null;
    final eye = state.camera.position();
    final distance = math.sqrt(
      List.generate(
        3,
        (i) => math.pow(eye[i] - world[i], 2),
      ).reduce((a, b) => a + b),
    );
    final length =
        distance *
        math.tan(state.camera.fovDegrees * math.pi / 360) *
        144 /
        size.height;
    final handles = [
      for (var axis = 0; axis < 3; axis++)
        project([
          for (var i = 0; i < 3; i++) world[i] + (i == axis ? length : 0),
        ]),
    ];
    return GizmoProjection(origin, handles, length);
  }

  int? hitTest(Offset position) {
    var best = 12.0;
    int? axis;
    for (var i = 0; i < 3; i++) {
      final handle = handles[i];
      if (handle == null || (handle - origin).distance < 18) continue;
      final v = handle - origin, q = position - origin;
      final t = ((q.dx * v.dx + q.dy * v.dy) / v.distanceSquared).clamp(
        .25,
        1.0,
      );
      final distance = (position - (origin + v * t)).distance;
      if (distance < best) {
        best = distance;
        axis = i;
      }
    }
    return axis;
  }

  double dragAmount(
    ManipulatorMode mode,
    int axis,
    Offset start,
    Offset current,
  ) {
    if (mode == ManipulatorMode.rotate) {
      final a = start - origin, b = current - origin;
      return math.atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy);
    }
    if (mode == ManipulatorMode.scale) {
      return math.exp(
        ((current.dx - start.dx) - (current.dy - start.dy)) / 100,
      );
    }
    final v = handles[axis]! - origin, delta = current - start;
    return (delta.dx * v.dx + delta.dy * v.dy) /
        v.distanceSquared *
        worldLength;
  }
}

class GizmoPainter extends CustomPainter {
  final StudioState state;
  GizmoPainter(this.state) : super(repaint: state);
  @override
  void paint(Canvas canvas, Size size) {
    if (state.manipulatorMode == ManipulatorMode.none ||
        (state.tool != StudioTool.navigate &&
            state.tool != StudioTool.modify)) {
      return;
    }
    final p = GizmoProjection.forState(state, size);
    if (p == null) return;
    const colors = [
      Colors.redAccent,
      Colors.greenAccent,
      Colors.lightBlueAccent,
    ];
    for (var i = 0; i < 3; i++) {
      final end = p.handles[i];
      if (end == null || (end - p.origin).distance < 18) continue;
      final paint = Paint()
        ..color = colors[i]
        ..strokeWidth = 3;
      canvas.drawLine(p.origin, end, paint);
      if (state.manipulatorMode == ManipulatorMode.rotate) {
        canvas.drawCircle(end, 9, paint..style = PaintingStyle.stroke);
      } else if (state.manipulatorMode == ManipulatorMode.scale) {
        canvas.drawRect(
          Rect.fromCenter(center: end, width: 13, height: 13),
          paint,
        );
      } else {
        canvas.drawCircle(end, 7, paint);
      }
      final label = TextPainter(
        text: TextSpan(
          text: ['X', 'Y', 'Z'][i],
          style: TextStyle(
            color: colors[i],
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, end + const Offset(10, -8));
    }
    canvas.drawCircle(p.origin, 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant GizmoPainter oldDelegate) => true;
}
