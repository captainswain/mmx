import 'dart:math' as math;

/// Bounded ear clipping of a simple polygon projected onto its dominant plane.
/// [inferred] Import behavior: preserve original winding and vertex indices;
/// reject self-intersections instead of inventing overlapping fan triangles.
List<int> triangulatePolygon(List<double> positions, List<int> polygon) {
  if (polygon.length < 3 || polygon.length > 4096) {
    throw const FormatException('Polygon must contain 3–4096 vertices');
  }
  final nVertices = positions.length ~/ 3;
  if (polygon.any((i) => i < 0 || i >= nVertices)) {
    throw const FormatException('Polygon index out of range');
  }
  if (polygon.length == 3) return List<int>.from(polygon);
  final ids = <int>[];
  for (final id in polygon) {
    if (ids.isEmpty || id != ids.last) ids.add(id);
  }
  if (ids.length > 1 && ids.first == ids.last) ids.removeLast();
  if (ids.length < 3 || ids.toSet().length != ids.length) {
    throw const FormatException('Repeated polygon vertices');
  }
  var nx = 0.0, ny = 0.0, nz = 0.0;
  final origin = ids.first * 3;
  for (var k = 0; k < ids.length; k++) {
    final a = ids[k] * 3, b = ids[(k + 1) % ids.length] * 3;
    final ax = positions[a] - positions[origin],
        ay = positions[a + 1] - positions[origin + 1],
        az = positions[a + 2] - positions[origin + 2];
    final bx = positions[b] - positions[origin],
        by = positions[b + 1] - positions[origin + 1],
        bz = positions[b + 2] - positions[origin + 2];
    nx += ay * bz - az * by;
    ny += az * bx - ax * bz;
    nz += ax * by - ay * bx;
  }
  final drop = nx.abs() >= ny.abs() && nx.abs() >= nz.abs()
      ? 0
      : ny.abs() >= nz.abs()
          ? 1
          : 2;
  final u = (drop + 1) % 3, v = (drop + 2) % 3;
  var span = 0.0;
  for (final id in ids) {
    span = math.max(
        span,
        math.max((positions[id * 3 + u] - positions[origin + u]).abs(),
            (positions[id * 3 + v] - positions[origin + v]).abs()));
  }
  if (!span.isFinite || span == 0) {
    throw const FormatException('Degenerate polygon');
  }
  final xs = [
    for (final id in ids) (positions[id * 3 + u] - positions[origin + u]) / span
  ];
  final ys = [
    for (final id in ids) (positions[id * 3 + v] - positions[origin + v]) / span
  ];
  double cross(int a, int b, int c) =>
      (xs[b] - xs[a]) * (ys[c] - ys[a]) - (ys[b] - ys[a]) * (xs[c] - xs[a]);
  const epsilon = 1e-12;
  var budget = 4000000;
  void tick() {
    if (--budget < 0) {
      throw const FormatException('Polygon complexity limit exceeded');
    }
  }

  bool onSegment(int a, int b, int c) =>
      cross(a, b, c).abs() <= epsilon &&
      xs[c] >= math.min(xs[a], xs[b]) - epsilon &&
      xs[c] <= math.max(xs[a], xs[b]) + epsilon &&
      ys[c] >= math.min(ys[a], ys[b]) - epsilon &&
      ys[c] <= math.max(ys[a], ys[b]) + epsilon;
  final n = ids.length;
  for (var a = 0; a < n; a++) {
    final b = (a + 1) % n;
    for (var c = a + 1; c < n; c++) {
      tick();
      final d = (c + 1) % n;
      if (a == d || b == c) continue;
      final abC = cross(a, b, c),
          abD = cross(a, b, d),
          cdA = cross(c, d, a),
          cdB = cross(c, d, b);
      if ((abC * abD < 0 && cdA * cdB < 0) ||
          onSegment(a, b, c) ||
          onSegment(a, b, d) ||
          onSegment(c, d, a) ||
          onSegment(c, d, b)) {
        throw const FormatException('Self-intersecting polygon');
      }
    }
  }
  var area = 0.0;
  for (var i = 0; i < n; i++) {
    area += xs[i] * ys[(i + 1) % n] - xs[(i + 1) % n] * ys[i];
  }
  if (area.abs() <= epsilon) throw const FormatException('Degenerate polygon');
  final sign = area > 0 ? 1 : -1;
  final remaining = List<int>.generate(n, (i) => i);
  final out = <int>[];
  while (remaining.length > 3) {
    var removed = false;
    for (var i = 0; i < remaining.length; i++) {
      final a = remaining[(i + remaining.length - 1) % remaining.length],
          b = remaining[i],
          c = remaining[(i + 1) % remaining.length];
      final bend = cross(a, b, c) * sign;
      if (bend.abs() <= epsilon && onSegment(a, c, b)) {
        remaining.removeAt(i);
        removed = true;
        break;
      }
      if (bend <= epsilon) continue;
      var contains = false;
      for (final p in remaining) {
        tick();
        if (p == a || p == b || p == c) continue;
        if (cross(a, b, p) * sign >= -epsilon &&
            cross(b, c, p) * sign >= -epsilon &&
            cross(c, a, p) * sign >= -epsilon) {
          contains = true;
          break;
        }
      }
      if (contains) continue;
      out.addAll([ids[a], ids[b], ids[c]]);
      remaining.removeAt(i);
      removed = true;
      break;
    }
    if (!removed) throw const FormatException('Cannot triangulate polygon');
  }
  if (remaining.length == 3 &&
      cross(remaining[0], remaining[1], remaining[2]).abs() > epsilon) {
    out.addAll(remaining.map((i) => ids[i]));
  }
  return out;
}
