import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';

/// Creates a flat polygon from a boundary loop or a point list, matching the
/// Edit panel's Make Polygon action. Concave loops are triangulated with ear
/// clipping rather than a fan, which would produce overlapping triangles.
class MakePolygon {
  static TriMesh fromLoop(TriMesh mesh, List<int> loop) {
    if (loop.length < 3) return TriMesh(Float32List(0), Uint32List(0));
    final points = <List<double>>[
      for (final v in loop) <double>[mesh.vx(v), mesh.vy(v), mesh.vz(v)],
    ];
    return _build(points);
  }

  static TriMesh fromPoints(List<List<double>> points) {
    if (points.length < 3) return TriMesh(Float32List(0), Uint32List(0));
    final clean = <List<double>>[
      for (final p in points)
        if (p.length >= 3) <double>[p[0], p[1], p[2]],
    ];
    return _build(clean);
  }

  static TriMesh _build(List<List<double>> points) {
    if (points.length < 3) return TriMesh(Float32List(0), Uint32List(0));
    final projected = _project(points);
    var tris = _earClip(projected.points, projected.ccw);
    if (tris.isEmpty) {
      tris = _fan(points.length, projected.ccw);
    }
    final builder = MeshBuilder();
    final ids = <int>[
      for (final p in points) builder.addVertex(p[0], p[1], p[2]),
    ];
    for (final t in tris) {
      builder.addTriangle(ids[t[0]], ids[t[1]], ids[t[2]]);
    }
    return builder.build();
  }

  /// Projects a 3D polygon onto its best-fit plane and returns the 2D points
  /// plus the winding direction of the original loop.
  static ({List<List<double>> points, bool ccw}) _project(
      List<List<double>> points) {
    var nx = 0.0, ny = 0.0, nz = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      nx += (a[1] - b[1]) * (a[2] + b[2]);
      ny += (a[2] - b[2]) * (a[0] + b[0]);
      nz += (a[0] - b[0]) * (a[1] + b[1]);
    }
    var nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl < 1e-12) {
      nx = 0;
      ny = 0;
      nz = 1;
      nl = 1;
    }
    nx /= nl;
    ny /= nl;
    nz /= nl;
    var refx = 0.0, refy = 0.0, refz = 0.0;
    if (nx.abs() < 0.9) {
      refx = 0;
      refy = -nz;
      refz = ny;
    } else {
      refx = nz;
      refy = 0;
      refz = -nx;
    }
    final rl = math.sqrt(refx * refx + refy * refy + refz * refz);
    refx /= rl;
    refy /= rl;
    refz /= rl;
    final bx = ny * refz - nz * refy;
    final by = nz * refx - nx * refz;
    final bz = nx * refy - ny * refx;
    final ox = points[0][0], oy = points[0][1], oz = points[0][2];
    final projected = <List<double>>[];
    for (final p in points) {
      final dx = p[0] - ox, dy = p[1] - oy, dz = p[2] - oz;
      projected.add(<double>[
        dx * refx + dy * refy + dz * refz,
        dx * bx + dy * by + dz * bz,
      ]);
    }
    final area = _signedArea(projected);
    return (points: projected, ccw: area > 0);
  }

  static double _signedArea(List<List<double>> pts) {
    var s = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      s += a[0] * b[1] - b[0] * a[1];
    }
    return s * 0.5;
  }

  static List<List<int>> _fan(int n, bool ccw) {
    final out = <List<int>>[];
    for (var i = 1; i + 1 < n; i++) {
      out.add(ccw ? <int>[0, i, i + 1] : <int>[0, i + 1, i]);
    }
    return out;
  }

  static List<List<int>> _earClip(List<List<double>> pts, bool ccw) {
    final n = pts.length;
    if (n < 3) return <List<int>>[];
    final idx = List<int>.generate(n, (i) => i);
    if (!ccw) {
      final rev = idx.reversed.toList();
      idx.setAll(0, rev);
    }
    final out = <List<int>>[];
    var guard = 0;
    while (idx.length > 3 && guard++ < n * n) {
      var best = -1;
      var bestScore = double.infinity;
      for (var i = 0; i < idx.length; i++) {
        final prev = idx[(i - 1 + idx.length) % idx.length];
        final cur = idx[i];
        final next = idx[(i + 1) % idx.length];
        if (!_isConvex(pts, prev, cur, next)) continue;
        if (_containsAny(pts, idx, prev, cur, next)) continue;
        final score = _triArea(pts[prev], pts[cur], pts[next]);
        if (score < bestScore) {
          bestScore = score;
          best = i;
        }
      }
      if (best < 0) break;
      final prev = idx[(best - 1 + idx.length) % idx.length];
      final cur = idx[best];
      final next = idx[(best + 1) % idx.length];
      out.add(<int>[prev, cur, next]);
      idx.removeAt(best);
    }
    if (idx.length == 3) out.add(<int>[idx[0], idx[1], idx[2]]);
    if (!ccw) {
      for (final t in out) {
        final tmp = t[1];
        t[1] = t[2];
        t[2] = tmp;
      }
    }
    return out;
  }

  static bool _isConvex(List<List<double>> p, int a, int b, int c) {
    final ax = p[b][0] - p[a][0], ay = p[b][1] - p[a][1];
    final bx = p[c][0] - p[b][0], by = p[c][1] - p[b][1];
    return ax * by - ay * bx > 0;
  }

  static bool _containsAny(
      List<List<double>> p, List<int> idx, int a, int b, int c) {
    for (final i in idx) {
      if (i == a || i == b || i == c) continue;
      if (_pointInTriangle(p[i], p[a], p[b], p[c])) return true;
    }
    return false;
  }

  static bool _pointInTriangle(
      List<double> p, List<double> a, List<double> b, List<double> c) {
    double sign(List<double> p1, List<double> p2, List<double> p3) =>
        (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1]);
    final d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a);
    final hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
    final hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
    return !(hasNeg && hasPos);
  }

  static double _triArea(List<double> a, List<double> b, List<double> c) {
    return ((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))
            .abs() *
        0.5;
  }
}
