import 'dart:math' as math;
import 'dart:typed_data';

import '../analysis/analysis.dart';
import '../mesh/tri_mesh.dart';
import '../spatial/bvh.dart';

/// Support-structure parameters, mirroring the shipped preset XML fields
/// (OverhangAngle, ContactTolerance, VerticalOffset, LayerHeight,
/// SupportMaxAngle, SupportDensity, PostDiameter, TipDiameter, BaseDiameter,
/// AllowTopConnections, OptimizationRounds, PostSides...).
class SupportSettings {
  final double overhangAngleDegrees;
  final double contactTolerance;
  final double verticalOffset;
  final double layerHeight;
  final double maxStrutAngleDegrees;
  final double density;
  final double postDiameter;
  final double tipDiameter;
  final double baseDiameter;
  final double baseHeight;
  final double tipHeight;
  final int postSides;
  final bool allowTopConnections;

  const SupportSettings({
    this.overhangAngleDegrees = 45,
    this.contactTolerance = 0.2,
    this.verticalOffset = 0.0,
    this.layerHeight = 0.2,
    this.maxStrutAngleDegrees = 45,
    this.density = 0.5,
    this.postDiameter = 2.0,
    this.tipDiameter = 0.6,
    this.baseDiameter = 6.0,
    this.baseHeight = 1.0,
    this.tipHeight = 0.8,
    this.postSides = 12,
    this.allowTopConnections = false,
  });
}

class SupportResult {
  final TriMesh supports;
  final int postCount;
  final int strutCount;
  final double contactArea;
  SupportResult(
      this.supports, this.postCount, this.strutCount, this.contactArea);
}

/// Generates a printable support forest for overhanging geometry.
///
/// The shipped binary uses SupportForestGenerator.cpp plus SupportPostGraph.cpp
/// with an optimization pass over candidate posts. This implementation samples
/// overhang regions on a density grid, drops tapered posts to the bed, and
/// connects neighbouring posts with struts that respect the max strut angle.
class SupportGenerator {
  static SupportResult generate(
    TriMesh mesh, {
    SupportSettings settings = const SupportSettings(),
    double bedY = 0,
  }) {
    final overhang =
        OverhangAnalysis.run(mesh, angleDegrees: settings.overhangAngleDegrees);
    if (overhang.overhangFaces.isEmpty) {
      return SupportResult(TriMesh.empty(), 0, 0, 0);
    }
    final bvh = TriangleBVH.build(mesh);
    final b = mesh.bounds();
    // Sample spacing derived from density (density 1 = dense posts).
    final spacing = math.max(settings.postDiameter * 2.0,
        (1.0 - settings.density) * b.diagonal * 0.08 + settings.postDiameter);
    final cell = <int, List<double>>{};
    var contactArea = 0.0;

    for (final f in overhang.overhangFaces) {
      final a = mesh.indices[f * 3],
          bb = mesh.indices[f * 3 + 1],
          c = mesh.indices[f * 3 + 2];
      final ax = mesh.vx(a), ay = mesh.vy(a), az = mesh.vz(a);
      final bx = mesh.vx(bb), by = mesh.vy(bb), bz = mesh.vz(bb);
      final cx = mesh.vx(c), cy = mesh.vy(c), cz = mesh.vz(c);
      // Sample points on a grid over the triangle.
      final edgeMax = math.max(
          _dist3(ax, ay, az, bx, by, bz),
          math.max(
              _dist3(bx, by, bz, cx, cy, cz), _dist3(cx, cy, cz, ax, ay, az)));
      final n = math.max(1, (edgeMax / spacing).ceil());
      for (var i = 0; i <= n; i++) {
        for (var j = 0; j <= n - i; j++) {
          final u = i / n, v = j / n, w = 1 - u - v;
          if (w < 0) continue;
          final px = ax * w + bx * u + cx * v;
          final py = ay * w + by * u + cy * v;
          final pz = az * w + bz * u + cz * v;
          final key = ((px / spacing).round() << 20) ^
              ((pz / spacing).round() & 0xFFFFF);
          cell.putIfAbsent(key, () => <double>[px, py, pz]);
        }
      }
      contactArea += 0.5 * _triArea(ax, ay, az, bx, by, bz, cx, cy, cz);
    }

    final posts = <List<double>>[];
    for (final p in cell.values) {
      // Cast down to find the first surface below (or the bed).
      final hit = bvh.raycast(<double>[
        p[0],
        p[1] - settings.contactTolerance,
        p[2]
      ], <double>[
        0,
        -1,
        0
      ], tMax: p[1] - bedY + 1e-6);
      final endY = hit != null ? hit.point[1] : bedY;
      if (endY >= p[1] - settings.contactTolerance) continue;
      posts.add(<double>[p[0], p[1] - settings.verticalOffset, p[2], endY]);
    }

    final b2 = MeshBuilder();
    var struts = 0;
    // Posts.
    for (final p in posts) {
      final top = <double>[p[0], p[1], p[2]];
      final bottom = <double>[p[0], p[3], p[2]];
      final tipBase = <double>[p[0], p[1] - settings.tipHeight, p[2]];
      final post = cylinderMesh(
          top, tipBase, settings.tipDiameter / 2, settings.postDiameter / 2,
          sides: settings.postSides);
      _append(b2, post);
      final shaft = cylinderMesh(
          tipBase, bottom, settings.postDiameter / 2, settings.postDiameter / 2,
          sides: settings.postSides);
      _append(b2, shaft);
      if (bottom[1] <= bedY + 1e-6) {
        final base = cylinderMesh(
          <double>[bottom[0], bedY, bottom[2]],
          <double>[bottom[0], bedY + settings.baseHeight, bottom[2]],
          settings.baseDiameter / 2,
          settings.baseDiameter / 2,
          sides: settings.postSides,
        );
        _append(b2, base);
      }
    }
    // Struts between nearby posts that satisfy the angle limit.
    final maxStrutRun = settings.postDiameter * 14;
    for (var i = 0; i < posts.length; i++) {
      for (var j = i + 1; j < posts.length; j++) {
        final dx = posts[i][0] - posts[j][0];
        final dz = posts[i][2] - posts[j][2];
        final dy = posts[i][3] - posts[j][3];
        final horiz = math.sqrt(dx * dx + dz * dz);
        if (horiz < 1e-6 || horiz > maxStrutRun) continue;
        final angle = math.atan2(dy.abs(), horiz) * 180 / math.pi;
        if (angle > settings.maxStrutAngleDegrees) continue;
        // Only connect the nearest few neighbours to keep the forest sparse.
        if (horiz > maxStrutRun * 0.5 && (i + j) % 3 != 0) continue;
        final from = <double>[
          posts[i][0],
          posts[i][1] - settings.tipHeight,
          posts[i][2]
        ];
        final to = <double>[
          posts[j][0],
          posts[j][1] - settings.tipHeight,
          posts[j][2]
        ];
        final strut = cylinderMesh(from, to, settings.postDiameter * 0.35,
            settings.postDiameter * 0.35,
            sides: math.max(6, settings.postSides ~/ 2));
        _append(b2, strut);
        struts++;
      }
    }

    final supports = b2.build();
    return SupportResult(supports, posts.length, struts, contactArea);
  }

  static void _append(MeshBuilder target, TriMesh m) {
    final base = target.vertexCount;
    for (var i = 0; i < m.vertexCount; i++) {
      target.addVertex(m.vx(i), m.vy(i), m.vz(i));
    }
    for (var f = 0; f < m.faceCount; f++) {
      target.addTriangle(base + m.indices[f * 3], base + m.indices[f * 3 + 1],
          base + m.indices[f * 3 + 2]);
    }
  }

  static double _dist3(
      double ax, double ay, double az, double bx, double by, double bz) {
    final dx = ax - bx, dy = ay - by, dz = az - bz;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _triArea(double ax, double ay, double az, double bx, double by,
      double bz, double cx, double cy, double cz) {
    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final wx = cx - ax, wy = cy - ay, wz = cz - az;
    final nx = uy * wz - uz * wy,
        ny = uz * wx - ux * wz,
        nz = ux * wy - uy * wx;
    return math.sqrt(nx * nx + ny * ny + nz * nz);
  }
}

/// Orientation optimization: searches candidate rotations and scores them by
/// support volume, bed contact and stability, matching the "Optimize
/// Orientation" analysis tool.
class OrientationOptimizer {
  final List<double> bestRotation;
  final double score;
  final double supportVolume;
  final double contactArea;
  final bool stable;

  OrientationOptimizer(this.bestRotation, this.score, this.supportVolume,
      this.contactArea, this.stable);

  static OrientationOptimizer optimize(TriMesh mesh, {int candidates = 24}) {
    var best = <double>[0, 0, 0];
    var bestScore = double.negativeInfinity;
    var bestSupport = double.infinity;
    var bestContact = 0.0;
    var bestStable = false;
    final diag = mesh.bounds().diagonal;

    for (var i = 0; i < candidates; i++) {
      // Distribute candidate rotations over the sphere (spiral sampling).
      final y = 1 - (i / (candidates - 1)) * 2;
      final r = math.sqrt(math.max(0.0, 1 - y * y));
      final theta = math.pi * (1 + math.sqrt(5)) * i;
      final ax = math.cos(theta) * r;
      final az = math.sin(theta) * r;
      final angle = math.acos(y.clamp(-1.0, 1.0));
      final rotated = mesh.clone();
      rotated.transform(_axisAngle(ax, y, az, angle));

      final overhang = OverhangAnalysis.run(rotated, angleDegrees: 45);
      final stability = StabilityAnalysis.run(rotated);
      // Estimate support material as overhang area times an average height.
      final supportEstimate = overhang.overhangArea * diag * 0.15;
      final score = -supportEstimate -
          (stability.centerInsideSupport ? 0 : diag) +
          stability.minTipAngleDegrees * diag * 0.01 +
          stability.bedContactArea * 0.5;
      if (score > bestScore) {
        bestScore = score;
        best = <double>[ax, y, az, angle];
        bestSupport = supportEstimate;
        bestContact = stability.bedContactArea;
        bestStable = stability.centerInsideSupport;
      }
    }
    return OrientationOptimizer(
        best, bestScore, bestSupport, bestContact, bestStable);
  }

  static Float64List _axisAngle(double ax, double ay, double az, double angle) {
    final l = math.sqrt(ax * ax + ay * ay + az * az);
    if (l < 1e-12) {
      return Float64List.fromList(
          <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    }
    final x = ax / l, y = ay / l, z = az / l;
    final c = math.cos(angle), s = math.sin(angle), t = 1 - c;
    return Float64List.fromList(<double>[
      t * x * x + c,
      t * x * y - s * z,
      t * x * z + s * y,
      0,
      t * x * y + s * z,
      t * y * y + c,
      t * y * z - s * x,
      0,
      t * x * z - s * y,
      t * y * z + s * x,
      t * z * z + c,
      0,
      0,
      0,
      0,
      1,
    ]);
  }
}
