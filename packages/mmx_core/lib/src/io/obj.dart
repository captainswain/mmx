import 'dart:typed_data';

import '../mesh/tri_mesh.dart';

/// Wavefront OBJ import/export. Supports negative indices, polygon faces
/// (fan triangulated), and per-object/group segmentation.
class ObjIO {
  static TriMesh read(String text, {bool keepGroups = true}) {
    final positions = <double>[];
    final builder = MeshBuilder();
    // OBJ vertex ids are 1-based over the *file*, so keep an explicit map from
    // file vertex id to builder vertex id.
    final fileToLocal = <int, int>{};
    final groupIds = <int>[];
    var currentGroup = 0;
    final groupNames = <String, int>{};

    int resolve(int objIndex) {
      // objIndex is 1-based and may be negative (relative).
      final abs = objIndex > 0 ? objIndex : positions.length ~/ 3 + objIndex + 1;
      final cached = fileToLocal[abs];
      if (cached != null) return cached;
      final base = (abs - 1) * 3;
      if (base < 0 || base + 2 >= positions.length) return 0;
      final id = builder.addVertex(positions[base], positions[base + 1], positions[base + 2]);
      fileToLocal[abs] = id;
      return id;
    }

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      switch (parts[0]) {
        case 'v':
          if (parts.length >= 4) {
            positions.add(double.parse(parts[1]));
            positions.add(double.parse(parts[2]));
            positions.add(double.parse(parts[3]));
          }
        case 'g':
        case 'o':
          if (keepGroups && parts.length > 1) {
            currentGroup = groupNames.putIfAbsent(parts.sublist(1).join(' '), () => groupNames.length + 1);
          }
        case 'f':
          final idx = <int>[];
          for (var i = 1; i < parts.length; i++) {
            final token = parts[i].split('/').first;
            final v = int.tryParse(token);
            if (v != null) idx.add(resolve(v));
          }
          for (var i = 2; i < idx.length; i++) {
            builder.addTriangle(idx[0], idx[i - 1], idx[i]);
            groupIds.add(currentGroup);
          }
      }
    }
    final mesh = builder.build();
    mesh.removeDegenerateFaces();
    if (keepGroups && groupIds.isNotEmpty) {
      final groups = List<int>.filled(mesh.faceCount, 0);
      for (var i = 0; i < groups.length && i < groupIds.length; i++) {
        groups[i] = groupIds[i];
      }
      mesh.faceGroups = Uint16List.fromList(groups);
    }
    return mesh;
  }

  static String write(TriMesh mesh, {String name = 'mesh', bool writeGroups = true}) {
    final sb = StringBuffer('# exported by mmx_core\n');
    for (var i = 0; i < mesh.vertexCount; i++) {
      sb.writeln('v ${mesh.vx(i)} ${mesh.vy(i)} ${mesh.vz(i)}');
    }
    if (writeGroups && mesh.faceGroups != null) {
      var last = -1;
      for (var f = 0; f < mesh.faceCount; f++) {
        final g = mesh.faceGroups![f];
        if (g != last) {
          sb.writeln('g group_$g');
          last = g;
        }
        sb.writeln('f ${mesh.indices[f * 3] + 1} ${mesh.indices[f * 3 + 1] + 1} ${mesh.indices[f * 3 + 2] + 1}');
      }
    } else {
      sb.writeln('o $name');
      for (var f = 0; f < mesh.faceCount; f++) {
        sb.writeln('f ${mesh.indices[f * 3] + 1} ${mesh.indices[f * 3 + 1] + 1} ${mesh.indices[f * 3 + 2] + 1}');
      }
    }
    return sb.toString();
  }
}
