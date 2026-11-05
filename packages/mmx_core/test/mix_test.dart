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

    test('reads the older VFMesh 1.2 sample from the official mm-api repo', () {
      final file = File('test/fixtures/mmapi_sphere.mix');
      if (!file.existsSync()) {
        markTestSkipped('mm-api sphere.mix fixture not present');
        return;
      }
      final objects = MixIO.read(file.readAsBytesSync());
      expect(objects.length, 1);
      expect(objects.first.mesh.vertexCount, 6302);
      expect(objects.first.mesh.faceCount, 12600);
      expect(objects.first.name, 'sphere.obj');
      expect(objects.first.mesh.signedVolume(), closeTo(4.18879, 0.01));
      expect(MeshTopology(objects.first.mesh).boundaryLoops(), isEmpty);
    });

    test('reads face groups from a Meshmixer scene', () {
      final file = File('test/fixtures/grouped.mix');
      if (!file.existsSync()) {
        markTestSkipped('grouped.mix fixture not present');
        return;
      }
      final objects = MixIO.read(file.readAsBytesSync());
      expect(objects.length, 1);
      final groups = objects.first.mesh.faceGroups;
      expect(groups, isNotNull);
      expect(groups!.length, objects.first.mesh.faceCount);
      expect(groups.every((g) => g == 4), isTrue);
    });

    test('writes face groups back into .mix', () {
      final mesh = loadModel('sphere.obj');
      final groups = Uint16List(mesh.faceCount);
      for (var i = 0; i < groups.length; i++) {
        groups[i] = i < groups.length ~/ 2 ? 1 : 2;
      }
      final grouped = TriMesh(mesh.positions, mesh.indices, faceGroups: groups);
      final bytes = MixIO.write([MixObject(name: 'grouped', mesh: grouped)]);
      final back = MixIO.read(bytes).first.mesh;
      expect(back.faceCount, grouped.faceCount);
      expect(back.faceGroups, isNotNull);
      expect(back.faceGroups!.sublist(0, 10), groups.sublist(0, 10));
      expect(back.faceGroups!.sublist(groups.length - 10), groups.sublist(groups.length - 10));
    });

    test('rewrite preserves the scene XML and updates the mesh', () {
      final file = File('test/fixtures/grouped.mix');
      if (!file.existsSync()) {
        markTestSkipped('grouped.mix fixture not present');
        return;
      }
      final original = file.readAsBytesSync();
      final objects = MixIO.read(original);
      final mesh = objects.first.mesh;
      final scaledPositions = Float32List.fromList(
          mesh.positions.map((v) => v * 2.0).toList());
      final scaled = TriMesh(scaledPositions, mesh.indices,
          faceGroups: mesh.faceGroups);
      final rewritten =
          MixIO.rewrite(original, [MixObject(name: 'scaled', mesh: scaled)]);
      final back = MixIO.read(rewritten).first.mesh;
      expect(back.faceCount, mesh.faceCount);
      expect(back.signedVolume(),
          closeTo(mesh.signedVolume() * 8.0, mesh.signedVolume().abs() * 0.01));
      expect(back.faceGroups, isNotNull);
      expect(back.faceGroups!.every((g) => g == 4), isTrue);
      // XML record must be preserved byte-for-byte.
      final bdOriginal = ByteData.sublistView(original);
      final bdRewritten = ByteData.sublistView(rewritten);
      final xmlLen = bdOriginal.getUint32(0, Endian.little);
      expect(bdRewritten.getUint32(0, Endian.little), xmlLen);
      expect(rewritten.sublist(4, 4 + xmlLen),
          original.sublist(4, 4 + xmlLen));
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

    test('multi-object scenes round-trip with names and geometry', () {
      final a = loadModel('sphere.obj');
      final b = Modify.duplicate(a, offset: <double>[30, 0, 0]);
      final bytes = MixIO.write(<MixObject>[
        MixObject(name: 'part_a.obj', mesh: a),
        MixObject(name: 'part_b.obj', mesh: b),
      ]);
      final read = MixIO.read(bytes);
      expect(read.length, 2);
      expect(read[0].name, 'part_a.obj');
      expect(read[1].name, 'part_b.obj');
      expect(read[1].mesh.bounds().minX,
          closeTo(a.bounds().minX + 30, 1e-2));
    });
  });
}
