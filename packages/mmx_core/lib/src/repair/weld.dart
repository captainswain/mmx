import 'dart:typed_data';

import '../mesh/topology.dart';
import '../mesh/tri_mesh.dart';

/// Vertex welding and crack closing.
///
/// The shipped Meshmixer binary exposes both "Weld Cracks" and implicit
/// welding during import; this module implements the same idea with a
/// quantized spatial hash (O(n) instead of O(n^2)).
class Weld {
  /// Welds all vertices closer than [tolerance], then drops degenerate faces.
  static TriMesh weldVertices(TriMesh mesh, {double tolerance = 1e-6}) {
    if (mesh.vertexCount == 0) return mesh;
    final inv = tolerance <= 0 ? 1e9 : 1.0 / tolerance;
    final map = <int, int>{};
    final remap = Uint32List(mesh.vertexCount);
    final builder = MeshBuilder();
    for (var i = 0; i < mesh.vertexCount; i++) {
      final x = mesh.vx(i), y = mesh.vy(i), z = mesh.vz(i);
      final qx = (x * inv).round(),
          qy = (y * inv).round(),
          qz = (z * inv).round();
      // Quantized key; collisions within one cell are welded, which is the
      // intended behaviour for a tolerance-based weld.
      final key =
          ((qx & 0x1FFFFF) << 42) | ((qy & 0x1FFFFF) << 21) | (qz & 0x1FFFFF);
      final existing = map[key];
      if (existing != null) {
        remap[i] = existing;
      } else {
        final id = builder.addVertex(x, y, z);
        map[key] = id;
        remap[i] = id;
      }
    }
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = remap[mesh.indices[f * 3]];
      final b = remap[mesh.indices[f * 3 + 1]];
      final c = remap[mesh.indices[f * 3 + 2]];
      if (a == b || b == c || a == c) continue;
      builder.addTriangle(a, b, c);
    }
    final out = builder.build();
    out.removeDegenerateFaces();
    return out;
  }

  /// Merges boundary-loop vertices that lie within [tolerance] of each other,
  /// which closes hairline cracks without touching interior geometry.
  static TriMesh weldCracks(TriMesh mesh, {double tolerance = 1e-5}) {
    final topo = MeshTopology(mesh);
    final boundary = <int>{};
    for (final e in topo.boundaryEdges()) {
      boundary.add(e[0]);
      boundary.add(e[1]);
    }
    if (boundary.isEmpty) return mesh;
    final inv = 1.0 / tolerance;
    final map = <int, int>{};
    final remap = Uint32List(mesh.vertexCount);
    for (var i = 0; i < mesh.vertexCount; i++) {
      remap[i] = i;
    }
    for (final v in boundary) {
      final x = mesh.vx(v), y = mesh.vy(v), z = mesh.vz(v);
      final key = (((x * inv).round() & 0x1FFFFF) << 42) |
          (((y * inv).round() & 0x1FFFFF) << 21) |
          ((z * inv).round() & 0x1FFFFF);
      final existing = map[key];
      if (existing != null) {
        remap[v] = existing;
      } else {
        map[key] = v;
      }
    }
    final builder = MeshBuilder();
    final vmap = <int, int>{};
    for (var i = 0; i < mesh.vertexCount; i++) {
      vmap[i] = builder.addVertex(mesh.vx(i), mesh.vy(i), mesh.vz(i));
    }
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = vmap[remap[mesh.indices[f * 3]]]!;
      final b = vmap[remap[mesh.indices[f * 3 + 1]]]!;
      final c = vmap[remap[mesh.indices[f * 3 + 2]]]!;
      if (a == b || b == c || a == c) continue;
      builder.addTriangle(a, b, c);
    }
    final out = builder.build();
    out.removeDegenerateFaces();
    out.compact();
    return out;
  }

  /// Removes faces that duplicate an existing face (same vertex set).
  static int removeDuplicateFaces(TriMesh mesh) {
    final seen = <String>{};
    final keep = <int>[];
    for (var f = 0; f < mesh.faceCount; f++) {
      final ids = <int>[
        mesh.indices[f * 3],
        mesh.indices[f * 3 + 1],
        mesh.indices[f * 3 + 2],
      ]..sort();
      final key = '${ids[0]}_${ids[1]}_${ids[2]}';
      if (seen.add(key)) {
        keep.addAll(<int>[
          mesh.indices[f * 3],
          mesh.indices[f * 3 + 1],
          mesh.indices[f * 3 + 2]
        ]);
      }
    }
    final removed = mesh.faceCount - keep.length ~/ 3;
    if (removed > 0) mesh.indices = Uint32List.fromList(keep);
    return removed;
  }
}
