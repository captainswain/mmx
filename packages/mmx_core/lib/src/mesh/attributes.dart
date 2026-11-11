import 'dart:typed_data';

import '../geom/bbox.dart';
import '../spatial/bvh.dart';
import 'tri_mesh.dart';

/// Interpolates source RGB at each output vertex's nearest surface point.
/// Remeshing changes vertex identities, so copying buffer offsets is invalid.
Float32List? transferVertexColors(TriMesh source, TriMesh output,
    {TriangleBVH? sourceBvh}) {
  final colors = source.vertexColors;
  if (colors == null) return null;
  final bvh = sourceBvh ?? TriangleBVH.build(source);
  final result = Float32List(output.vertexCount * 3);
  final bary = Float64List(3);
  for (var v = 0; v < output.vertexCount; v++) {
    final hit = bvh.closestPoint(output.vx(v), output.vy(v), output.vz(v));
    if (hit == null) {
      throw StateError('Cannot transfer colors from an empty surface');
    }
    final a = source.indices[hit.face * 3];
    final b = source.indices[hit.face * 3 + 1];
    final c = source.indices[hit.face * 3 + 2];
    closestPointTriangleSq(
        hit.point[0],
        hit.point[1],
        hit.point[2],
        source.vx(a),
        source.vy(a),
        source.vz(a),
        source.vx(b),
        source.vy(b),
        source.vz(b),
        source.vx(c),
        source.vy(c),
        source.vz(c),
        bary);
    for (var k = 0; k < 3; k++) {
      result[v * 3 + k] = colors[a * 3 + k] * bary[0] +
          colors[b * 3 + k] * bary[1] +
          colors[c * 3 + k] * bary[2];
    }
  }
  return result;
}
