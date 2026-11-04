import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import '../spatial/bvh.dart';

/// Rigid alignment (ICP) of a source mesh onto a target surface, matching
/// Meshmixer's Align tool: sample source vertices, find closest target points,
/// reject outliers, solve the rigid transform with Horn's quaternion method,
/// and iterate.
class AlignTool {
  /// Returns the column-major 4x4 transform that maps [source] onto [target].
  static Float64List solve(
    TriMesh source,
    TriMesh target, {
    int iterations = 30,
    int maxSamples = 2500,
    double outlierFraction = 0.2,
  }) {
    final bvh = TriangleBVH.build(target);
    final step = math.max(1, source.vertexCount ~/ maxSamples);
    final sampleIdx = <int>[];
    for (var v = 0; v < source.vertexCount; v += step) {
      sampleIdx.add(v);
    }
    if (sampleIdx.length < 3) return _identity();

    var transform = _identity();
    final scratch = Float32List(source.positions.length);
    for (var it = 0; it < iterations; it++) {
      scratch.setAll(0, source.positions);
      _apply(scratch, transform);
      final from = <List<double>>[];
      final to = <List<double>>[];
      final dists = <double>[];
      for (final v in sampleIdx) {
        final x = scratch[v * 3], y = scratch[v * 3 + 1], z = scratch[v * 3 + 2];
        final hit = bvh.closestPoint(x, y, z);
        if (hit == null) continue;
        from.add(<double>[x, y, z]);
        to.add(<double>[hit.point[0], hit.point[1], hit.point[2]]);
        dists.add(hit.distance);
      }
      if (from.length < 3) break;
      // Reject the worst matches so a partial overlap does not drag the solve.
      dists.sort();
      final cutoff = dists[(dists.length * (1 - outlierFraction)).floor().clamp(0, dists.length - 1)];
      final keep = <int>[];
      for (var i = 0; i < dists.length; i++) {
        if (dists[i] <= cutoff) keep.add(i);
      }
      if (keep.length < 3) break;
      final delta = _rigidFromCorrespondences(
        <List<double>>[for (final i in keep) from[i]],
        <List<double>>[for (final i in keep) to[i]],
      );
      if (delta == null) break;
      transform = _multiply(delta, transform);
      var maxStep = 0.0;
      for (var i = 0; i < 16; i++) {
        final d = (delta[i] - (i % 5 == 0 ? 1.0 : 0.0)).abs();
        if (d > maxStep) maxStep = d;
      }
      if (maxStep < 1e-5) break;
    }
    return transform;
  }

  /// Applies the solved transform to the mesh.
  static TriMesh align(TriMesh source, TriMesh target, {int iterations = 30}) {
    final out = source.clone();
    out.transform(solve(source, target, iterations: iterations));
    return out;
  }

  /// Root-mean-square closest-point distance, for verification.
  static double rmsDistance(TriMesh source, TriMesh target) {
    final bvh = TriangleBVH.build(target);
    var sum = 0.0;
    var n = 0;
    final step = math.max(1, source.vertexCount ~/ 2000);
    for (var v = 0; v < source.vertexCount; v += step) {
      final hit = bvh.closestPoint(source.vx(v), source.vy(v), source.vz(v));
      if (hit == null) continue;
      sum += hit.distance * hit.distance;
      n++;
    }
    return n == 0 ? double.infinity : math.sqrt(sum / n);
  }

  // ---------------------------------------------------------------- internals

  static Float64List? _rigidFromCorrespondences(
      List<List<double>> from, List<List<double>> to) {
    final n = from.length;
    var cpx = 0.0, cpy = 0.0, cpz = 0.0;
    var cqx = 0.0, cqy = 0.0, cqz = 0.0;
    for (var i = 0; i < n; i++) {
      cpx += from[i][0];
      cpy += from[i][1];
      cpz += from[i][2];
      cqx += to[i][0];
      cqy += to[i][1];
      cqz += to[i][2];
    }
    cpx /= n;
    cpy /= n;
    cpz /= n;
    cqx /= n;
    cqy /= n;
    cqz /= n;

    var sxx = 0.0, sxy = 0.0, sxz = 0.0;
    var syx = 0.0, syy = 0.0, syz = 0.0;
    var szx = 0.0, szy = 0.0, szz = 0.0;
    for (var i = 0; i < n; i++) {
      final px = from[i][0] - cpx, py = from[i][1] - cpy, pz = from[i][2] - cpz;
      final qx = to[i][0] - cqx, qy = to[i][1] - cqy, qz = to[i][2] - cqz;
      sxx += px * qx;
      sxy += px * qy;
      sxz += px * qz;
      syx += py * qx;
      syy += py * qy;
      syz += py * qz;
      szx += pz * qx;
      szy += pz * qy;
      szz += pz * qz;
    }

    final n4 = <List<double>>[
      <double>[sxx + syy + szz, syz - szy, szx - sxz, sxy - syx],
      <double>[syz - szy, sxx - syy - szz, sxy + syx, szx + sxz],
      <double>[szx - sxz, sxy + syx, -sxx + syy - szz, syz + szy],
      <double>[sxy - syx, szx + sxz, syz + szy, -sxx - syy + szz],
    ];

    // Shift so the largest-magnitude eigenvalue dominates, then power iterate.
    var shift = 0.0;
    for (final row in n4) {
      for (final v in row) {
        shift += v.abs();
      }
    }
    var q = <double>[1, 0, 0, 0];
    for (var iter = 0; iter < 200; iter++) {
      final next = <double>[0, 0, 0, 0];
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          next[r] += (n4[r][c] + (r == c ? shift : 0)) * q[c];
        }
      }
      final l = math.sqrt(next[0] * next[0] +
          next[1] * next[1] +
          next[2] * next[2] +
          next[3] * next[3]);
      if (l < 1e-20) break;
      q = <double>[next[0] / l, next[1] / l, next[2] / l, next[3] / l];
    }
    final w = q[0], x = q[1], y = q[2], z = q[3];
    final rot = <double>[
      1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
      2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
      2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
    ];
    final tx = cqx - (rot[0] * cpx + rot[1] * cpy + rot[2] * cpz);
    final ty = cqy - (rot[3] * cpx + rot[4] * cpy + rot[5] * cpz);
    final tz = cqz - (rot[6] * cpx + rot[7] * cpy + rot[8] * cpz);
    return Float64List.fromList(<double>[
      rot[0], rot[3], rot[6], 0,
      rot[1], rot[4], rot[7], 0,
      rot[2], rot[5], rot[8], 0,
      tx, ty, tz, 1,
    ]);
  }

  static Float64List _identity() => Float64List.fromList(<double>[
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);

  static Float64List _multiply(Float64List a, Float64List b) {
    final out = Float64List(16);
    for (var c = 0; c < 4; c++) {
      for (var r = 0; r < 4; r++) {
        var s = 0.0;
        for (var k = 0; k < 4; k++) {
          s += a[k * 4 + r] * b[c * 4 + k];
        }
        out[c * 4 + r] = s;
      }
    }
    return out;
  }

  static void _apply(Float32List positions, Float64List m) {
    for (var i = 0; i < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      positions[i] = m[0] * x + m[4] * y + m[8] * z + m[12];
      positions[i + 1] = m[1] * x + m[5] * y + m[9] * z + m[13];
      positions[i + 2] = m[2] * x + m[6] * y + m[10] * z + m[14];
    }
  }
}
