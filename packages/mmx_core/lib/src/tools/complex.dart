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
    return [
      for (var c = 0; c < count; c++)
        mesh.extractFaces([
          for (var f = 0; f < mesh.faceCount; f++)
            if (ids[f] == c) f,
        ])
    ];
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
    return mesh.extractFaces(faces.where((f) => f >= 0 && f < mesh.faceCount));
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

  /// Generates a complex by joining the supplied parts (Generate Complex).
  static TriMesh generate(List<TriMesh> parts) => join(parts);
}
