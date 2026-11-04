import 'dart:convert';
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import '../tools/modify.dart';
import 'mix.dart';
import 'obj.dart';
import 'ply.dart';
import 'stl.dart';
import 'threemf.dart';

/// Format sniffing and dispatch. Mirrors the import set observed in the
/// shipped Meshmixer binary: obj, ply, stl, off (plus amf/3mf/mix upstream).
class MeshIO {
  static const List<String> importExtensions = <String>[
    'obj', 'ply', 'stl', 'off', '3mf', 'amf', 'mix'
  ];

  static TriMesh readBytes(String filename, Uint8List bytes) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'stl':
        // ASCII STL starts with "solid" and contains "facet".
        final head = String.fromCharCodes(bytes.sublist(0, bytes.length < 512 ? bytes.length : 512));
        if (head.trimLeft().toLowerCase().startsWith('solid') && head.toLowerCase().contains('facet')) {
          return StlIO.readAscii(utf8.decode(bytes, allowMalformed: true));
        }
        return StlIO.readBinary(bytes);
      case 'ply':
        return PlyIO.read(bytes);
      case 'obj':
        return ObjIO.read(utf8.decode(bytes, allowMalformed: true));
      case 'off':
        return readOff(utf8.decode(bytes, allowMalformed: true));
      case '3mf':
        return ThreeMfIO.read(bytes);
      case 'mix':
        final objects = MixIO.read(bytes);
        if (objects.isEmpty) return TriMesh.empty();
        if (objects.length == 1) return objects.first.mesh;
        return Modify.combine(objects.map((o) => o.mesh).toList());
      default:
        // Fall back on content sniffing.
        if (bytes.length > 84 && bytes[0] == 0x70 && bytes[1] == 0x6C && bytes[2] == 0x79) {
          return PlyIO.read(bytes);
        }
        return ObjIO.read(utf8.decode(bytes, allowMalformed: true));
    }
  }

  static TriMesh readOff(String text) {
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty && !t.startsWith('#')).toList();
    if (tokens.isEmpty || tokens[0] != 'OFF') return TriMesh.empty();
    var i = 1;
    if (tokens[i] == 'OFF') i++;
    final nv = int.parse(tokens[i]);
    final nf = int.parse(tokens[i + 1]);
    i += 3;
    final builder = MeshBuilder();
    for (var v = 0; v < nv; v++) {
      builder.addVertex(double.parse(tokens[i]), double.parse(tokens[i + 1]), double.parse(tokens[i + 2]));
      i += 3;
    }
    for (var f = 0; f < nf; f++) {
      final n = int.parse(tokens[i]);
      final ids = <int>[];
      for (var k = 0; k < n; k++) {
        ids.add(int.parse(tokens[i + 1 + k]));
      }
      i += n + 1;
      for (var k = 2; k < ids.length; k++) {
        builder.addTriangle(ids[0], ids[k - 1], ids[k]);
      }
    }
    return builder.build();
  }

  static Uint8List writeBytes(String filename, TriMesh mesh, {bool binaryStl = true}) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'stl':
        return binaryStl
            ? StlIO.writeBinary(mesh)
            : Uint8List.fromList(utf8.encode(StlIO.writeAscii(mesh)));
      case 'ply':
        return Uint8List.fromList(utf8.encode(PlyIO.writeAscii(mesh)));
      case 'obj':
        return Uint8List.fromList(utf8.encode(ObjIO.write(mesh)));
      case '3mf':
        return ThreeMfIO.write(mesh);
      case 'mix':
        final name = filename.split('/').last.split('\\').last;
        return MixIO.write(<MixObject>[MixObject(name: name, mesh: mesh)]);
      default:
        return StlIO.writeBinary(mesh);
    }
  }
}
