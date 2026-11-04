import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('mirror', () {
    test('reflection has the same volume and mirrored bounds', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final mirrored = Mirror.mirror(mesh,
          point: <double>[0, 0, 0], normal: <double>[1, 0, 0], keepOriginal: false);
      expect(mirrored.faceCount, mesh.faceCount);
      expect(mirrored.signedVolume(), closeTo(mesh.signedVolume(), mesh.signedVolume() * 0.01));
      final mb = mirrored.bounds();
      expect(mb.minX, closeTo(-b.maxX, 1e-2));
      expect(mb.maxX, closeTo(-b.minX, 1e-2));
    });

    test('keeping the original doubles the volume', () {
      final mesh = loadModel('sphere.obj');
      final both = Mirror.mirror(mesh,
          point: <double>[0, 0, 0], normal: <double>[1, 0, 0], keepOriginal: true);
      expect(both.signedVolume(), closeTo(mesh.signedVolume() * 2, mesh.signedVolume() * 0.02));
    });

    test('seam welding closes a split sphere', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final merged = Mirror.mirror(mesh,
          point: <double>[b.maxX, 0, 0],
          normal: <double>[1, 0, 0],
          keepOriginal: true,
          weldTolerance: mesh.bounds().diagonal * 1e-4);
      expect(merged.validate(), isEmpty);
      expect(merged.signedVolume(), greaterThan(0));
    });
  });

  group('extrude', () {
    test('extruding a selection adds a skirt and stays closed', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final center = <double>[(b.minX + b.maxX) / 2, b.maxY, (b.minZ + b.maxZ) / 2];
      final sel = Selection.sphereBrush(mesh, center, b.extentX * 0.25);
      final extruded = Extruder.extrude(mesh,
          faceMask: sel.faceMask, distance: b.extentX * 0.08);
      expect(extruded.faceCount, greaterThan(mesh.faceCount));
      expect(extruded.bounds().maxY, greaterThan(mesh.bounds().maxY));
      final loops = MeshTopology(extruded).boundaryLoops();
      expect(loops, isEmpty, reason: 'extruding a patch of a closed mesh must stay closed');
    });

    test('zero distance is a no-op', () {
      final mesh = loadModel('sphere.obj');
      final sel = Selection.sphereBrush(mesh, <double>[0, 12.5, 0], 4);
      final out = Extruder.extrude(mesh, faceMask: sel.faceMask, distance: 0);
      expect(out.faceCount, mesh.faceCount);
    });
  });

  group('separate shells', () {
    test('splits a two-shell mesh', () {
      final a = loadModel('sphere.obj');
      final b = a.clone();
      final dx = a.bounds().extentX * 1.5;
      b.transform(Float64List.fromList(<double>[
        1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, dx, 0, 0, 1,
      ]));
      final merged = <TriMesh>[a, b];
      var totalV = 0;
      for (final m in merged) {
        totalV += m.vertexCount;
      }
      final pos = Float32List(totalV * 3);
      final idx = <int>[];
      var pi = 0, off = 0;
      for (final m in merged) {
        pos.setRange(pi, pi + m.positions.length, m.positions);
        pi += m.positions.length;
        for (var i = 0; i < m.indices.length; i++) {
          idx.add(m.indices[i] + off);
        }
        off += m.vertexCount;
      }
      final combined = TriMesh(pos, Uint32List.fromList(idx));
      final shells = ShellSeparator.separate(combined);
      expect(shells.length, 2);
      for (final s in shells) {
        expect(s.faceCount, greaterThan(0));
        expect(s.validate(), isEmpty);
      }
    });
  });

  group('3MF', () {
    test('round trips vertices and triangles', () {
      final mesh = loadModel('sphere.obj');
      final bytes = ThreeMfIO.write(mesh);
      expect(bytes.length, greaterThan(100));
      final back = ThreeMfIO.read(bytes);
      expect(back.vertexCount, mesh.vertexCount);
      expect(back.faceCount, mesh.faceCount);
      expect((back.surfaceArea() - mesh.surfaceArea()).abs() / mesh.surfaceArea(),
          lessThan(1e-3));
      // MeshIO dispatch by extension.
      final viaIo = MeshIO.readBytes('model.3mf', bytes);
      expect(viaIo.faceCount, mesh.faceCount);
    });

    test('zip archive round trips entries', () {
      final entries = <ZipEntry>[
        ZipEntry('a.txt', Uint8List.fromList('hello'.codeUnits)),
        ZipEntry('dir/b.bin', Uint8List.fromList(<int>[1, 2, 3, 4, 5])),
      ];
      final archive = ZipArchive.write(entries);
      final back = ZipArchive.read(archive);
      expect(back.length, 2);
      expect(String.fromCharCodes(back.first.data), 'hello');
      expect(back.last.data, <int>[1, 2, 3, 4, 5]);
    });
  });
}
