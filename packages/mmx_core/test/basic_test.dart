import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = 'test/fixtures/models';

TriMesh loadModel(String name) {
  final f = File('$modelsDir/$name');
  return MeshIO.readBytes(name, f.readAsBytesSync());
}

void main() {
  group('import and structural analysis', () {
    test('bunny imports with sane structure', () {
      final mesh = loadModel('bunnyr.obj');
      expect(mesh.faceCount, greaterThan(1000));
      expect(mesh.validate(), isEmpty);
      final b = mesh.bounds();
      expect(b.diagonal, greaterThan(0));
      final topo = MeshTopology(mesh);
      expect(topo.edgeFaces.isNotEmpty, isTrue);
      print('bunny: verts=${mesh.vertexCount} faces=${mesh.faceCount} '
          'area=${mesh.surfaceArea().toStringAsFixed(4)} '
          'volume=${mesh.signedVolume().toStringAsFixed(4)} '
          'components=${topo.components().$2} '
          'boundaryLoops=${topo.boundaryLoops().length} '
          'avgValence=${topo.averageValence().toStringAsFixed(2)}');
    });

    test('STL round trip preserves geometry', () {
      final mesh = loadModel('sphere.obj');
      final stl = StlIO.writeBinary(mesh);
      final back = StlIO.readBinary(stl);
      expect(back.faceCount, mesh.faceCount);
      expect(
          (back.surfaceArea() - mesh.surfaceArea()).abs() / mesh.surfaceArea(),
          lessThan(1e-4));
    });

    test('OBJ and PLY round trip', () {
      final mesh = loadModel('sphere.obj');
      final obj = ObjIO.read(ObjIO.write(mesh));
      expect(obj.faceCount, mesh.faceCount);
      final ply =
          PlyIO.read(Uint8List.fromList(PlyIO.writeAscii(mesh).codeUnits));
      expect(ply.faceCount, mesh.faceCount);
    });
  });

  group('repair', () {
    test('welds duplicated vertices', () {
      final mesh = loadModel('sphere.obj');
      // Explode the mesh into independent triangles.
      final builder = MeshBuilder();
      for (var f = 0; f < mesh.faceCount; f++) {
        final ids = <int>[];
        for (var k = 0; k < 3; k++) {
          final v = mesh.indices[f * 3 + k];
          ids.add(builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v)));
        }
        builder.addTriangle(ids[0], ids[1], ids[2]);
      }
      final exploded = builder.build();
      final welded = Weld.weldVertices(exploded, tolerance: 1e-5);
      expect(welded.vertexCount, lessThan(exploded.vertexCount));
      expect(welded.faceCount, exploded.faceCount);
      final topo = MeshTopology(welded);
      expect(topo.boundaryLoops(), isEmpty);
    });

    test('fills punched holes', () {
      final mesh = loadModel('sphere.obj');
      // Remove 12 faces to create a hole.
      final keep = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (f < 12) continue;
        keep.addAll(<int>[
          mesh.indices[f * 3],
          mesh.indices[f * 3 + 1],
          mesh.indices[f * 3 + 2]
        ]);
      }
      final holed = TriMesh(mesh.positions, Uint32List.fromList(keep));
      final before = MeshTopology(holed).boundaryLoops();
      expect(before.isNotEmpty, isTrue);
      final filled = HoleFiller.fill(holed);
      final after = MeshTopology(filled).boundaryLoops();
      expect(after.length, lessThan(before.length));
      print('holes: loops ${before.length} -> ${after.length}, '
          'faces ${holed.faceCount} -> ${filled.faceCount}');
    });

    test('inspector reports holes', () {
      final mesh = loadModel('sphere.obj');
      final keep = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (f < 6) continue;
        keep.addAll(<int>[
          mesh.indices[f * 3],
          mesh.indices[f * 3 + 1],
          mesh.indices[f * 3 + 2]
        ]);
      }
      final holed = TriMesh(mesh.positions, Uint32List.fromList(keep));
      final defects = MeshInspector.scan(holed);
      expect(
          defects.where((d) => d.kind == DefectKind.hole).isNotEmpty, isTrue);
    });
  });

  group('spatial', () {
    test('BVH raycast hits the surface', () {
      final mesh = loadModel('sphere.obj');
      final bvh = TriangleBVH.build(mesh);
      final b = mesh.bounds();
      final hit = bvh.raycast(
          <double>[b.minX - 1, (b.minY + b.maxY) / 2, (b.minZ + b.maxZ) / 2],
          <double>[1, 0, 0]);
      expect(hit, isNotNull);
      expect(hit!.t, greaterThan(0));
      final hits = bvh.raycastAll(
          <double>[b.minX - 1, (b.minY + b.maxY) / 2, (b.minZ + b.maxZ) / 2],
          <double>[1, 0, 0]);
      expect(hits.length, greaterThanOrEqualTo(2));
    });

    test('closest point on surface', () {
      final mesh = loadModel('sphere.obj');
      final bvh = TriangleBVH.build(mesh);
      final b = mesh.bounds();
      final cp = bvh.closestPoint(
          b.maxX + 5, (b.minY + b.maxY) / 2, (b.minZ + b.maxZ) / 2);
      expect(cp, isNotNull);
      expect(cp!.distance, greaterThan(0));
    });
  });
}
