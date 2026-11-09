import 'dart:typed_data';
import 'dart:convert';
import 'polygon_triangulation.dart';

import '../mesh/tri_mesh.dart';

/// Wavefront OBJ import/export. Supports negative indices, polygon faces
/// (ear-clipped), and per-object/group segmentation.
class ObjIO {
  static TriMesh read(String text, {bool keepGroups = true}) {
    if (text.length > 256 * 1024 * 1024) {
      throw const FormatException('OBJ exceeds size limit');
    }
    final positions = <double>[], colors = <double>[];
    final indices = <int>[], groupIds = <int>[];
    final groupNames = <String, int>{};
    var currentGroup = 0, anyColor = false;
    int resolve(String token) {
      final n = int.tryParse(token.split('/').first);
      if (n == null || n == 0) {
        throw const FormatException('Invalid OBJ vertex index');
      }
      final i = n > 0 ? n - 1 : positions.length ~/ 3 + n;
      if (i < 0 || i >= positions.length ~/ 3) {
        throw const FormatException('Invalid OBJ vertex index');
      }
      return i;
    }

    for (final raw
        in LineSplitter.split(text.replaceAll(RegExp(r'\\\r?\n'), ' '))) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      if (line.length > 1024 * 1024) {
        throw const FormatException('OBJ line exceeds size limit');
      }
      final parts = line.split(RegExp(r'\s+'));
      switch (parts[0]) {
        case 'v':
          if (positions.length >= 6000000 ||
              ![4, 5, 7].contains(parts.length)) {
            throw const FormatException(
                'Invalid OBJ vertex or vertex limit exceeded');
          }
          final values = parts.skip(1).map(double.parse).toList();
          if (values.any((v) => !v.isFinite)) {
            throw const FormatException('Non-finite OBJ vertex');
          }
          final w = parts.length == 5 ? values[3] : 1.0;
          if (w == 0) {
            throw const FormatException('Zero homogeneous OBJ coordinate');
          }
          positions.addAll(values.take(3).map((v) => v / w));
          if (parts.length == 7) {
            final rgb = values.skip(3).toList();
            if (rgb.any((v) => v < 0 || v > 1)) {
              throw const FormatException('OBJ color outside [0,1]');
            }
            colors.addAll(rgb);
            anyColor = true;
          } else {
            colors.addAll([1, 1, 1]);
          }
        case 'g':
        case 'o':
          if (keepGroups && parts.length > 1) {
            final name = parts.sublist(1).join(' ');
            final encoded = RegExp(r'^group_(\d+)$').firstMatch(name);
            final group = encoded == null
                ? groupNames.putIfAbsent(name, () => groupNames.length + 1)
                : int.parse(encoded.group(1)!);
            if (group > 65535) {
              throw const FormatException('OBJ face group limit exceeded');
            }
            currentGroup = group;
          }
        case 'f':
          if (parts.length < 4 || parts.length > 4097) {
            throw const FormatException('Invalid OBJ polygon');
          }
          final face = parts.skip(1).map(resolve).toList();
          final triangles = triangulatePolygon(positions, face);
          if (indices.length + triangles.length > 12000000) {
            throw const FormatException('OBJ triangle limit exceeded');
          }
          indices.addAll(triangles);
          groupIds
              .addAll(List<int>.filled(triangles.length ~/ 3, currentGroup));
      }
    }
    final mesh = TriMesh(
        Float32List.fromList(positions), Uint32List.fromList(indices),
        vertexColors: anyColor ? Float32List.fromList(colors) : null,
        faceGroups: keepGroups && groupIds.isNotEmpty
            ? Uint16List.fromList(groupIds)
            : null);
    if (mesh.validate().isNotEmpty) {
      throw const FormatException('Invalid OBJ geometry');
    }
    mesh.removeDegenerateFaces();
    return mesh;
  }

  static String write(TriMesh mesh,
      {String name = 'mesh', bool writeGroups = true}) {
    if (mesh.validate().isNotEmpty) {
      throw const FormatException('Invalid OBJ geometry');
    }
    name = name.replaceAll(RegExp(r'[\r\n]'), ' ');
    final sb = StringBuffer('# exported by mmx_core\n');
    for (var i = 0; i < mesh.vertexCount; i++) {
      sb.write('v ${mesh.vx(i)} ${mesh.vy(i)} ${mesh.vz(i)}');
      if (mesh.vertexColors != null) {
        sb.write(
            ' ${mesh.vertexColors![i * 3]} ${mesh.vertexColors![i * 3 + 1]} ${mesh.vertexColors![i * 3 + 2]}');
      }
      sb.writeln();
    }
    if (writeGroups && mesh.faceGroups != null) {
      var last = -1;
      for (var f = 0; f < mesh.faceCount; f++) {
        final g = mesh.faceGroups![f];
        if (g != last) {
          sb.writeln('g group_$g');
          last = g;
        }
        sb.writeln(
            'f ${mesh.indices[f * 3] + 1} ${mesh.indices[f * 3 + 1] + 1} ${mesh.indices[f * 3 + 2] + 1}');
      }
    } else {
      sb.writeln('o $name');
      for (var f = 0; f < mesh.faceCount; f++) {
        sb.writeln(
            'f ${mesh.indices[f * 3] + 1} ${mesh.indices[f * 3 + 1] + 1} ${mesh.indices[f * 3 + 2] + 1}');
      }
    }
    return sb.toString();
  }
}
