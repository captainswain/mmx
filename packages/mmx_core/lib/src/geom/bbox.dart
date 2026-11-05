import 'dart:math' as math;
import 'dart:typed_data';

/// Axis-aligned bounding box. Mutable accumulators used by builders.
class BBox {
  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;
  double maxZ = double.negativeInfinity;

  BBox();

  BBox.fromBounds(
      this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ);

  bool get isEmpty => minX > maxX;

  double get extentX => isEmpty ? 0 : maxX - minX;
  double get extentY => isEmpty ? 0 : maxY - minY;
  double get extentZ => isEmpty ? 0 : maxZ - minZ;

  void add(double x, double y, double z) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }

  void addBox(BBox o) {
    if (o.isEmpty) return;
    add(o.minX, o.minY, o.minZ);
    add(o.maxX, o.maxY, o.maxZ);
  }

  void expand(double d) {
    if (isEmpty) return;
    minX -= d;
    minY -= d;
    minZ -= d;
    maxX += d;
    maxY += d;
    maxZ += d;
  }

  double get diagonal {
    final dx = extentX, dy = extentY, dz = extentZ;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  double get volume => isEmpty ? 0 : extentX * extentY * extentZ;

  BBox clone() => BBox.fromBounds(minX, minY, minZ, maxX, maxY, maxZ);

  /// Writes 6 doubles [minx,miny,minz,maxx,maxy,maxz].
  void writeTo(Float64List out, int offset) {
    out[offset] = minX;
    out[offset + 1] = minY;
    out[offset + 2] = minZ;
    out[offset + 3] = maxX;
    out[offset + 4] = maxY;
    out[offset + 5] = maxZ;
  }

  static double surfaceAreaOf(BBox b) {
    if (b.isEmpty) return 0;
    final dx = b.extentX, dy = b.extentY, dz = b.extentZ;
    return 2 * (dx * dy + dy * dz + dz * dx);
  }
}

/// Small vector helpers. Kept as free functions over doubles to avoid
/// allocating objects in hot loops.
double dot3(double ax, double ay, double az, double bx, double by, double bz) =>
    ax * bx + ay * by + az * bz;

List<double> cross3(
    double ax, double ay, double az, double bx, double by, double bz) {
  return <double>[ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx];
}

double length3(double x, double y, double z) =>
    math.sqrt(x * x + y * y + z * z);

/// Closest point on triangle abc to p. Returns barycentric (u,v,w) plus
/// squared distance in [out]. This is the Ericson "closest point on triangle"
/// routine, written branch-explicit for speed.
double closestPointTriangleSq(
  double px,
  double py,
  double pz,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  double cx,
  double cy,
  double cz,
  Float64List out,
) {
  final abx = bx - ax, aby = by - ay, abz = bz - az;
  final acx = cx - ax, acy = cy - ay, acz = cz - az;
  final apx = px - ax, apy = py - ay, apz = pz - az;
  final d1 = dot3(abx, aby, abz, apx, apy, apz);
  final d2 = dot3(acx, acy, acz, apx, apy, apz);
  if (d1 <= 0 && d2 <= 0) {
    out[0] = 1;
    out[1] = 0;
    out[2] = 0;
    return apx * apx + apy * apy + apz * apz;
  }
  final bpx = px - bx, bpy = py - by, bpz = pz - bz;
  final d3 = dot3(abx, aby, abz, bpx, bpy, bpz);
  final d4 = dot3(acx, acy, acz, bpx, bpy, bpz);
  if (d3 >= 0 && d4 <= d3) {
    out[0] = 0;
    out[1] = 1;
    out[2] = 0;
    return bpx * bpx + bpy * bpy + bpz * bpz;
  }
  final vc = d1 * d4 - d3 * d2;
  if (vc <= 0 && d1 >= 0 && d3 <= 0) {
    final v = d1 / (d1 - d3);
    out[0] = 1 - v;
    out[1] = v;
    out[2] = 0;
    final qx = px - (ax + abx * v),
        qy = py - (ay + aby * v),
        qz = pz - (az + abz * v);
    return qx * qx + qy * qy + qz * qz;
  }
  final cpx = px - cx, cpy = py - cy, cpz = pz - cz;
  final d5 = dot3(abx, aby, abz, cpx, cpy, cpz);
  final d6 = dot3(acx, acy, acz, cpx, cpy, cpz);
  if (d6 >= 0 && d5 <= d6) {
    out[0] = 0;
    out[1] = 0;
    out[2] = 1;
    return cpx * cpx + cpy * cpy + cpz * cpz;
  }
  final vb = d5 * d2 - d1 * d6;
  if (vb <= 0 && d2 >= 0 && d6 <= 0) {
    final w = d2 / (d2 - d6);
    out[0] = 1 - w;
    out[1] = 0;
    out[2] = w;
    final qx = px - (ax + acx * w),
        qy = py - (ay + acy * w),
        qz = pz - (az + acz * w);
    return qx * qx + qy * qy + qz * qz;
  }
  final va = d3 * d6 - d5 * d4;
  if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
    final w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
    out[0] = 0;
    out[1] = 1 - w;
    out[2] = w;
    final qx = px - (bx + (cx - bx) * w),
        qy = py - (by + (cy - by) * w),
        qz = pz - (bz + (cz - bz) * w);
    return qx * qx + qy * qy + qz * qz;
  }
  final denom = 1.0 / (va + vb + vc);
  final v = vb * denom;
  final w = vc * denom;
  out[0] = 1 - v - w;
  out[1] = v;
  out[2] = w;
  final qx = px - (ax + abx * v + acx * w);
  final qy = py - (ay + aby * v + acy * w);
  final qz = pz - (az + abz * v + acz * w);
  return qx * qx + qy * qy + qz * qz;
}
