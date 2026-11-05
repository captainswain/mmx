import 'dart:math' as math;

import '../mesh/topology.dart';
import '../mesh/tri_mesh.dart';

/// Bridges pairs of open boundary loops, the job Meshmixer's
/// BoundaryBridge/BoundaryJoiner tools do. The strip is built by walking both
/// loops from their closest pair and advancing whichever side keeps the
/// triangles well shaped, so both loops are consumed completely.
class Bridge {
  /// Connects two ordered boundary loops. Returns the input unchanged when a
  /// loop has fewer than three vertices.
  static TriMesh bridgeLoops(TriMesh mesh, List<int> loopA, List<int> loopB) {
    if (loopA.length < 3 || loopB.length < 3) return mesh.clone();

    // Start from the closest vertex pair, keeping the loops' own order.
    var bestA = 0, bestB = 0;
    var bestD = double.infinity;
    for (var i = 0; i < loopA.length; i++) {
      for (var j = 0; j < loopB.length; j++) {
        final dx = mesh.vx(loopA[i]) - mesh.vx(loopB[j]);
        final dy = mesh.vy(loopA[i]) - mesh.vy(loopB[j]);
        final dz = mesh.vz(loopA[i]) - mesh.vz(loopB[j]);
        final d = dx * dx + dy * dy + dz * dz;
        if (d < bestD) {
          bestD = d;
          bestA = i;
          bestB = j;
        }
      }
    }

    final a = <int>[
      for (var k = 0; k < loopA.length; k++) loopA[(bestA + k) % loopA.length]
    ];
    final b = <int>[
      for (var k = 0; k < loopB.length; k++) loopB[(bestB + k) % loopB.length]
    ];
    // Reverse B so the two loops run in opposite directions.
    final br = b.reversed.toList();

    TriMesh build(bool flip) {
      final builder = MeshBuilder();
      for (var v = 0; v < mesh.vertexCount; v++) {
        builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v));
      }
      for (var f = 0; f < mesh.faceCount; f++) {
        builder.addTriangle(mesh.indices[f * 3], mesh.indices[f * 3 + 1],
            mesh.indices[f * 3 + 2]);
      }
      var i = 0, j = 0;
      while (i < a.length || j < br.length) {
        final aNext = a[(i + 1) % a.length];
        final bNext = br[(j + 1) % br.length];
        final da = _dist(mesh, a[i % a.length], aNext);
        final db = _dist(mesh, br[j % br.length], bNext);
        if (j >= br.length || (i < a.length && da <= db)) {
          final t0 = a[i % a.length], t1 = br[j % br.length];
          if (flip) {
            builder.addTriangle(t0, aNext, t1);
          } else {
            builder.addTriangle(t0, t1, aNext);
          }
          i++;
        } else {
          final t0 = a[i % a.length], t1 = br[j % br.length];
          if (flip) {
            builder.addTriangle(t0, bNext, t1);
          } else {
            builder.addTriangle(t0, t1, bNext);
          }
          j++;
        }
        if (i >= a.length && j >= br.length) break;
      }
      return builder.build();
    }

    var out = build(false);
    if (MeshTopology(out).boundaryEdges().isNotEmpty) {
      final flipped = build(true);
      if (MeshTopology(flipped).boundaryEdges().length <
          MeshTopology(out).boundaryEdges().length) {
        out = flipped;
      }
    }
    out.removeDegenerateFaces();
    out.compact();
    return out;
  }

  /// Pairs boundary loops by centroid proximity and bridges them, largest gap
  /// first limited by [maxGap]. Use this to stitch a slit or join two halves.
  static TriMesh stitchNearest(TriMesh mesh,
      {double? maxGap, int maxPairs = 8}) {
    var work = mesh.clone();
    final gap = maxGap ?? work.bounds().diagonal * 0.2;
    var pairs = 0;
    while (pairs < maxPairs) {
      final loops = MeshTopology(work).boundaryLoops();
      if (loops.length < 2) break;
      var bi = -1, bj = -1;
      var bestD = double.infinity;
      for (var i = 0; i < loops.length; i++) {
        for (var j = i + 1; j < loops.length; j++) {
          final d = _centroidDistance(work, loops[i], loops[j]);
          if (d < bestD) {
            bestD = d;
            bi = i;
            bj = j;
          }
        }
      }
      if (bi < 0 || bestD > gap) break;
      final next = bridgeLoops(work, loops[bi], loops[bj]);
      if (MeshTopology(next).boundaryLoops().length >= loops.length) break;
      work = next;
      pairs++;
    }
    return work;
  }

  static double _centroidDistance(TriMesh mesh, List<int> a, List<int> b) {
    var ax = 0.0, ay = 0.0, az = 0.0;
    for (final v in a) {
      ax += mesh.vx(v);
      ay += mesh.vy(v);
      az += mesh.vz(v);
    }
    ax /= a.length;
    ay /= a.length;
    az /= a.length;
    var bx = 0.0, by = 0.0, bz = 0.0;
    for (final v in b) {
      bx += mesh.vx(v);
      by += mesh.vy(v);
      bz += mesh.vz(v);
    }
    bx /= b.length;
    by /= b.length;
    bz /= b.length;
    return math.sqrt(
        math.pow(ax - bx, 2) + math.pow(ay - by, 2) + math.pow(az - bz, 2));
  }

  static double _dist(TriMesh mesh, int a, int b) {
    final dx = mesh.vx(a) - mesh.vx(b);
    final dy = mesh.vy(a) - mesh.vy(b);
    final dz = mesh.vz(a) - mesh.vz(b);
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}
