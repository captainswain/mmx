import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('mix import', () {
    test('reads the scene Meshmixer saved under Wine', () {
      final file = File('/data/re/meshmixer/sample.mix');
      if (!file.existsSync()) {
        markTestSkipped('sample.mix not present');
        return;
      }
      final objects = MixIO.read(file.readAsBytesSync());
      expect(objects.length, 1);
      expect(objects.first.mesh.vertexCount, 5550);
      expect(objects.first.mesh.faceCount, 10996);
      expect(objects.first.mesh.signedVolume(), closeTo(1.2413, 0.01));
      expect(objects.first.name, contains('bunny'));
    });

    test('MeshIO dispatches .mix to the scene reader', () {
      final file = File('/data/re/meshmixer/sample.mix');
      if (!file.existsSync()) {
        markTestSkipped('sample.mix not present');
        return;
      }
      final mesh = MeshIO.readBytes('sample.mix', file.readAsBytesSync());
      expect(mesh.faceCount, 10996);
      expect(mesh.vertexCount, 5550);
    });
  });

  group('mix export', () {
    test('round-trips a mesh through the writer', () {
      final mesh = loadModel('bunnyr.obj');
      final bytes = MixIO.write(<MixObject>[
        MixObject(name: 'bunnyr.obj', mesh: mesh),
      ]);
      expect(bytes.length, greaterThan(1000));
      // Container: four length-prefixed records.
      var off = 0;
      var records = 0;
      while (off + 4 <= bytes.length) {
        final len = ByteData.sublistView(bytes, off, off + 4)
            .getUint32(0, Endian.little);
        off += 4 + len;
        records++;
      }
      expect(records, 4);
      expect(off, bytes.length);

      final read = MixIO.read(bytes);
      expect(read.length, 1);
      expect(read.first.mesh.vertexCount, mesh.vertexCount);
      expect(read.first.mesh.faceCount, mesh.faceCount);
      expect(read.first.mesh.signedVolume(),
          closeTo(mesh.signedVolume(), mesh.signedVolume().abs() * 0.02));
      expect(read.first.name, 'bunnyr.obj');
    });

    test('writes a sphere scene that reads back closed', () {
      final mesh = loadModel('sphere.obj');
      final bytes = MixIO.write(<MixObject>[
        MixObject(name: 'sphere.obj', mesh: mesh),
      ]);
      final read = MixIO.read(bytes);
      expect(read.length, 1);
      expect(read.first.mesh.faceCount, mesh.faceCount);
      expect(MeshTopology(read.first.mesh).boundaryLoops(), isEmpty);
      expect(read.first.mesh.signedVolume(),
          closeTo(mesh.signedVolume(), mesh.signedVolume().abs() * 0.02));
    });
  });
}
