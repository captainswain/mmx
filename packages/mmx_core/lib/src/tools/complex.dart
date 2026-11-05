import 'dart:typed_data';

import '../mesh/topology.dart';
import '../mesh/tri_mesh.dart';
import '../solid/solidifier.dart';
import 'modify.dart';

/// Complex/shell operations from Meshmixer's Edit panel: splitting a scene
/// object into its connected shells, filtering shells, and joining them again.
class ComplexTools {
  /// Splits [mesh] into one mesh per connected component, preserving the
  /// face-group assignment of each component.
  static List<TriMesh> split(TriMesh mesh) {
    final (ids, count) = MeshTopology(mesh).components();
    if (count == 0) return <TriMesh>[];
    final out = <TriMesh>[];
    for (var c = 0; c < count; c++) {
      final builder = MeshBuilder();
      final vertexMap = <int, int>{};
      final groups = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (ids[f] != c) continue;
        final face = <int>[
          mesh.indices[f * 3],
          mesh.indices[f * 3 + 1],
          mesh.indices[f * 3 + 2],
        ];
        final mapped = <int>[];
        for (final v in face) {
          final existing = vertexMap[v];
          if (existing != null) {
            mapped.add(existing);
          } else {
            final id = builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v));
            vertexMap[v] = id;
            mapped.add(id);
          }
        }
        builder.addTriangle(mapped[0], mapped[1], mapped[2]);
        groups.add(mesh.faceGroups == null ? 0 : mesh.faceGroups![f]);
      }
      if (builder.faceCount == 0) continue;
      final part = builder.build();
      out.add(TriMesh(part.positions, part.indices,
          faceGroups: Uint16List.fromList(groups)));
    }
    return out;
  }

  /// Keeps the shells that match [keep] (or all shells when [keep] is null),
  /// then joins them back into one mesh.
  static TriMesh filter(
    TriMesh mesh, {
    bool Function(TriMesh shell, int index)? keep,
    int? minFaces,
    double? minVolume,
  }) {
    final parts = split(mesh);
    final selected = <TriMesh>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (minFaces != null && part.faceCount < minFaces) continue;
      if (minVolume != null && part.signedVolume().abs() < minVolume) continue;
      if (keep != null && !keep(part, i)) continue;
      selected.add(part);
    }
    if (selected.isEmpty) return TriMesh(Float32List(0), Uint32List(0));
    return Modify.combine(selected);
  }

  /// Extracts the selected faces as a new mesh (Make Part).
  static TriMesh extract(TriMesh mesh, Set<int> faces) {
    final builder = MeshBuilder();
    final vertexMap = <int, int>{};
    final groups = <int>[];
    for (final f in faces) {
      if (f < 0 || f >= mesh.faceCount) continue;
      final mapped = <int>[];
      for (var k = 0; k < 3; k++) {
        final v = mesh.indices[f * 3 + k];
        final existing = vertexMap[v];
        if (existing != null) {
          mapped.add(existing);
        } else {
          final id = builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v));
          vertexMap[v] = id;
          mapped.add(id);
        }
      }
      builder.addTriangle(mapped[0], mapped[1], mapped[2]);
      groups.add(mesh.faceGroups == null ? 0 : mesh.faceGroups![f]);
    }
    final part = builder.build();
    return TriMesh(part.positions, part.indices,
        faceGroups: Uint16List.fromList(groups));
  }

  /// Converts a selected face region into a solid part (Make Solid Part).
  static TriMesh makeSolidPart(
    TriMesh mesh,
    Set<int> faces, {
    SolidMode mode = SolidMode.accurate,
    int resolution = 128,
  }) {
    final part = extract(mesh, faces);
    if (part.faceCount == 0) return part;
    return Solidifier.makeSolid(part, mode: mode, resolution: resolution).mesh;
  }

  /// Joins shells into one mesh (the Edit panel's Join/Combine action).
  static TriMesh join(List<TriMesh> parts) => Modify.combine(parts);
}
