import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../state/studio_state.dart';

/// 3D viewport. The image is produced by mmx_core's software rasterizer, so
/// the same rendering path works on every platform without a platform view.
class MeshViewport extends StatefulWidget {
  final StudioState state;
  const MeshViewport({super.key, required this.state});

  @override
  State<MeshViewport> createState() => _MeshViewportState();
}

class _MeshViewportState extends State<MeshViewport> {
  Offset? _last;
  bool _brushing = false;
  Offset? _lastBrush;

  // Multi-pointer (touch) state: two fingers orbit and pinch-zoom, matching
  // the tablet gesture set Meshmixer's mobile UI expects.
  final Map<int, Offset> _pointers = <int, Offset>{};
  Offset? _lastCentroid;
  double _lastSpread = 0;

  bool get _brushTool =>
      widget.state.tool == StudioTool.sculpt ||
      widget.state.tool == StudioTool.select;

  Offset _centroid() {
    var sx = 0.0, sy = 0.0;
    for (final p in _pointers.values) {
      sx += p.dx;
      sy += p.dy;
    }
    final n = _pointers.length;
    return Offset(sx / n, sy / n);
  }

  double _spread() {
    final c = _centroid();
    var total = 0.0;
    for (final p in _pointers.values) {
      total += (p - c).distance;
    }
    return _pointers.isEmpty ? 0 : total / _pointers.length;
  }

  void _resetGesture() {
    _last = null;
    _brushing = false;
    _lastBrush = null;
    _lastCentroid = null;
    _lastSpread = 0;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.floor();
        final h = constraints.maxHeight.floor();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) state.setFrameSize(w, h);
        });
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              state.zoom(event.scrollDelta.dy);
            }
          },
          onPointerDown: (event) {
            _pointers[event.pointer] = event.localPosition;
            if (_pointers.length >= 2) {
              _brushing = false;
              _last = null;
              _lastCentroid = _centroid();
              _lastSpread = _spread();
              return;
            }
            _last = event.localPosition;
            _brushing = false;
            final shift = HardwareKeyboard.instance.isShiftPressed;
            final secondary = (event.buttons & kSecondaryMouseButton) != 0;
            if (_brushTool && !shift && !secondary) {
              _brushing = true;
              _lastBrush = event.localPosition;
              if (state.tool == StudioTool.select) {
                state.pickAndSelect(
                  event.localPosition.dx,
                  event.localPosition.dy,
                );
              } else {
                state.sculptAt(event.localPosition.dx, event.localPosition.dy);
              }
            }
          },
          onPointerMove: (event) {
            if (_pointers.containsKey(event.pointer)) {
              _pointers[event.pointer] = event.localPosition;
            }
            if (_pointers.length >= 2) {
              final centroid = _centroid();
              final spread = _spread();
              final lastCentroid = _lastCentroid;
              if (lastCentroid != null) {
                state.orbit(
                  centroid.dx - lastCentroid.dx,
                  centroid.dy - lastCentroid.dy,
                );
                if (_lastSpread > 0 && spread != _lastSpread) {
                  state.zoom(spread - _lastSpread);
                }
              }
              _lastCentroid = centroid;
              _lastSpread = spread;
              return;
            }
            final last = _last;
            if (last == null) return;
            final pos = event.localPosition;
            final dx = pos.dx - last.dx;
            final dy = pos.dy - last.dy;
            final shift = HardwareKeyboard.instance.isShiftPressed;
            final secondary = (event.buttons & kSecondaryMouseButton) != 0;
            if (_brushing && !shift && !secondary) {
              final lb = _lastBrush;
              if (lb != null && (pos - lb).distance > 6) {
                _lastBrush = pos;
                if (state.tool == StudioTool.sculpt) {
                  state.sculptAt(pos.dx, pos.dy);
                } else {
                  state.pickAndSelect(pos.dx, pos.dy);
                }
              }
            } else if (shift || secondary) {
              state.pan(dx, dy);
            } else {
              state.orbit(dx, dy);
            }
            _last = pos;
          },
          onPointerUp: (event) {
            _pointers.remove(event.pointer);
            if (_pointers.length < 2) {
              _lastCentroid = null;
              _lastSpread = 0;
            }
            if (_pointers.isEmpty) {
              _resetGesture();
            } else {
              _last = _pointers.values.first;
            }
          },
          onPointerCancel: (event) {
            _pointers.remove(event.pointer);
            if (_pointers.isEmpty) _resetGesture();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(painter: _FramePainter(state)),
              ),
              Positioned(left: 12, top: 10, child: _Hud(state: state)),
            ],
          ),
        );
      },
    );
  }
}

class _Hud extends StatelessWidget {
  final StudioState state;
  const _Hud({required this.state});

  @override
  Widget build(BuildContext context) {
    final obj = state.selected;
    final faces = obj?.mesh.faceCount ?? 0;
    final verts = obj?.mesh.vertexCount ?? 0;
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${state.tool.name.toUpperCase()}   ${obj?.name ?? "no object"}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$verts verts  $faces faces   render ${state.lastRenderMs}ms',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final StudioState state;
  _FramePainter(this.state) : super(repaint: state);

  @override
  void paint(Canvas canvas, Size size) {
    final img = state.frame;
    if (img == null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFF16181B),
      );
      return;
    }
    final src = Rect.fromLTWH(
      0,
      0,
      img.width.toDouble(),
      img.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => true;
}

/// Utility to hand a ui.Image to a canvas without importing dart:ui elsewhere.
ui.Image? currentFrame(StudioState state) => state.frame;
