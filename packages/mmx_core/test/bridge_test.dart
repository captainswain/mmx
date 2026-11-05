import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = 'test/fixtures/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

/// Removes a horizontal band of faces, leaving two parallel boundary loops.
TriMesh slitSphere() {
  final mesh = loadModel('sphere.obj');
  final keep = <int>[];
  for (var f = 0; f < mesh.faceCount; f++) {
    final i0 = mesh.indices[f * 3],
        i1 = mesh.indices[f * 3 + 1],
        i2 = mesh.indices[f * 3 + 2];
    final cy = (mesh.vy(i0) + mesh.vy(i1) + mesh.vy(i2)) / 3;
    if (cy > 1.5 && cy < 4.0) continue;
    keep.addAll(<int>[i0, i1, i2]);
  }
  final out = TriMesh(mesh.positions, Uint32List.fromList(keep));
  out.compact();
  return out;
}

void main() {
  group('bridge', () {
    test('stitching a slit closes both boundary loops', () {
      final slit = slitSphere();
      final loops = MeshTopology(slit).boundaryLoops();
      expect(loops.length, 2);
      final stitched = Bridge.stitchNearest(slit);
      expect(MeshTopology(stitched).boundaryLoops(), isEmpty);
      expect(MeshTopology(stitched).nonManifoldEdges(), isEmpty);
      expect(stitched.faceCount, greaterThan(slit.faceCount));
      expect(stitched.signedVolume(), greaterThan(0));
    });

    test('explicit loop bridging consumes both loops', () {
      final slit = slitSphere();
      final loops = MeshTopology(slit).boundaryLoops();
      final bridged = Bridge.bridgeLoops(slit, loops[0], loops[1]);
      expect(MeshTopology(bridged).boundaryLoops(), isEmpty);
    });
  });
}
