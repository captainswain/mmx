import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import 'modify.dart';

/// Generates a tube along a polyline, matching Meshmixer's Add Tube action.
class AddTube {
  /// Builds a capped tube of [radius] around [points]. [segments] controls the
  /// ring resolution. Consecutive duplicate points are ignored.
  static TriMesh build(
    List<List<double>> points, {
    double radius = 1.0,
    int segments = 12,
    bool caps = true,
  }) {
    final path = <List<double>>[];
    for (final p in points) {
      if (p.length < 3) continue;
      if (path.isNotEmpty) {
        final last = path.last;
        final dx = p[0] - last[0], dy = p[1] - last[1], dz = p[2] - last[2];
        if (dx * dx + dy * dy + dz * dz < 1e-20) continue;
      }
      path.add(<double>[p[0], p[1], p[2]]);
    }
    if (path.length < 2 || segments < 3) {
      return TriMesh(Float32List(0), Uint32List(0));
    }

    final builder = MeshBuilder();
    final rings = <List<int>>[];
    List<double>? normal;
    for (var i = 0; i < path.length; i++) {
      final tangent = _tangent(path, i);
      if (normal == null) {
        normal = _perpendicular(tangent);
      } else {
        // Parallel-transport the frame so the tube does not twist.
        final dot = normal[0] * tangent[0] +
            normal[1] * tangent[1] +
            normal[2] * tangent[2];
        normal = _normalize(<double>[
          normal[0] - tangent[0] * dot,
          normal[1] - tangent[1] * dot,
          normal[2] - tangent[2] * dot,
        ]);
      }
      final binormal = _cross(tangent, normal);
      final ring = <int>[];
      for (var s = 0; s < segments; s++) {
        final a = 2 * math.pi * s / segments;
        final c = math.cos(a), sn = math.sin(a);
        ring.add(builder.addVertex(
          path[i][0] + radius * (normal[0] * c + binormal[0] * sn),
          path[i][1] + radius * (normal[1] * c + binormal[1] * sn),
          path[i][2] + radius * (normal[2] * c + binormal[2] * sn),
        ));
      }
      rings.add(ring);
    }

    for (var i = 0; i + 1 < rings.length; i++) {
      final a = rings[i], b = rings[i + 1];
      for (var s = 0; s < segments; s++) {
        final s2 = (s + 1) % segments;
        builder.addTriangle(a[s], b[s2], b[s]);
        builder.addTriangle(a[s], a[s2], b[s2]);
      }
    }

    if (caps) {
      final first = rings.first;
      final last = rings.last;
      final c0 = builder.addVertex(path.first[0], path.first[1], path.first[2]);
      final c1 = builder.addVertex(path.last[0], path.last[1], path.last[2]);
      for (var s = 0; s < segments; s++) {
        final s2 = (s + 1) % segments;
        builder.addTriangle(c0, first[s], first[s2]);
        builder.addTriangle(c1, last[s2], last[s]);
      }
    }

    return builder.build();
  }

  /// Adds a tube to [mesh] and returns the combined mesh.
  static TriMesh addTo(
    TriMesh mesh,
    List<List<double>> points, {
    double radius = 1.0,
    int segments = 12,
  }) {
    final tube = build(points, radius: radius, segments: segments);
    if (tube.faceCount == 0) return mesh.clone();
    return Modify.combine(<TriMesh>[mesh, tube]);
  }

  static List<double> _tangent(List<List<double>> path, int i) {
    final a = path[i == 0 ? 0 : i - 1];
    final b = path[i == path.length - 1 ? i : i + 1];
    return _normalize(<double>[b[0] - a[0], b[1] - a[1], b[2] - a[2]]);
  }

  static List<double> _perpendicular(List<double> t) {
    final up = t[2].abs() < 0.9 ? <double>[0, 0, 1] : <double>[1, 0, 0];
    return _normalize(_cross(t, up));
  }

  static List<double> _cross(List<double> a, List<double> b) => <double>[
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];

  static List<double> _normalize(List<double> v) {
    final l = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l < 1e-20) return <double>[0, 0, 1];
    return <double>[v[0] / l, v[1] / l, v[2] / l];
  }
}
