import 'dart:typed_data';

import '../mesh/tri_mesh.dart';

/// Creates a flat polygon from a boundary loop or a point list, matching the
/// Edit panel's Make Polygon action.
class MakePolygon {
  static TriMesh fromLoop(TriMesh mesh, List<int> loop) {
    if (loop.length < 3) return TriMesh(mesh.positions, mesh.indices);
    final builder = MeshBuilder();
    final ids = <int>[];
    for (final v in loop) {
      ids.add(builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v)));
    }
    for (var i = 1; i + 1 < ids.length; i++) {
      builder.addTriangle(ids[0], ids[i], ids[i + 1]);
    }
    return builder.build();
  }

  static TriMesh fromPoints(List<List<double>> points) {
    if (points.length < 3) return TriMesh(Float32List(0), Uint32List(0));
    final builder = MeshBuilder();
    final ids = <int>[];
    for (final p in points) {
      if (p.length < 3) continue;
      ids.add(builder.addVertex(p[0], p[1], p[2]));
    }
    for (var i = 1; i + 1 < ids.length; i++) {
      builder.addTriangle(ids[0], ids[i], ids[i + 1]);
    }
    return builder.build();
  }
}
