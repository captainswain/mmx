import 'dart:typed_data';

import '../mesh/tri_mesh.dart';

/// PLY import/export: ascii and binary little-endian, vertex x/y/z plus
/// face vertex_indices. Unknown properties are skipped by stride.
class PlyIO {
  static TriMesh read(Uint8List bytes) {
    final text = String.fromCharCodes(bytes.sublist(0, _headerEnd(bytes)));
    final lines = text.split('\n').map((l) => l.trim()).toList();
    if (lines.isEmpty || lines.first != 'ply') return TriMesh.empty();

    var binary = false;
    var bigEndian = false;
    var vertexCount = 0;
    var faceCount = 0;
    var inVertex = false, inFace = false;
    final vertexProps = <String>[];
    final faceProps = <String>[];
    var bodyOffset = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('format')) {
        binary = line.contains('binary');
        bigEndian = line.contains('big_endian');
      } else if (line.startsWith('element vertex')) {
        vertexCount = int.parse(line.split(RegExp(r'\s+')).last);
        inVertex = true;
        inFace = false;
      } else if (line.startsWith('element face')) {
        faceCount = int.parse(line.split(RegExp(r'\s+')).last);
        inFace = true;
        inVertex = false;
      } else if (line.startsWith('property')) {
        final p = line.split(RegExp(r'\s+'));
        if (inVertex && p.length >= 3) vertexProps.add('${p[1]}:${p[2]}');
        if (inFace && p.length >= 3) faceProps.add('${p[1]}:${p[2]}');
      } else if (line == 'end_header') {
        bodyOffset = _offsetOf(bytes, 'end_header\n') + 'end_header\n'.length;
        break;
      }
    }

    final builder = MeshBuilder();
    if (!binary) {
      final body = String.fromCharCodes(bytes.sublist(bodyOffset));
      final bodyLines = body.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      for (var i = 0; i < vertexCount && i < bodyLines.length; i++) {
        final vals = bodyLines[i].split(RegExp(r'\s+'));
        final xi = vertexProps.indexOf('float:x') >= 0 ? vertexProps.indexOf('float:x') : 0;
        final yi = vertexProps.indexOf('float:y') >= 0 ? vertexProps.indexOf('float:y') : 1;
        final zi = vertexProps.indexOf('float:z') >= 0 ? vertexProps.indexOf('float:z') : 2;
        if (vals.length <= xi || vals.length <= yi || vals.length <= zi) continue;
        builder.addVertex(double.parse(vals[xi]), double.parse(vals[yi]), double.parse(vals[zi]));
      }
      for (var i = 0; i < faceCount; i++) {
        final idx = vertexCount + i;
        if (idx >= bodyLines.length) break;
        final vals = bodyLines[idx].split(RegExp(r'\s+'));
        final n = int.parse(vals[0]);
        final ids = <int>[];
        for (var k = 1; k <= n && k < vals.length; k++) {
          ids.add(int.parse(vals[k]));
        }
        for (var k = 2; k < ids.length; k++) {
          builder.addTriangle(ids[0], ids[k - 1], ids[k]);
        }
      }
      return builder.build();
    }

    final bd = ByteData.sublistView(bytes);
    final endian = bigEndian ? Endian.big : Endian.little;
    var off = bodyOffset;
    final xIdx = vertexProps.indexOf('float:x');
    final yIdx = vertexProps.indexOf('float:y');
    final zIdx = vertexProps.indexOf('float:z');
    final hasColor = vertexProps.indexOf('uchar:red') >= 0;
    final colors = <double>[];
    for (var i = 0; i < vertexCount; i++) {
      final vals = <double>[];
      for (final prop in vertexProps) {
        final type = prop.split(':')[0];
        switch (type) {
          case 'float':
            vals.add(bd.getFloat32(off, endian));
            off += 4;
          case 'double':
            vals.add(bd.getFloat64(off, endian));
            off += 8;
          case 'uchar':
            vals.add(bd.getUint8(off).toDouble());
            off += 1;
          case 'char':
            vals.add(bd.getInt8(off).toDouble());
            off += 1;
          case 'ushort':
            vals.add(bd.getUint16(off, endian).toDouble());
            off += 2;
          case 'short':
            vals.add(bd.getInt16(off, endian).toDouble());
            off += 2;
          case 'uint':
            vals.add(bd.getUint32(off, endian).toDouble());
            off += 4;
          case 'int':
            vals.add(bd.getInt32(off, endian).toDouble());
            off += 4;
          default:
            off += 4;
        }
      }
      if (xIdx < 0 || yIdx < 0 || zIdx < 0) continue;
      builder.addVertex(vals[xIdx], vals[yIdx], vals[zIdx]);
      if (hasColor) {
        colors.add(vals[vertexProps.indexOf('uchar:red')] / 255.0);
        colors.add(vals[vertexProps.indexOf('uchar:green')] / 255.0);
        colors.add(vals[vertexProps.indexOf('uchar:blue')] / 255.0);
      }
    }
    // Face element: assume list uchar int vertex_indices.
    for (var i = 0; i < faceCount; i++) {
      final n = bd.getUint8(off);
      off += 1;
      final ids = <int>[];
      for (var k = 0; k < n; k++) {
        ids.add(bd.getInt32(off, endian));
        off += 4;
      }
      for (var k = 2; k < ids.length; k++) {
        builder.addTriangle(ids[0], ids[k - 1], ids[k]);
      }
    }
    final mesh = builder.build();
    if (colors.length == mesh.vertexCount * 3) {
      mesh.vertexColors = Float32List.fromList(colors);
    }
    return mesh;
  }

  static String writeAscii(TriMesh mesh, {String name = 'mesh'}) {
    final sb = StringBuffer('ply\nformat ascii 1.0\ncomment exported by mmx_core\n');
    sb.writeln('element vertex ${mesh.vertexCount}');
    sb.writeln('property float x\nproperty float y\nproperty float z');
    sb.writeln('element face ${mesh.faceCount}');
    sb.writeln('property list uchar int vertex_indices');
    sb.writeln('end_header');
    for (var i = 0; i < mesh.vertexCount; i++) {
      sb.writeln('${mesh.vx(i)} ${mesh.vy(i)} ${mesh.vz(i)}');
    }
    for (var f = 0; f < mesh.faceCount; f++) {
      sb.writeln('3 ${mesh.indices[f * 3]} ${mesh.indices[f * 3 + 1]} ${mesh.indices[f * 3 + 2]}');
    }
    return sb.toString();
  }

  static int _headerEnd(Uint8List bytes) {
    final idx = _offsetOf(bytes, 'end_header');
    return idx < 0 ? bytes.length : idx + 11;
  }

  static int _offsetOf(Uint8List bytes, String needle) {
    final n = needle.codeUnits;
    outer:
    for (var i = 0; i + n.length <= bytes.length; i++) {
      for (var k = 0; k < n.length; k++) {
        if (bytes[i + k] != n[k]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
