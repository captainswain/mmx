import 'dart:math' as math;
import 'dart:typed_data';

import '../geom/bbox.dart';

/// Indexed triangle mesh: the single geometry container used by every
/// operator in this kernel. Positions and indices are flat typed arrays so
/// hot loops stay allocation free, and so the same buffers can be handed to
/// a GPU or a worker isolate without per-element boxing.
class TriMesh {
  Float32List positions;
  Uint32List indices;

  /// Per-face group id (face groups / material regions). Optional.
  Uint16List? faceGroups;

  /// Per-vertex RGB, 3 floats per vertex. Optional.
  Float32List? vertexColors;

  TriMesh(this.positions, this.indices, {this.faceGroups, this.vertexColors});

  factory TriMesh.empty() => TriMesh(Float32List(0), Uint32List(0));

  int get vertexCount => positions.length ~/ 3;
  int get faceCount => indices.length ~/ 3;

  double vx(int i) => positions[i * 3];
  double vy(int i) => positions[i * 3 + 1];
  double vz(int i) => positions[i * 3 + 2];

  TriMesh clone() => TriMesh(
        Float32List.fromList(positions),
        Uint32List.fromList(indices),
        faceGroups:
            faceGroups == null ? null : Uint16List.fromList(faceGroups!),
        vertexColors:
            vertexColors == null ? null : Float32List.fromList(vertexColors!),
      );

  BBox bounds() {
    final b = BBox();
    for (var i = 0; i < positions.length; i += 3) {
      b.add(positions[i], positions[i + 1], positions[i + 2]);
    }
    return b;
  }

  /// Signed volume via the divergence theorem (positive for outward normals).
  double signedVolume() {
    var vol = 0.0;
    for (var f = 0; f < indices.length; f += 3) {
      final a = indices[f] * 3, b = indices[f + 1] * 3, c = indices[f + 2] * 3;
      final ax = positions[a], ay = positions[a + 1], az = positions[a + 2];
      final bx = positions[b], by = positions[b + 1], bz = positions[b + 2];
      final cx = positions[c], cy = positions[c + 1], cz = positions[c + 2];
      vol += _det(ax, ay, az, bx, by, bz, cx, cy, cz);
    }
    return vol / 6.0;
  }

  double surfaceArea() {
    var area = 0.0;
    for (var f = 0; f < indices.length; f += 3) {
      final a = indices[f] * 3, b = indices[f + 1] * 3, c = indices[f + 2] * 3;
      final ux = positions[b] - positions[a];
      final uy = positions[b + 1] - positions[a + 1];
      final uz = positions[b + 2] - positions[a + 2];
      final wx = positions[c] - positions[a];
      final wy = positions[c + 1] - positions[a + 1];
      final wz = positions[c + 2] - positions[a + 2];
      final nx = uy * wz - uz * wy;
      final ny = uz * wx - ux * wz;
      final nz = ux * wy - uy * wx;
      area += 0.5 * math.sqrt(nx * nx + ny * ny + nz * nz);
    }
    return area;
  }

  /// Vertex-area weighted centroid.
  List<double> centroid() {
    var sx = 0.0, sy = 0.0, sz = 0.0, sw = 0.0;
    for (var f = 0; f < indices.length; f += 3) {
      final ia = indices[f], ib = indices[f + 1], ic = indices[f + 2];
      final ax = vx(ia), ay = vy(ia), az = vz(ia);
      final ux = vx(ib) - ax, uy = vy(ib) - ay, uz = vz(ib) - az;
      final wx = vx(ic) - ax, wy = vy(ic) - ay, wz = vz(ic) - az;
      final nx = uy * wz - uz * wy,
          ny = uz * wx - ux * wz,
          nz = ux * wy - uy * wx;
      final a = 0.5 * math.sqrt(nx * nx + ny * ny + nz * nz);
      sx += a * (ax + vx(ib) + vx(ic)) / 3.0;
      sy += a * (ay + vy(ib) + vy(ic)) / 3.0;
      sz += a * (az + vz(ib) + vz(ic)) / 3.0;
      sw += a;
    }
    if (sw == 0) return <double>[0, 0, 0];
    return <double>[sx / sw, sy / sw, sz / sw];
  }

  /// Applies a column-major 4x4 affine transform in place.
  void transform(Float64List m) {
    for (var i = 0; i < positions.length; i += 3) {
      final x = positions[i], y = positions[i + 1], z = positions[i + 2];
      positions[i] = m[0] * x + m[4] * y + m[8] * z + m[12];
      positions[i + 1] = m[1] * x + m[5] * y + m[9] * z + m[13];
      positions[i + 2] = m[2] * x + m[6] * y + m[10] * z + m[14];
    }
  }

  /// Drops faces with repeated indices or (near) zero area.
  int removeDegenerateFaces({double minArea = 1e-14}) {
    final keep = <int>[];
    for (var f = 0; f < indices.length; f += 3) {
      final ia = indices[f], ib = indices[f + 1], ic = indices[f + 2];
      if (ia == ib || ib == ic || ia == ic) continue;
      final ax = vx(ia), ay = vy(ia), az = vz(ia);
      final ux = vx(ib) - ax, uy = vy(ib) - ay, uz = vz(ib) - az;
      final wx = vx(ic) - ax, wy = vy(ic) - ay, wz = vz(ic) - az;
      final nx = uy * wz - uz * wy,
          ny = uz * wx - ux * wz,
          nz = ux * wy - uy * wx;
      if (0.5 * math.sqrt(nx * nx + ny * ny + nz * nz) <= minArea) continue;
      keep.add(ia);
      keep.add(ib);
      keep.add(ic);
    }
    final removed = (indices.length - keep.length) ~/ 3;
    if (removed > 0) {
      indices = Uint32List.fromList(keep);
      if (faceGroups != null && faceGroups!.length != keep.length ~/ 3) {
        faceGroups = null;
      }
    }
    return removed;
  }

  /// Removes vertices not referenced by any face and remaps indices.
  void compact() {
    final used = Uint8List(vertexCount);
    for (final i in indices) {
      used[i] = 1;
    }
    final remap = Uint32List(vertexCount);
    var n = 0;
    for (var i = 0; i < vertexCount; i++) {
      if (used[i] == 1) {
        remap[i] = n++;
      }
    }
    if (n == vertexCount) return;
    final np = Float32List(n * 3);
    Float32List? nc;
    if (vertexColors != null) nc = Float32List(n * 3);
    for (var i = 0; i < vertexCount; i++) {
      if (used[i] != 1) continue;
      final d = remap[i] * 3;
      np[d] = positions[i * 3];
      np[d + 1] = positions[i * 3 + 1];
      np[d + 2] = positions[i * 3 + 2];
      if (nc != null) {
        nc[d] = vertexColors![i * 3];
        nc[d + 1] = vertexColors![i * 3 + 1];
        nc[d + 2] = vertexColors![i * 3 + 2];
      }
    }
    final ni = Uint32List(indices.length);
    for (var i = 0; i < indices.length; i++) {
      ni[i] = remap[indices[i]];
    }
    positions = np;
    indices = ni;
    vertexColors = nc;
  }

  /// Returns human-readable problems; empty list means structurally sane.
  List<String> validate() {
    final issues = <String>[];
    if (positions.length % 3 != 0) issues.add('positions not a multiple of 3');
    if (indices.length % 3 != 0) issues.add('indices not a multiple of 3');
    final n = vertexCount;
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= n) {
        issues.add('index ${indices[i]} out of range (verts=$n)');
        break;
      }
    }
    for (var i = 0; i < positions.length; i++) {
      if (!positions[i].isFinite) {
        issues.add('non-finite position at $i');
        break;
      }
    }
    return issues;
  }

  static double _det(double ax, double ay, double az, double bx, double by,
      double bz, double cx, double cy, double cz) {
    return ax * (by * cz - bz * cy) -
        ay * (bx * cz - bz * cx) +
        az * (bx * cy - by * cx);
  }
}

/// Incremental builder for operator output.
class MeshBuilder {
  final List<double> _p = <double>[];
  final List<int> _i = <int>[];

  int addVertex(double x, double y, double z) {
    final id = _p.length ~/ 3;
    _p.addAll(<double>[x, y, z]);
    return id;
  }

  void addTriangle(int a, int b, int c) => _i.addAll(<int>[a, b, c]);

  int get vertexCount => _p.length ~/ 3;
  int get faceCount => _i.length ~/ 3;

  TriMesh build() {
    final positions = Float32List(_p.length);
    for (var i = 0; i < _p.length; i++) {
      positions[i] = _p[i];
    }
    final indices = Uint32List(_i.length);
    for (var i = 0; i < _i.length; i++) {
      indices[i] = _i[i];
    }
    return TriMesh(positions, indices);
  }
}

/// Builds a closed cylinder mesh from p0 to p1 (used for support posts).
TriMesh cylinderMesh(List<double> p0, List<double> p1, double r0, double r1,
    {int sides = 12, bool caps = true}) {
  final b = MeshBuilder();
  final dx = p1[0] - p0[0], dy = p1[1] - p0[1], dz = p1[2] - p0[2];
  final len = length3(dx, dy, dz);
  if (len < 1e-9) return TriMesh.empty();
  final ux = dx / len, uy = dy / len, uz = dz / len;
  // Pick a stable perpendicular basis.
  var tx = 0.0, ty = 0.0, tz = 0.0;
  if (ux.abs() < 0.9) {
    tx = 0;
    ty = -uz;
    tz = uy;
  } else {
    tx = uz;
    ty = 0;
    tz = -ux;
  }
  final tl = length3(tx, ty, tz);
  tx /= tl;
  ty /= tl;
  tz /= tl;
  final bx = uy * tz - uz * ty, by = uz * tx - ux * tz, bz = ux * ty - uy * tx;

  final ring0 = <int>[];
  final ring1 = <int>[];
  for (var s = 0; s < sides; s++) {
    final a = 2 * math.pi * s / sides;
    final ca = math.cos(a), sa = math.sin(a);
    final ox = tx * ca + bx * sa,
        oy = ty * ca + by * sa,
        oz = tz * ca + bz * sa;
    ring0.add(b.addVertex(p0[0] + ox * r0, p0[1] + oy * r0, p0[2] + oz * r0));
    ring1.add(b.addVertex(p1[0] + ox * r1, p1[1] + oy * r1, p1[2] + oz * r1));
  }
  for (var s = 0; s < sides; s++) {
    final s2 = (s + 1) % sides;
    b.addTriangle(ring0[s], ring1[s], ring1[s2]);
    b.addTriangle(ring0[s], ring1[s2], ring0[s2]);
  }
  if (caps) {
    final c0 = b.addVertex(p0[0], p0[1], p0[2]);
    final c1 = b.addVertex(p1[0], p1[1], p1[2]);
    for (var s = 0; s < sides; s++) {
      final s2 = (s + 1) % sides;
      b.addTriangle(c0, ring0[s2], ring0[s]);
      b.addTriangle(c1, ring1[s], ring1[s2]);
    }
  }
  return b.build();
}
