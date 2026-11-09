import 'dart:math' as math;
import 'dart:typed_data';

import '../geom/bbox.dart';
import '../mesh/tri_mesh.dart';

/// Bounding volume hierarchy over mesh triangles.
///
/// Built with a median-of-centroids split on the widest axis, 8 triangles per
/// leaf. Supports ray casting (all hits, closest hit, shadow rays), closest
/// point queries, and box overlap traversal. This is the spatial core behind
/// voxelization, thickness probing, hole detection, projection and supports.
class TriangleBVH {
  // 6 doubles per node: minx,miny,minz,maxx,maxy,maxz
  final Float32List nodeBounds;
  // For internal nodes: child node ids; -1 for leaves.
  final Int32List nodeLeft;
  final Int32List nodeRight;
  // Leaf triangle ranges into triOrder.
  final Uint32List leafStart;
  final Uint32List leafCount;
  final Uint32List triOrder;
  final int nodeCount;

  final TriMesh mesh;

  TriangleBVH._(this.mesh, this.nodeBounds, this.nodeLeft, this.nodeRight,
      this.leafStart, this.leafCount, this.triOrder, this.nodeCount);

  static TriangleBVH build(TriMesh mesh, {int leafSize = 8}) {
    final n = mesh.faceCount;
    final centroids = Float32List(n * 3);
    final bounds = Float64List(n * 6);
    for (var f = 0; f < n; f++) {
      var minx = double.infinity,
          miny = double.infinity,
          minz = double.infinity;
      var maxx = double.negativeInfinity,
          maxy = double.negativeInfinity,
          maxz = double.negativeInfinity;
      var cx = 0.0, cy = 0.0, cz = 0.0;
      for (var k = 0; k < 3; k++) {
        final v = mesh.indices[f * 3 + k];
        final x = mesh.vx(v), y = mesh.vy(v), z = mesh.vz(v);
        cx += x / 3;
        cy += y / 3;
        cz += z / 3;
        if (x < minx) minx = x;
        if (y < miny) miny = y;
        if (z < minz) minz = z;
        if (x > maxx) maxx = x;
        if (y > maxy) maxy = y;
        if (z > maxz) maxz = z;
      }
      centroids[f * 3] = cx;
      centroids[f * 3 + 1] = cy;
      centroids[f * 3 + 2] = cz;
      bounds[f * 6] = minx;
      bounds[f * 6 + 1] = miny;
      bounds[f * 6 + 2] = minz;
      bounds[f * 6 + 3] = maxx;
      bounds[f * 6 + 4] = maxy;
      bounds[f * 6 + 5] = maxz;
    }

    final order = Uint32List(n);
    for (var i = 0; i < n; i++) {
      order[i] = i;
    }

    // Node arrays grow as needed; a full binary tree over n/leafSize leaves
    // needs fewer than 4*n/leafSize nodes in practice.
    final nb = <double>[];
    final childL = <int>[];
    final childR = <int>[];
    final lstart = <int>[];
    final lcount = <int>[];

    int buildNode(int start, int count) {
      final nodeId = childL.length;
      childL.add(-1);
      childR.add(-1);
      lstart.add(0);
      lcount.add(0);
      for (var k = 0; k < 6; k++) {
        nb.add(0);
      }
      var minx = double.infinity,
          miny = double.infinity,
          minz = double.infinity;
      var maxx = double.negativeInfinity,
          maxy = double.negativeInfinity,
          maxz = double.negativeInfinity;
      var cminx = double.infinity,
          cminy = double.infinity,
          cminz = double.infinity;
      var cmaxx = double.negativeInfinity,
          cmaxy = double.negativeInfinity,
          cmaxz = double.negativeInfinity;
      for (var i = start; i < start + count; i++) {
        final f = order[i];
        minx = math.min(minx, bounds[f * 6]);
        miny = math.min(miny, bounds[f * 6 + 1]);
        minz = math.min(minz, bounds[f * 6 + 2]);
        maxx = math.max(maxx, bounds[f * 6 + 3]);
        maxy = math.max(maxy, bounds[f * 6 + 4]);
        maxz = math.max(maxz, bounds[f * 6 + 5]);
        cminx = math.min(cminx, centroids[f * 3]);
        cminy = math.min(cminy, centroids[f * 3 + 1]);
        cminz = math.min(cminz, centroids[f * 3 + 2]);
        cmaxx = math.max(cmaxx, centroids[f * 3]);
        cmaxy = math.max(cmaxy, centroids[f * 3 + 1]);
        cmaxz = math.max(cmaxz, centroids[f * 3 + 2]);
      }
      final o = nodeId * 6;
      nb[o] = minx;
      nb[o + 1] = miny;
      nb[o + 2] = minz;
      nb[o + 3] = maxx;
      nb[o + 4] = maxy;
      nb[o + 5] = maxz;

      if (count <= leafSize) {
        lstart[nodeId] = start;
        lcount[nodeId] = count;
        return nodeId;
      }

      final ex = cmaxx - cminx, ey = cmaxy - cminy, ez = cmaxz - cminz;
      int axis;
      if (ex >= ey && ex >= ez) {
        axis = 0;
      } else if (ey >= ez) {
        axis = 1;
      } else {
        axis = 2;
      }
      // Median split on the chosen centroid axis.
      final sub = order.sublist(start, start + count);
      sub.sort(
          (a, b) => centroids[a * 3 + axis].compareTo(centroids[b * 3 + axis]));
      for (var i = 0; i < count; i++) {
        order[start + i] = sub[i];
      }
      final mid = count ~/ 2;
      final left = buildNode(start, mid);
      final right = buildNode(start + mid, count - mid);
      childL[nodeId] = left;
      childR[nodeId] = right;
      return nodeId;
    }

    if (n == 0) {
      return TriangleBVH._(mesh, Float32List(0), Int32List(0), Int32List(0),
          Uint32List(0), Uint32List(0), Uint32List(0), 0);
    }
    buildNode(0, n);
    return TriangleBVH._(
      mesh,
      Float32List.fromList(nb),
      Int32List.fromList(childL),
      Int32List.fromList(childR),
      Uint32List.fromList(lstart),
      Uint32List.fromList(lcount),
      order,
      childL.length,
    );
  }

  /// Slab test. Returns entry distance (may be negative when inside).
  double _boxHit(int node, double ox, double oy, double oz, double dx,
      double dy, double dz, double tMax) {
    final o = node * 6;
    var t0 = 0.0, t1 = tMax;
    // X
    if (dx == 0) {
      if (ox < nodeBounds[o] || ox > nodeBounds[o + 3]) return double.infinity;
    } else {
      var a = (nodeBounds[o] - ox) / dx;
      var b = (nodeBounds[o + 3] - ox) / dx;
      if (a > b) {
        final t = a;
        a = b;
        b = t;
      }
      if (a > t0) t0 = a;
      if (b < t1) t1 = b;
      if (t0 > t1) return double.infinity;
    }
    // Y
    if (dy == 0) {
      if (oy < nodeBounds[o + 1] || oy > nodeBounds[o + 4]) {
        return double.infinity;
      }
    } else {
      var a = (nodeBounds[o + 1] - oy) / dy;
      var b = (nodeBounds[o + 4] - oy) / dy;
      if (a > b) {
        final t = a;
        a = b;
        b = t;
      }
      if (a > t0) t0 = a;
      if (b < t1) t1 = b;
      if (t0 > t1) return double.infinity;
    }
    // Z
    if (dz == 0) {
      if (oz < nodeBounds[o + 2] || oz > nodeBounds[o + 5]) {
        return double.infinity;
      }
    } else {
      var a = (nodeBounds[o + 2] - oz) / dz;
      var b = (nodeBounds[o + 5] - oz) / dz;
      if (a > b) {
        final t = a;
        a = b;
        b = t;
      }
      if (a > t0) t0 = a;
      if (b < t1) t1 = b;
      if (t0 > t1) return double.infinity;
    }
    return t0;
  }

  /// Möller-Trumbore. Returns hit distance or -1.
  double _triHit(int f, double ox, double oy, double oz, double dx, double dy,
      double dz, double tMax) {
    final i0 = mesh.indices[f * 3] * 3;
    final i1 = mesh.indices[f * 3 + 1] * 3;
    final i2 = mesh.indices[f * 3 + 2] * 3;
    final ax = mesh.positions[i0],
        ay = mesh.positions[i0 + 1],
        az = mesh.positions[i0 + 2];
    final bx = mesh.positions[i1],
        by = mesh.positions[i1 + 1],
        bz = mesh.positions[i1 + 2];
    final cx = mesh.positions[i2],
        cy = mesh.positions[i2 + 1],
        cz = mesh.positions[i2 + 2];
    final e1x = bx - ax, e1y = by - ay, e1z = bz - az;
    final e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
    final px = dy * e2z - dz * e2y;
    final py = dz * e2x - dx * e2z;
    final pz = dx * e2y - dy * e2x;
    final det = e1x * px + e1y * py + e1z * pz;
    final e1Sq = e1x * e1x + e1y * e1y + e1z * e1z;
    final e2Sq = e2x * e2x + e2y * e2y + e2z * e2z;
    final dirSq = dx * dx + dy * dy + dz * dz;
    // Relative angular tolerance: a world-unit determinant threshold misses
    // every triangle in small models and depends on direction magnitude.
    if (det * det <= 1e-24 * e1Sq * e2Sq * dirSq) return -1;
    final inv = 1.0 / det;
    final tx = ox - ax, ty = oy - ay, tz = oz - az;
    final u = (tx * px + ty * py + tz * pz) * inv;
    if (u < -1e-6 || u > 1 + 1e-6) return -1;
    final qx = ty * e1z - tz * e1y;
    final qy = tz * e1x - tx * e1z;
    final qz = tx * e1y - ty * e1x;
    final v = (dx * qx + dy * qy + dz * qz) * inv;
    if (v < -1e-6 || u + v > 1 + 1e-6) return -1;
    final t = (e2x * qx + e2y * qy + e2z * qz) * inv;
    if (t <= 0 || t * t * dirSq <= 1e-14 * math.max(e1Sq, e2Sq) || t > tMax) {
      return -1;
    }
    return t;
  }

  /// Closest hit along the ray. Returns null when nothing is hit.
  RayHit? raycast(List<double> origin, List<double> dir,
      {double tMax = double.infinity}) {
    if (nodeCount == 0) return null;
    final ox = origin[0], oy = origin[1], oz = origin[2];
    final dx = dir[0], dy = dir[1], dz = dir[2];
    var bestT = tMax;
    var bestF = -1;
    final stack = <int>[0];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (_boxHit(node, ox, oy, oz, dx, dy, dz, bestT) == double.infinity) {
        continue;
      }
      final l = nodeLeft[node];
      if (l < 0) {
        final s = leafStart[node], n = leafCount[node];
        for (var i = s; i < s + n; i++) {
          final f = triOrder[i];
          final t = _triHit(f, ox, oy, oz, dx, dy, dz, bestT);
          if (t > 0 && t < bestT) {
            bestT = t;
            bestF = f;
          }
        }
      } else {
        stack.add(l);
        stack.add(nodeRight[node]);
      }
    }
    if (bestF < 0) return null;
    return RayHit(bestT, bestF,
        <double>[ox + dx * bestT, oy + dy * bestT, oz + dz * bestT]);
  }

  /// All intersections along the ray, sorted by distance.
  List<double> raycastAll(List<double> origin, List<double> dir,
      {double tMax = double.infinity}) {
    final hits = <double>[];
    if (nodeCount == 0) return hits;
    final ox = origin[0], oy = origin[1], oz = origin[2];
    final dx = dir[0], dy = dir[1], dz = dir[2];
    final stack = <int>[0];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (_boxHit(node, ox, oy, oz, dx, dy, dz, tMax) == double.infinity) {
        continue;
      }
      final l = nodeLeft[node];
      if (l < 0) {
        final s = leafStart[node], n = leafCount[node];
        for (var i = s; i < s + n; i++) {
          final t = _triHit(triOrder[i], ox, oy, oz, dx, dy, dz, tMax);
          if (t > 0) hits.add(t);
        }
      } else {
        stack.add(l);
        stack.add(nodeRight[node]);
      }
    }
    hits.sort();
    return hits;
  }

  /// True when any triangle lies within tMax along the ray (shadow query).
  bool occluded(List<double> origin, List<double> dir,
      {double tMax = double.infinity}) {
    return raycast(origin, dir, tMax: tMax) != null;
  }

  /// Closest surface point to p. Returns null only for an empty mesh.
  ClosestPoint? closestPoint(double px, double py, double pz,
      {double maxDist = double.infinity}) {
    if (nodeCount == 0) return null;
    var best = maxDist * maxDist;
    var bestF = -1;
    final bary = Float64List(3);
    final bestBary = Float64List(3);
    final stack = <int>[0];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final o = node * 6;
      // Sphere-box distance test.
      final cx = px.clamp(nodeBounds[o], nodeBounds[o + 3]);
      final cy = py.clamp(nodeBounds[o + 1], nodeBounds[o + 4]);
      final cz = pz.clamp(nodeBounds[o + 2], nodeBounds[o + 5]);
      final dx = px - cx, dy = py - cy, dz = pz - cz;
      if (dx * dx + dy * dy + dz * dz > best) continue;
      final l = nodeLeft[node];
      if (l < 0) {
        final s = leafStart[node], n = leafCount[node];
        for (var i = s; i < s + n; i++) {
          final f = triOrder[i];
          final i0 = mesh.indices[f * 3] * 3;
          final i1 = mesh.indices[f * 3 + 1] * 3;
          final i2 = mesh.indices[f * 3 + 2] * 3;
          final d2 = closestPointTriangleSq(
            px,
            py,
            pz,
            mesh.positions[i0],
            mesh.positions[i0 + 1],
            mesh.positions[i0 + 2],
            mesh.positions[i1],
            mesh.positions[i1 + 1],
            mesh.positions[i1 + 2],
            mesh.positions[i2],
            mesh.positions[i2 + 1],
            mesh.positions[i2 + 2],
            bary,
          );
          if (d2 < best) {
            best = d2;
            bestF = f;
            bestBary[0] = bary[0];
            bestBary[1] = bary[1];
            bestBary[2] = bary[2];
          }
        }
      } else {
        stack.add(l);
        stack.add(nodeRight[node]);
      }
    }
    if (bestF < 0) return null;
    final i0 = mesh.indices[bestF * 3] * 3;
    final i1 = mesh.indices[bestF * 3 + 1] * 3;
    final i2 = mesh.indices[bestF * 3 + 2] * 3;
    final x = bestBary[0] * mesh.positions[i0] +
        bestBary[1] * mesh.positions[i1] +
        bestBary[2] * mesh.positions[i2];
    final y = bestBary[0] * mesh.positions[i0 + 1] +
        bestBary[1] * mesh.positions[i1 + 1] +
        bestBary[2] * mesh.positions[i2 + 1];
    final z = bestBary[0] * mesh.positions[i0 + 2] +
        bestBary[1] * mesh.positions[i1 + 2] +
        bestBary[2] * mesh.positions[i2 + 2];
    return ClosestPoint(math.sqrt(best), bestF, <double>[x, y, z]);
  }

  /// Collects triangle ids whose boxes overlap [box].
  List<int> overlap(BBox box, {bool exact = false}) {
    final out = <int>[];
    if (nodeCount == 0) return out;
    final stack = <int>[0];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      final o = node * 6;
      if (nodeBounds[o] > box.maxX ||
          nodeBounds[o + 3] < box.minX ||
          nodeBounds[o + 1] > box.maxY ||
          nodeBounds[o + 4] < box.minY ||
          nodeBounds[o + 2] > box.maxZ ||
          nodeBounds[o + 5] < box.minZ) {
        continue;
      }
      final l = nodeLeft[node];
      if (l < 0) {
        final s = leafStart[node], n = leafCount[node];
        for (var i = s; i < s + n; i++) {
          final f = triOrder[i];
          if (!exact) {
            out.add(f);
            continue;
          }
          var tminx = double.infinity,
              tminy = double.infinity,
              tminz = double.infinity;
          var tmaxx = double.negativeInfinity,
              tmaxy = double.negativeInfinity,
              tmaxz = double.negativeInfinity;
          for (var k = 0; k < 3; k++) {
            final v = mesh.indices[f * 3 + k];
            final x = mesh.vx(v), y = mesh.vy(v), z = mesh.vz(v);
            tminx = math.min(tminx, x);
            tminy = math.min(tminy, y);
            tminz = math.min(tminz, z);
            tmaxx = math.max(tmaxx, x);
            tmaxy = math.max(tmaxy, y);
            tmaxz = math.max(tmaxz, z);
          }
          if (tmaxx >= box.minX &&
              tminx <= box.maxX &&
              tmaxy >= box.minY &&
              tminy <= box.maxY &&
              tmaxz >= box.minZ &&
              tminz <= box.maxZ) {
            out.add(f);
          }
        }
      } else {
        stack.add(l);
        stack.add(nodeRight[node]);
      }
    }
    return out;
  }
}

class RayHit {
  final double t;
  final int face;
  final List<double> point;
  RayHit(this.t, this.face, this.point);
}

class ClosestPoint {
  final double distance;
  final int face;
  final List<double> point;
  ClosestPoint(this.distance, this.face, this.point);
}
