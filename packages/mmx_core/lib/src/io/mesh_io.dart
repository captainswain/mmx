import 'dart:convert';
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import '../tools/modify.dart';
import 'mix.dart';
import 'obj.dart';
import 'ply.dart';
import 'polygon_triangulation.dart';
import 'stl.dart';
import 'threemf.dart';

/// Format sniffing and dispatch. Mirrors the import set observed in the
/// shipped Meshmixer binary: obj, ply, stl, off (plus amf/3mf/mix upstream).
class MeshIO {
  static const List<String> importExtensions = <String>[
    'obj',
    'ply',
    'stl',
    'off',
    '3mf',
    'mix'
  ];

  static const exportExtensions = <String>['stl', 'obj', 'ply', '3mf', 'mix'];
  static const maxFileBytes = 256 * 1024 * 1024;

  static TriMesh readBytes(String filename, Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('File exceeds 256 MiB limit');
    }
    try {
      final mesh = _readBytes(filename, bytes);
      final errors = mesh.validate();
      if (errors.isNotEmpty) throw FormatException(errors.join(', '));
      return mesh;
    } on RangeError {
      throw const FormatException('Truncated or invalid mesh data');
    }
  }

  static TriMesh _readBytes(String filename, Uint8List bytes) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'stl':
        if (bytes.length >= 84 &&
            ByteData.sublistView(bytes).getUint32(80, Endian.little) * 50 +
                    84 ==
                bytes.length) {
          return StlIO.readBinary(bytes);
        }
        // ASCII STL starts with "solid" and contains "facet".
        final head = String.fromCharCodes(
            bytes.sublist(0, bytes.length < 512 ? bytes.length : 512));
        if (head.trimLeft().toLowerCase().startsWith('solid') &&
            (head.toLowerCase().contains('facet') ||
                head.toLowerCase().contains('endsolid'))) {
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
        throw FormatException('Unsupported import format: $ext');
    }
  }

  static TriMesh readOff(String text) {
    if (text.length > maxFileBytes) {
      throw const FormatException('OFF exceeds size limit');
    }
    final matches = RegExp(r'\S+')
        .allMatches(text.replaceAll(RegExp(r'#[^\r\n]*'), ''))
        .iterator;
    String token() {
      if (!matches.moveNext()) throw const FormatException('Truncated OFF');
      return matches.current.group(0)!;
    }

    if (token() != 'OFF') throw const FormatException('Invalid OFF header');
    final nv = int.parse(token()),
        nf = int.parse(token()),
        edges = int.parse(token());
    if (nv < 0 ||
        nv > 2000000 ||
        nf < 0 ||
        nf > 4000000 ||
        edges < 0 ||
        nv * 3 + nf * 4 > text.length) {
      throw const FormatException('Invalid OFF counts');
    }
    final positions = Float32List(nv * 3);
    for (var i = 0; i < positions.length; i++) {
      positions[i] = double.parse(token());
      if (!positions[i].isFinite) {
        throw const FormatException('Non-finite OFF coordinate');
      }
    }
    final indices = <int>[];
    for (var f = 0; f < nf; f++) {
      final n = int.parse(token());
      if (n < 3 || n > 4096) {
        throw const FormatException('Invalid OFF polygon size');
      }
      final polygon = List<int>.generate(n, (_) => int.parse(token()));
      final triangles = triangulatePolygon(positions, polygon);
      if (indices.length + triangles.length > 12000000) {
        throw const FormatException('OFF triangle limit exceeded');
      }
      indices.addAll(triangles);
    }
    return TriMesh(positions, Uint32List.fromList(indices));
  }

  static Uint8List writeBytes(String filename, TriMesh mesh,
      {bool binaryStl = true}) {
    final errors = mesh.validate();
    if (errors.isNotEmpty) throw FormatException(errors.join(', '));
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
        throw FormatException('Unsupported export format: $ext');
    }
  }
}
