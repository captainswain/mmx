import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_core/src/io/polygon_triangulation.dart';
import 'package:test/test.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
final polygon = <double>[0, 0, 0, 3, 0, 0, 3, 1, 0, 1, 1, 0, 1, 3, 0, 0, 3, 0];
TriMesh triangle() => TriMesh(Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
    Uint32List.fromList([0, 1, 2]));

void main() {
  group('polygon import', () {
    test('concave OBJ and OFF preserve area and winding', () {
      final vertices = [
        for (var i = 0; i < 6; i++) '${polygon[i * 3]} ${polygon[i * 3 + 1]} 0'
      ];
      for (final reverse in [false, true]) {
        final ids = reverse ? [5, 4, 3, 2, 1, 0] : [0, 1, 2, 3, 4, 5];
        final obj = ObjIO.read(
            '${vertices.map((v) => 'v $v').join('\n')}\nf ${ids.map((i) => i + 1).join(' ')}');
        final off = MeshIO.readOff(
            'OFF\n6 1 0\n${vertices.join('\n')}\n6 ${ids.join(' ')}');
        for (final mesh in [obj, off]) {
          expect(mesh.faceCount, 4);
          expect(mesh.surfaceArea(), closeTo(5, 1e-6));
          expect(mesh.validate(), isEmpty);
          for (var f = 0; f < mesh.faceCount; f++) {
            final a = mesh.indices[f * 3],
                b = mesh.indices[f * 3 + 1],
                c = mesh.indices[f * 3 + 2];
            final winding =
                (mesh.vx(b) - mesh.vx(a)) * (mesh.vy(c) - mesh.vy(a)) -
                    (mesh.vy(b) - mesh.vy(a)) * (mesh.vx(c) - mesh.vx(a));
            expect(winding.sign, reverse ? -1 : 1);
          }
        }
      }
    });
    test('concave prism imports watertight with correct volume', () {
      final vertices = [
        for (final z in [0, 2])
          for (var i = 0; i < 6; i++)
            'v ${polygon[i * 3]} ${polygon[i * 3 + 1]} $z'
      ];
      final faces = [
        'f 6 5 4 3 2 1',
        'f 7 8 9 10 11 12',
        for (var i = 0; i < 6; i++)
          'f ${i + 1} ${(i + 1) % 6 + 1} ${(i + 1) % 6 + 7} ${i + 7}'
      ];
      final mesh = ObjIO.read([...vertices, ...faces].join('\n'));
      expect(mesh.signedVolume(), closeTo(10, 1e-6));
      expect(MeshTopology(mesh).boundaryLoops(), isEmpty);
      expect(MeshTopology(mesh).nonManifoldEdges(), isEmpty);
    });
    test(
        'collinear and closed-loop vertices are handled, self-crossings rejected',
        () {
      final p = <double>[0, 0, 0, 1, 0, 0, 2, 0, 0, 2, 2, 0, 0, 2, 0];
      final t = triangulatePolygon(p, [0, 1, 2, 3, 4, 0]);
      expect(
          TriMesh(Float32List.fromList(p), Uint32List.fromList(t))
              .surfaceArea(),
          4);
      expect(() => triangulatePolygon(p, [0, 3, 2, 4]), throwsFormatException);
      expect(() => triangulatePolygon(p, [0, 1, 0, 3]), throwsFormatException);
      expect(() => triangulatePolygon(p, [0, 9, 2]), throwsFormatException);
      expect(() => triangulatePolygon(p, [0, 1]), throwsFormatException);
    });
    test('dominant-plane projection handles all coordinate planes', () {
      for (var axis = 0; axis < 3; axis++) {
        final p = <double>[];
        for (var i = 0; i < 6; i++) {
          final v = [0.0, 0.0, 0.0];
          v[(axis + 1) % 3] = polygon[i * 3];
          v[(axis + 2) % 3] = polygon[i * 3 + 1];
          p.addAll(v);
        }
        final mesh = TriMesh(Float32List.fromList(p),
            Uint32List.fromList(triangulatePolygon(p, [0, 1, 2, 3, 4, 5])));
        expect(mesh.surfaceArea(), closeTo(5, 1e-6));
      }
    });
    test('OBJ preserves unused vertices, RGB, group IDs and negative indices',
        () {
      final mesh = ObjIO.read(
          'v 0 0 0 1 0 0\nv 1 0 0 0 1 0\nv 0 1 0 0 0 1\nv 9 9 9\ng group_42\nf -4 -3 -2');
      final back = ObjIO.read(ObjIO.write(mesh));
      expect(back.vertexCount, 4);
      expect(back.vertexColors, mesh.vertexColors);
      expect(back.faceGroups, [42]);
      expect(back.indices, [0, 1, 2]);
      expect(ObjIO.read('v 2 4 6 2').positions, [1, 2, 3]);
    });
    test('malformed OBJ and OFF counts fail before allocation', () {
      for (final s in [
        'v 0 0',
        'v 1 2 3 0',
        'v NaN 0 0',
        'v 0 0 0\nf 1 1',
        'v 0 0 0\nf 0 1 1',
        'v 0 0 0\nf 9 1 1'
      ]) {
        expect(() => ObjIO.read(s), throwsFormatException);
      }
      for (final s in [
        'OFF\n999999999 1 0',
        'OFF\n-1 0 0',
        'OFF\n3 1 0\n0 0 0',
        'OFF\n0 1 0\n999999999'
      ]) {
        expect(() => MeshIO.readOff(s), throwsFormatException);
      }
    });
  });
  group('PLY schemas', () {
    test('CRLF ascii properties, unknown elements and colors', () {
      final text = '''ply
format ascii 1.0
comment schema coverage
element edge 1
property list uchar float weights
property uint id
element vertex 3
property double z
property ushort red
property double x
property ushort green
property double y
property ushort blue
element face 1
property float confidence
property list ushort ushort vertex_index
property ushort group_id
end_header
2 0.2 0.8 12
0 65535 0 0 0 0
0 0 1 65535 0 0
0 0 0 0 1 65535
0.9 3 0 1 2 77
''';
      final mesh = PlyIO.read(bytes(text.replaceAll('\n', '\r\n')));
      expect(mesh.positions, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
      expect(mesh.vertexColors, [1, 0, 0, 0, 1, 0, 0, 0, 1]);
      expect(mesh.faceGroups, [77]);
      final back = PlyIO.read(bytes(PlyIO.writeAscii(mesh)));
      expect(back.vertexColors, mesh.vertexColors);
      expect(back.faceGroups, mesh.faceGroups);
    });
    for (final endian in [Endian.little, Endian.big]) {
      test(
          'binary ${endian == Endian.little ? 'little' : 'big'} endian consumes typed properties',
          () {
        final header = bytes(
            'ply\nformat binary_${endian == Endian.little ? 'little' : 'big'}_endian 1.0\nelement face 1\nproperty uchar material\nproperty list ushort uint vertex_indices\nelement vertex 3\nproperty int16 dummy\nproperty float64 y\nproperty float32 z\nproperty float64 x\nend_header\n');
        final data = ByteData(15 + 3 * 22);
        var o = 0;
        data.setUint8(o++, 1);
        data.setUint16(o, 3, endian);
        o += 2;
        for (var i = 0; i < 3; i++) {
          data.setUint32(o, i, endian);
          o += 4;
        }
        for (var i = 0; i < 3; i++) {
          data.setInt16(o, -12, endian);
          o += 2;
          data.setFloat64(o, i == 2 ? 1 : 0, endian);
          o += 8;
          data.setFloat32(o, 0, endian);
          o += 4;
          data.setFloat64(o, i == 1 ? 1 : 0, endian);
          o += 8;
        }
        final mesh = PlyIO.read(
            Uint8List.fromList([...header, ...data.buffer.asUint8List()]));
        expect(mesh.surfaceArea(), .5);
        expect(mesh.indices, [0, 1, 2]);
      });
    }
    test('concave faces and flexible scalar aliases', () {
      final text =
          'ply\nformat ascii 1.0\nelement vertex 6\nproperty float32 x\nproperty float64 y\nproperty int8 z\nelement face 1\nproperty list uint8 int32 vertex_indices\nend_header\n${[
        for (var i = 0; i < 6; i++) '${polygon[i * 3]} ${polygon[i * 3 + 1]} 0'
      ].join('\n')}\n6 0 1 2 3 4 5\n';
      expect(PlyIO.read(bytes(text)).surfaceArea(), 5);
    });
    test(
        'invalid declarations, list counts, truncation and scalar ranges reject',
        () {
      const base =
          'ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n';
      for (final changed in [
        base.replaceFirst('ascii', 'unknown'),
        base.replaceFirst('vertex 3', 'vertex 999999999'),
        base.replaceFirst('float x', 'xyz x'),
        base.replaceFirst('uchar int', 'float int'),
        base.replaceFirst('3 0 1 2', '255 0'),
        base.replaceFirst('3 0 1 2', '3 0 1 -1'),
        '$base 1 2 3',
        base.replaceFirst(
            'end_header', 'property list uchar float vertex_index\nend_header'),
        base.replaceFirst('0 0 0', 'NaN 0 0'),
        base.substring(0, base.length - 5)
      ]) {
        expect(() => PlyIO.read(bytes(changed)), throwsFormatException,
            reason: changed);
      }
    });
  });
  group('STL grammar', () {
    test('ASCII round-trips multiple solids and exact vertex coordinates', () {
      final mesh = triangle();
      final ascii = StlIO.writeAscii(mesh, name: 'safe\nname');
      final back = StlIO.readAscii('$ascii$ascii');
      expect(back.vertexCount, 3);
      expect(back.faceCount, 2);
      expect(back.surfaceArea(), 1);
      expect(StlIO.readAscii(ascii.toUpperCase()).positions, mesh.positions);
      expect(
          MeshIO.readBytes('empty.stl', bytes('solid empty\nendsolid empty\n'))
              .faceCount,
          0);
      final close = triangle()..positions[3] = 1e-9;
      expect(StlIO.readAscii(StlIO.writeAscii(close)).vertexCount, 3);
      expect(StlIO.readBinary(StlIO.writeBinary(close)).vertexCount, 3);
    });
    test('incomplete, nonfinite and extra facets or bytes reject', () {
      final ascii = StlIO.writeAscii(triangle());
      for (final bad in [
        '',
        ascii.replaceAll('endsolid mmx_core', ''),
        ascii.replaceAll('outer loop', 'outer invalid'),
        ascii.replaceAll('endfacet', ''),
        ascii.replaceFirst('vertex 0.0 0.0 0.0', 'vertex NaN 0 0'),
        ascii.replaceFirst('normal 0 0 0', 'normal NaN 0 0'),
        ascii.replaceAll('endloop', 'vertex 1 1 1\nendloop'),
        '$ascii unknown'
      ]) {
        expect(() => StlIO.readAscii(bad), throwsFormatException, reason: bad);
      }
      final binary = StlIO.writeBinary(triangle());
      expect(() => StlIO.readBinary(Uint8List.fromList([...binary, 0])),
          throwsFormatException);
      expect(() => StlIO.readBinary(Uint8List.sublistView(binary, 0, 83)),
          throwsFormatException);
    });
  });
  group('native and archive fidelity', () {
    test('project preserves original MIX bytes separately from edits', () {
      final source = File('test/fixtures/grouped.mix').readAsBytesSync();
      final mesh = triangle();
      final project = ProjectData([
        SceneObject(1, 'edited', mesh)
      ], sourceAttachments: [
        ProjectSourceAttachment(name: '原本.mix', bytes: source)
      ]);
      final back = ProjectIO.read(ProjectIO.write(project));
      expect(back.sourceAttachments.single.name, '原本.mix');
      expect(back.sourceAttachments.single.bytes, source);
      expect(back.objects.single.mesh.faceCount, 1);
    });
    test('MIX rewrite consumes replaced records and preserves opaque records',
        () {
      final source = File('test/fixtures/grouped.mix').readAsBytesSync();
      final objects = MixIO.read(source);
      final rewritten = MixIO.rewrite(source, objects);
      expect(MixIO.read(rewritten).length, objects.length);
      List<Uint8List> records(Uint8List data) {
        final out = <Uint8List>[];
        var p = 0;
        while (p < data.length) {
          final n = ByteData.sublistView(data).getUint32(p, Endian.little);
          out.add(Uint8List.sublistView(data, p + 4, p + 4 + n));
          p += 4 + n;
        }
        return out;
      }

      final before = records(source), after = records(rewritten);
      expect(after.length, before.length);
      expect(after.first, before.first);
      expect(after.last, before.last);
      expect(() => MixIO.rewrite(source, []), throwsFormatException);
      expect(
          () => MixIO.read(Uint8List.sublistView(source, 0, source.length - 1)),
          throwsFormatException);
    });
    test('ZIP Unicode names and local/header integrity', () {
      final zip = ZipArchive.write([ZipEntry('資料.bin', bytes('payload'))]);
      expect(ZipArchive.read(zip).single.name, '資料.bin');
      final bad = Uint8List.fromList(zip);
      bad[18] ^= 1;
      expect(() => ZipArchive.read(bad), throwsFormatException);
      expect(
          () => ZipArchive.write(
              [ZipEntry('same', bytes('a')), ZipEntry('same', bytes('b'))]),
          throwsFormatException);
    });
    test('3MF uses physical unit round-trips and preserves tiny coordinates',
        () {
      final mesh = triangle();
      for (final unit in [
        'micron',
        'millimeter',
        'centimeter',
        'inch',
        'foot',
        'meter'
      ]) {
        final back = ThreeMfIO.read(ThreeMfIO.write(mesh, unit: unit));
        expect(back.positions, mesh.positions);
      }
      final tiny = triangle()
        ..positions = Float32List.fromList(
            triangle().positions.map((n) => n * 1e-8).toList());
      expect(ThreeMfIO.read(ThreeMfIO.write(tiny)).positions, tiny.positions);
    });
    test('3MF material payload and cycles reject explicitly', () {
      final original = ZipArchive.read(ThreeMfIO.write(triangle()));
      Uint8List replaceModel(String Function(String) f) => ZipArchive.write(
          original
              .map((e) => e.name.endsWith('.model')
                  ? ZipEntry(e.name, bytes(f(utf8.decode(e.data))))
                  : e)
              .toList());
      expect(
          () => ThreeMfIO.read(replaceModel(
              (x) => x.replaceFirst('<triangle ', '<triangle pid="1" '))),
          throwsFormatException);
      expect(
          () => ThreeMfIO.read(replaceModel((x) => x.replaceFirst(
              RegExp(r'<mesh>.*?</mesh>', dotAll: true),
              '<components><component objectid="1"/></components>'))),
          throwsFormatException);
    });
    test('declared project buffers cannot be reused to amplify allocations',
        () {
      final entries = ZipArchive.read(
          ProjectIO.write(ProjectData([SceneObject(1, 'one', triangle())])));
      final manifest = jsonDecode(utf8.decode(entries.first.data));
      final second = Map<String, dynamic>.from(manifest['objects'][0] as Map)
        ..['id'] = 2;
      manifest['objects'].add(second);
      entries[0] = ZipEntry('manifest.json', bytes(jsonEncode(manifest)));
      expect(() => ProjectIO.read(ZipArchive.write(entries)),
          throwsFormatException);
    });
    test('native metadata record counts and vector shapes are bounded', () {
      final original = ZipArchive.read(
          ProjectIO.write(ProjectData([SceneObject(1, 'one', triangle())])));
      for (final change in <void Function(Map<String, dynamic>)>[
        (m) => m['objects'] = List.filled(1025, m['objects'][0]),
        (m) => m['sources'] = List.filled(1025, {}),
        (m) => m['objects'][0]['transform'] = [1, 2],
        (m) => m['camera']['target'] = [0, 0, 0, 0]
      ]) {
        final manifest = jsonDecode(utf8.decode(original.first.data))
            as Map<String, dynamic>;
        change(manifest);
        final entries = [
          ZipEntry('manifest.json', bytes(jsonEncode(manifest))),
          ...original.skip(1)
        ];
        expect(() => ProjectIO.read(ZipArchive.write(entries)),
            throwsFormatException);
      }
    });
  });
  test('seeded parser mutations are bounded and never return invalid geometry',
      () {
    final mesh = triangle();
    final corpus = <String, Uint8List>{
      'obj': bytes(ObjIO.write(mesh)),
      'off': bytes('OFF\n3 1 0\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2'),
      'ply': bytes(PlyIO.writeAscii(mesh)),
      'stl': StlIO.writeBinary(mesh),
      'mix': MixIO.write([MixObject(name: 't', mesh: mesh)]),
      '3mf': ThreeMfIO.write(mesh)
    };
    final random = math.Random(20261109);
    for (final entry in corpus.entries) {
      for (var attempt = 0; attempt < 48; attempt++) {
        final data = Uint8List.fromList(entry.value);
        for (var j = 0; j < 1 + attempt % 4; j++) {
          data[random.nextInt(data.length)] = random.nextInt(256);
        }
        try {
          expect(MeshIO.readBytes('f.${entry.key}', data).validate(), isEmpty);
        } on FormatException {
          /* Explicit bounded rejection is a valid outcome. */
        }
      }
    }
  });
}
