import 'dart:convert';
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import '../scene/document.dart';
import '../tools/pivot.dart';
import '../render/camera.dart';
import 'zip.dart';

/// Original import data retained independently of editable geometry. In
/// particular, opaque .mix records remain recoverable after project edits.
class ProjectSourceAttachment {
  final String name;
  final Uint8List bytes;
  ProjectSourceAttachment({required this.name, required this.bytes});
}

/// Native, versioned editing document. Geometry is stored little-endian.
class ProjectData {
  final List<SceneObject> objects;
  final Camera camera;
  final int? selectedId;
  final List<ProjectSourceAttachment> sourceAttachments;
  ProjectData(this.objects,
      {Camera? camera, this.selectedId, this.sourceAttachments = const []})
      : camera = camera ?? Camera();
}

class ProjectIO {
  static Uint8List write(ProjectData project) {
    final entries = <ZipEntry>[];
    final objects = <Map<String, Object?>>[];
    final ids = <int>{};
    final c = project.camera;
    if (project.objects.length > 1024 ||
        project.sourceAttachments.length > 1024 ||
        ![c.yaw, c.pitch, c.distance, c.fovDegrees, c.near, c.far, ...c.target]
            .every((v) => v.isFinite) ||
        c.target.length != 3 ||
        c.distance <= 0 ||
        c.near <= 0 ||
        c.far <= c.near ||
        c.fovDegrees <= 0 ||
        c.fovDegrees >= 180) {
      throw const FormatException('Invalid project metadata');
    }
    for (final o in project.objects) {
      if (o.id <= 0 ||
          !ids.add(o.id) ||
          o.name.length > 1048576 ||
          o.transform.length != 16 ||
          o.transform.any((v) => !v.isFinite) ||
          o.transform[3] != 0 ||
          o.transform[7] != 0 ||
          o.transform[11] != 0 ||
          o.transform[15] != 1 ||
          (o.pivot != null &&
              (o.pivot!.position.length != 3 ||
                  o.pivot!.normal.length != 3 ||
                  [...o.pivot!.position, ...o.pivot!.normal]
                      .any((v) => !v.isFinite)))) {
        throw const FormatException('Invalid project object metadata');
      }
      final errors = o.mesh.validate();
      if (errors.isNotEmpty) throw FormatException(errors.join(', '));
      String buffer(String name, List<num> values, int width, bool floating) {
        final data = ByteData(values.length * width);
        for (var i = 0; i < values.length; i++) {
          if (floating) {
            data.setFloat32(i * width, values[i].toDouble(), Endian.little);
          } else if (width == 2) {
            data.setUint16(i * width, values[i].toInt(), Endian.little);
          } else {
            data.setUint32(i * width, values[i].toInt(), Endian.little);
          }
        }
        final path = 'objects/${o.id}/$name';
        entries.add(ZipEntry(path, data.buffer.asUint8List()));
        return path;
      }

      objects.add({
        'id': o.id,
        'name': o.name,
        'transform': o.transform.toList(),
        'visible': o.visible,
        'target': o.isTarget,
        'pivot': o.pivot == null
            ? null
            : {'position': o.pivot!.position, 'normal': o.pivot!.normal},
        'positions': buffer('positions', o.mesh.positions, 4, true),
        'indices': buffer('indices', o.mesh.indices, 4, false),
        'groups': o.mesh.faceGroups == null
            ? null
            : buffer('groups', o.mesh.faceGroups!, 2, false),
        'colors': o.mesh.vertexColors == null
            ? null
            : buffer('colors', o.mesh.vertexColors!, 4, true),
      });
    }
    if (project.selectedId != null && !ids.contains(project.selectedId)) {
      throw const FormatException('Missing selected object');
    }
    final sources = <Map<String, String>>[];
    for (var i = 0; i < project.sourceAttachments.length; i++) {
      final source = project.sourceAttachments[i];
      if (source.name.length > 1048576) {
        throw const FormatException('Project source name exceeds limit');
      }
      final path = 'sources/$i.bin';
      sources.add({'name': source.name, 'path': path});
      entries.add(ZipEntry(path, source.bytes));
    }
    entries.insert(
        0,
        ZipEntry(
            'manifest.json',
            Uint8List.fromList(utf8.encode(jsonEncode({
              'version': 1,
              'units': 'millimeter',
              'objects': objects,
              'selectedId': project.selectedId,
              'sources': sources,
              'camera': {
                'yaw': c.yaw,
                'pitch': c.pitch,
                'distance': c.distance,
                'target': c.target,
                'fov': c.fovDegrees,
                'near': c.near,
                'far': c.far
              },
            })))));
    if (entries.length > 4096 ||
        entries.fold<int>(0, (n, e) => n + e.data.length) > 256 * 1024 * 1024) {
      throw const FormatException('Project exceeds archive limits');
    }
    final bytes = ZipArchive.write(entries);
    if (bytes.length > 256 * 1024 * 1024) {
      throw const FormatException('Project exceeds file limit');
    }
    return bytes;
  }

  static ProjectData read(Uint8List bytes) {
    try {
      final files = {for (final e in ZipArchive.read(bytes)) e.name: e.data};
      final m = jsonDecode(utf8.decode(files['manifest.json']!))
          as Map<String, dynamic>;
      if (m['version'] != 1 || m['units'] != 'millimeter') {
        throw const FormatException('Unsupported project version or units');
      }
      final objectRecords = m['objects'] as List;
      final sourceRecords = m['sources'] as List? ?? [];
      if (objectRecords.length > 1024 || sourceRecords.length > 1024) {
        throw const FormatException('Project record count exceeds limit');
      }
      List<double> vector(dynamic value, int length) {
        if (value is! List || value.length != length) {
          throw const FormatException('Invalid project vector');
        }
        final result = value.map((v) => (v as num).toDouble()).toList();
        if (result.any((v) => !v.isFinite)) {
          throw const FormatException('Invalid project vector');
        }
        return result;
      }

      final claimedBuffers = <String>{};
      List<num> buffer(dynamic path, int width, bool floating) {
        if (path is! String ||
            !path.startsWith('objects/') ||
            !claimedBuffers.add(path)) {
          throw const FormatException('Invalid or reused project buffer');
        }
        final bytes = files[path]!;
        if (bytes.length % width != 0) {
          throw const FormatException('Invalid buffer size');
        }
        final data = ByteData.sublistView(bytes);
        final List<num> values = floating
            ? Float32List(bytes.length ~/ width)
            : width == 2
                ? Uint16List(bytes.length ~/ width)
                : Uint32List(bytes.length ~/ width);
        for (var i = 0; i < values.length; i++) {
          values[i] = floating
              ? data.getFloat32(i * width, Endian.little)
              : width == 2
                  ? data.getUint16(i * width, Endian.little)
                  : data.getUint32(i * width, Endian.little);
        }
        return values;
      }

      final sources = <ProjectSourceAttachment>[];
      for (final source in sourceRecords) {
        final path = source['path'] as String;
        final name = source['name'] as String;
        if (!path.startsWith('sources/') ||
            !claimedBuffers.add(path) ||
            name.length > 1048576 ||
            files[path] == null) {
          throw const FormatException('Invalid project source attachment');
        }
        sources.add(ProjectSourceAttachment(name: name, bytes: files[path]!));
      }
      final ids = <int>{};
      final objects = <SceneObject>[];
      for (final o in objectRecords) {
        final id = o['id'] as int;
        final name = o['name'] as String;
        if (id <= 0 || !ids.add(id) || name.length > 1048576) {
          throw const FormatException('Invalid project object metadata');
        }
        final mesh = TriMesh(
            Float32List.fromList(
                buffer(o['positions'], 4, true).cast<double>()),
            Uint32List.fromList(buffer(o['indices'], 4, false).cast<int>()),
            faceGroups: o['groups'] == null
                ? null
                : Uint16List.fromList(
                    buffer(o['groups'], 2, false).cast<int>()),
            vertexColors: o['colors'] == null
                ? null
                : Float32List.fromList(
                    buffer(o['colors'], 4, true).cast<double>()));
        if (mesh.validate().isNotEmpty) {
          throw FormatException(mesh.validate().join(', '));
        }
        final transform = vector(o['transform'], 16);
        if (transform[3] != 0 ||
            transform[7] != 0 ||
            transform[11] != 0 ||
            transform[15] != 1) {
          throw const FormatException('Invalid affine transform');
        }
        objects.add(SceneObject(id, name, mesh,
            transform: Float64List.fromList(transform))
          ..visible = o['visible'] as bool
          ..isTarget = o['target'] as bool
          ..pivot = o['pivot'] == null
              ? null
              : Pivot(
                  position: vector(o['pivot']['position'], 3),
                  normal: vector(o['pivot']['normal'], 3)));
      }
      final c = m['camera'];
      final v = vector(
          [c['yaw'], c['pitch'], c['distance'], c['fov'], c['near'], c['far']],
          6);
      if (v[2] <= 0 || v[3] <= 0 || v[3] >= 180 || v[4] <= 0 || v[5] <= v[4]) {
        throw const FormatException('Invalid camera');
      }
      final selected = m['selectedId'] as int?;
      if (selected != null && !ids.contains(selected)) {
        throw const FormatException('Missing selected object');
      }
      return ProjectData(objects,
          sourceAttachments: sources,
          selectedId: selected,
          camera: Camera(
              yaw: v[0],
              pitch: v[1],
              distance: v[2],
              fovDegrees: v[3],
              near: v[4],
              far: v[5],
              target: vector(c['target'], 3)));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Malformed project');
    }
  }
}
