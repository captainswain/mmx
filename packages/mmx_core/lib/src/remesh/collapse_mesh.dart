import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';

/// Mutable triangle soup used for topology-safe edge collapses. Every collapse
/// is validated against the live adjacency (duplicate faces, >2-face edges and
/// new boundary edges) before it is applied, so a pass cannot leave the mesh
/// non-manifold.
class CollapseMesh {
  final int n;
  final Float32List positions;
  final List<List<int>> faces;
  final List<bool> faceAlive;
  final List<Set<int>> vertexFaces;
  final Map<int, int> edgeCount;
  final Map<int, int> faceKeyCount;
  final Map<int, int> boundaryDegree;
  int boundaryEdges = 0;

  CollapseMesh(TriMesh mesh)
      : n = mesh.vertexCount,
        positions = Float32List.fromList(mesh.positions),
        faces = <List<int>>[],
        faceAlive = <bool>[],
        vertexFaces = List<Set<int>>.generate(mesh.vertexCount, (_) => <int>{}),
        edgeCount = <int, int>{},
        faceKeyCount = <int, int>{},
        boundaryDegree = <int, int>{} {
    for (var f = 0; f < mesh.faceCount; f++) {
      final ids = <int>[
        mesh.indices[f * 3],
        mesh.indices[f * 3 + 1],
        mesh.indices[f * 3 + 2],
      ];
      _addFace(ids);
    }
  }

  int _edgeKey(int a, int b) => (a < b ? a : b) * n + (a < b ? b : a);

  int _faceKey(List<int> ids) {
    final sorted = <int>[...ids]..sort();
    return (sorted[0] * n + sorted[1]) * n + sorted[2];
  }

  bool isBoundaryVertex(int v) => (boundaryDegree[v] ?? 0) > 0;

  bool hasEdge(int a, int b) => (edgeCount[_edgeKey(a, b)] ?? 0) > 0;

  void _changeEdge(int a, int b, int delta) {
    final key = _edgeKey(a, b);
    final old = edgeCount[key] ?? 0;
    final next = old + delta;
    if (next <= 0) {
      edgeCount.remove(key);
    } else {
      edgeCount[key] = next;
    }
    if (old == 1 && next != 1) {
      boundaryEdges--;
      _changeBoundaryDegree(a, -1);
      _changeBoundaryDegree(b, -1);
    } else if (old != 1 && next == 1) {
      boundaryEdges++;
      _changeBoundaryDegree(a, 1);
      _changeBoundaryDegree(b, 1);
    }
  }

  void _changeBoundaryDegree(int v, int delta) {
    final next = (boundaryDegree[v] ?? 0) + delta;
    if (next <= 0) {
      boundaryDegree.remove(v);
    } else {
      boundaryDegree[v] = next;
    }
  }

  void _addFace(List<int> ids) {
    final f = faces.length;
    faces.add(ids);
    faceAlive.add(true);
    final key = _faceKey(ids);
    faceKeyCount[key] = (faceKeyCount[key] ?? 0) + 1;
    for (var k = 0; k < 3; k++) {
      final a = ids[k], b = ids[(k + 1) % 3];
      vertexFaces[a].add(f);
      _changeEdge(a, b, 1);
    }
  }

  void _removeFace(int f) {
    if (!faceAlive[f]) return;
    final ids = faces[f];
    faceAlive[f] = false;
    final key = _faceKey(ids);
    final count = (faceKeyCount[key] ?? 0) - 1;
    if (count <= 0) {
      faceKeyCount.remove(key);
    } else {
      faceKeyCount[key] = count;
    }
    for (var k = 0; k < 3; k++) {
      final a = ids[k], b = ids[(k + 1) % 3];
      vertexFaces[a].remove(f);
      _changeEdge(a, b, -1);
    }
  }

  List<double> _normal(List<int> ids) {
    final a = ids[0], b = ids[1], c = ids[2];
    final ax = positions[a * 3];
    final ay = positions[a * 3 + 1];
    final az = positions[a * 3 + 2];
    final bx = positions[b * 3];
    final by = positions[b * 3 + 1];
    final bz = positions[b * 3 + 2];
    final cx = positions[c * 3];
    final cy = positions[c * 3 + 1];
    final cz = positions[c * 3 + 2];
    final ux = bx - ax, uy = by - ay, uz = bz - az;
    final wx = cx - ax, wy = cy - ay, wz = cz - az;
    return <double>[
      uy * wz - uz * wy,
      uz * wx - ux * wz,
      ux * wy - uy * wx,
    ];
  }

  static double _dot(List<double> a, List<double> b) =>
      a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

  /// Attempts to collapse b into a, moving a to the supplied position.
  /// Returns false when the collapse would break manifoldness or add a hole.
  bool tryCollapse(
    int a,
    int b,
    double mx,
    double my,
    double mz, {
    bool preserveBoundary = true,
    Set<int> sharp = const <int>{},
    int maxValence = 12,
  }) {
    if (!hasEdge(a, b)) return false;
    if (sharp.contains(a) && sharp.contains(b)) return false;
    if (preserveBoundary) {
      final aB = isBoundaryVertex(a), bB = isBoundaryVertex(b);
      if (aB != bB) return false;
      if (aB && bB) {
        // A boundary-boundary collapse is only legal along the boundary edge.
        if ((edgeCount[_edgeKey(a, b)] ?? 0) != 1) return false;
      }
    }

    final na = <int>{};
    final nb = <int>{};
    for (final f in vertexFaces[a]) {
      for (final v in faces[f]) {
        if (v != a) na.add(v);
      }
    }
    for (final f in vertexFaces[b]) {
      for (final v in faces[f]) {
        if (v != b) nb.add(v);
      }
    }
    final common = na.intersection(nb);
    if (common.length > 2) return false;
    final valence = na.length + nb.length - 2 * common.length;
    if (valence < 3 || valence > maxValence) return false;

    final affected = <int>{
      ...vertexFaces[a],
      ...vertexFaces[b],
    };
    final removed = <int>{};
    final additions = <List<int>>[];
    final removedKeys = <int, int>{};
    final newKeys = <int, int>{};

    for (final f in affected) {
      final ids = faces[f];
      final hasA = ids.contains(a);
      final hasB = ids.contains(b);
      // Every affected face is removed and re-added with the collapsed
      // vertex mapped to a, so its old face key is no longer present.
      removed.add(f);
      final oldKey = _faceKey(ids);
      removedKeys[oldKey] = (removedKeys[oldKey] ?? 0) + 1;
      if (hasA && hasB) continue;
      final mapped = <int>[
        ids[0] == b ? a : ids[0],
        ids[1] == b ? a : ids[1],
        ids[2] == b ? a : ids[2],
      ];
      if (mapped[0] == mapped[1] ||
          mapped[1] == mapped[2] ||
          mapped[0] == mapped[2]) {
        continue;
      }
      final key = _faceKey(mapped);
      final existing = (faceKeyCount[key] ?? 0) - (removedKeys[key] ?? 0);
      if (existing + (newKeys[key] ?? 0) > 0) return false;
      newKeys[key] = (newKeys[key] ?? 0) + 1;
      additions.add(mapped);
    }

    // Orientation of the surviving faces must not flip.
    for (final f in affected) {
      final ids = faces[f];
      if (ids.contains(a) && ids.contains(b)) continue;
      final before = _normal(ids);
      final mapped = <int>[
        ids[0] == b ? a : ids[0],
        ids[1] == b ? a : ids[1],
        ids[2] == b ? a : ids[2],
      ];
      // Evaluate with a at the merged position.
      final p = <List<double>>[];
      for (final v in mapped) {
        if (v == a) {
          p.add(<double>[mx, my, mz]);
        } else {
          p.add(<double>[
            positions[v * 3],
            positions[v * 3 + 1],
            positions[v * 3 + 2]
          ]);
        }
      }
      final ux = p[1][0] - p[0][0],
          uy = p[1][1] - p[0][1],
          uz = p[1][2] - p[0][2];
      final wx = p[2][0] - p[0][0],
          wy = p[2][1] - p[0][1],
          wz = p[2][2] - p[0][2];
      final after = <double>[
        uy * wz - uz * wy,
        uz * wx - ux * wz,
        ux * wy - uy * wx,
      ];
      final lb = math.sqrt(_dot(before, before));
      final la = math.sqrt(_dot(after, after));
      if (lb < 1e-20 || la < 1e-20) return false;
      if (_dot(before, after) / (lb * la) <= 0.2) return false;
    }

    // Edge/boundary delta check.
    final delta = <int, int>{};
    void bump(List<int> ids, int amount) {
      for (var k = 0; k < 3; k++) {
        final x = ids[k], y = ids[(k + 1) % 3];
        final key = _edgeKey(x, y);
        delta[key] = (delta[key] ?? 0) + amount;
      }
    }

    for (final f in removed) {
      bump(faces[f], -1);
    }
    for (final ids in additions) {
      bump(ids, 1);
    }
    var boundary = boundaryEdges;
    for (final entry in delta.entries) {
      final old = edgeCount[entry.key] ?? 0;
      final next = old + entry.value;
      if (next > 2 || next < 0) return false;
      if (old == 1 && next != 1) boundary--;
      if (old != 1 && next == 1) boundary++;
    }
    if (boundary > boundaryEdges) return false;

    // Commit.
    for (final f in removed) {
      _removeFace(f);
    }
    for (final ids in additions) {
      _addFace(ids);
    }
    positions[a * 3] = mx;
    positions[a * 3 + 1] = my;
    positions[a * 3 + 2] = mz;
    return true;
  }

  TriMesh build() {
    final builder = MeshBuilder();
    final map = List<int>.filled(n, -1);
    for (var v = 0; v < n; v++) {
      if (vertexFaces[v].isEmpty) continue;
      map[v] = builder.addVertex(
          positions[v * 3], positions[v * 3 + 1], positions[v * 3 + 2]);
    }
    for (var f = 0; f < faces.length; f++) {
      if (!faceAlive[f]) continue;
      final ids = faces[f];
      final a = map[ids[0]], b = map[ids[1]], c = map[ids[2]];
      if (a < 0 || b < 0 || c < 0) continue;
      if (a == b || b == c || a == c) continue;
      builder.addTriangle(a, b, c);
    }
    return builder.build();
  }
}
