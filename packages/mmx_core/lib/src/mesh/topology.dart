import 'dart:collection';
import 'dart:typed_data';

import 'tri_mesh.dart';

/// Structural queries over a triangle mesh: vertex adjacency, edge-to-face
/// incidence, boundary loops, connected components, and manifold checks.
///
/// Everything is CSR (compressed sparse row) so traversal is cache friendly.
class MeshTopology {
  final TriMesh mesh;

  late final Uint32List vFaceStart;
  late final Uint32List vFaces;
  late final Uint32List vVertStart;
  late final Uint32List vVerts;

  /// Edge key (min(v)*V + max(v)) -> incident face ids.
  final HashMap<int, List<int>> edgeFaces = HashMap<int, List<int>>();

  MeshTopology(this.mesh) {
    _buildVertexFaces();
    _buildVertexVerts();
    _buildEdges();
  }

  int get vertexCount => mesh.vertexCount;

  int edgeKey(int a, int b) {
    final n = vertexCount;
    return a < b ? a * n + b : b * n + a;
  }

  void _buildVertexFaces() {
    final vc = mesh.vertexCount;
    final counts = Uint32List(vc + 1);
    for (var i = 0; i < mesh.indices.length; i++) {
      counts[mesh.indices[i] + 1]++;
    }
    for (var i = 0; i < vc; i++) {
      counts[i + 1] += counts[i];
    }
    final faces = Uint32List(mesh.indices.length);
    final cursor = Uint32List.fromList(counts);
    for (var f = 0; f < mesh.faceCount; f++) {
      for (var k = 0; k < 3; k++) {
        final v = mesh.indices[f * 3 + k];
        faces[cursor[v]++] = f;
      }
    }
    vFaceStart = counts;
    vFaces = faces;
  }

  void _buildVertexVerts() {
    final vc = mesh.vertexCount;
    final seen = <int>{};
    final lists = List<List<int>>.generate(vc, (_) => <int>[]);
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = mesh.indices[f * 3],
          b = mesh.indices[f * 3 + 1],
          c = mesh.indices[f * 3 + 2];
      void link(int x, int y) {
        final k = x * vc + y;
        if (seen.add(k)) lists[x].add(y);
      }

      link(a, b);
      link(b, a);
      link(b, c);
      link(c, b);
      link(c, a);
      link(a, c);
    }
    final start = Uint32List(vc + 1);
    var total = 0;
    for (var i = 0; i < vc; i++) {
      start[i] = total;
      total += lists[i].length;
    }
    start[vc] = total;
    final flat = Uint32List(total);
    var w = 0;
    for (var i = 0; i < vc; i++) {
      for (final v in lists[i]) {
        flat[w++] = v;
      }
    }
    vVertStart = start;
    vVerts = flat;
  }

  void _buildEdges() {
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = mesh.indices[f * 3],
          b = mesh.indices[f * 3 + 1],
          c = mesh.indices[f * 3 + 2];
      for (final e in <List<int>>[
        <int>[a, b],
        <int>[b, c],
        <int>[c, a],
      ]) {
        final k = edgeKey(e[0], e[1]);
        (edgeFaces[k] ??= <int>[]).add(f);
      }
    }
  }

  List<int> facesOfVertex(int v) =>
      vFaces.sublist(vFaceStart[v], vFaceStart[v + 1]);

  List<int> neighborsOfVertex(int v) =>
      vVerts.sublist(vVertStart[v], vVertStart[v + 1]);

  int valence(int v) => vVertStart[v + 1] - vVertStart[v];

  /// Boundary edges (exactly one incident face).
  List<List<int>> boundaryEdges() {
    final out = <List<int>>[];
    final n = vertexCount;
    for (final entry in edgeFaces.entries) {
      if (entry.value.length == 1) {
        final a = entry.key ~/ n, b = entry.key % n;
        out.add(<int>[a, b]);
      }
    }
    return out;
  }

  /// Traces boundary edges into ordered loops of vertex ids.
  List<List<int>> boundaryLoops() {
    final n = vertexCount;
    final next = HashMap<int, List<int>>();
    for (final entry in edgeFaces.entries) {
      if (entry.value.length != 1) continue;
      final a = entry.key ~/ n, b = entry.key % n;
      (next[a] ??= <int>[]).add(b);
      (next[b] ??= <int>[]).add(a);
    }
    final used = <int>{};
    final loops = <List<int>>[];
    for (final start in next.keys) {
      if (used.contains(start)) continue;
      final loop = <int>[start];
      used.add(start);
      var cur = start;
      var guard = 0;
      while (guard++ < n) {
        final cands = next[cur] ?? const <int>[];
        int? nxt;
        for (final c in cands) {
          if (!used.contains(c)) {
            nxt = c;
            break;
          }
        }
        if (nxt == null) break;
        loop.add(nxt);
        used.add(nxt);
        cur = nxt;
        if (cur == start) break;
      }
      if (loop.length >= 3) loops.add(loop);
    }
    return loops;
  }

  /// Connected components over the face-vertex graph. Returns per-face
  /// component ids and the number of components.
  (Uint32List, int) components() {
    final vc = vertexCount;
    final parent = Int32List(vc);
    for (var i = 0; i < vc; i++) {
      parent[i] = i;
    }
    int find(int x) {
      var r = x;
      while (parent[r] != r) {
        r = parent[r];
      }
      var c = x;
      while (parent[c] != r) {
        final nxt = parent[c];
        parent[c] = r;
        c = nxt;
      }
      return r;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    for (var f = 0; f < mesh.faceCount; f++) {
      final a = mesh.indices[f * 3],
          b = mesh.indices[f * 3 + 1],
          c = mesh.indices[f * 3 + 2];
      union(a, b);
      union(b, c);
    }
    final rootToId = HashMap<int, int>();
    final faceComp = Uint32List(mesh.faceCount);
    var comps = 0;
    for (var f = 0; f < mesh.faceCount; f++) {
      final r = find(mesh.indices[f * 3]);
      final id = rootToId.putIfAbsent(r, () => comps++);
      faceComp[f] = id;
    }
    return (faceComp, comps);
  }

  /// Edges shared by more than two faces.
  List<List<int>> nonManifoldEdges() {
    final out = <List<int>>[];
    final n = vertexCount;
    for (final e in edgeFaces.entries) {
      if (e.value.length > 2) {
        out.add(<int>[e.key ~/ n, e.key % n, e.value.length]);
      }
    }
    return out;
  }

  /// Vertices whose incident faces form more than one fan (bowtie vertices).
  List<int> nonManifoldVertices() {
    final out = <int>[];
    for (var v = 0; v < vertexCount; v++) {
      final faces = vFaces.sublist(vFaceStart[v], vFaceStart[v + 1]);
      if (faces.length < 2) continue;
      // Build a graph over incident faces linked by shared edges containing v.
      final adj = <int, Set<int>>{};
      for (final f in faces) {
        adj[f] = <int>{};
      }
      for (final f in faces) {
        for (var k = 0; k < 3; k++) {
          final a = mesh.indices[f * 3 + k];
          final b = mesh.indices[f * 3 + (k + 1) % 3];
          if (a != v && b != v) continue;
          final other = a == v ? b : a;
          final kk = edgeKey(v, other);
          final inc = edgeFaces[kk];
          if (inc == null) continue;
          for (final g in inc) {
            if (g != f && adj.containsKey(g)) {
              adj[f]!.add(g);
              adj[g]!.add(f);
            }
          }
        }
      }
      // Count connected components of the fan graph.
      final seen = <int>{};
      var fans = 0;
      for (final f in faces) {
        if (seen.contains(f)) continue;
        fans++;
        final q = Queue<int>()..add(f);
        seen.add(f);
        while (q.isNotEmpty) {
          final cur = q.removeFirst();
          for (final nb in adj[cur]!) {
            if (seen.add(nb)) q.add(nb);
          }
        }
      }
      if (fans > 1) out.add(v);
    }
    return out;
  }

  /// Average vertex valence, useful for remesh diagnostics.
  double averageValence() {
    var s = 0;
    for (var v = 0; v < vertexCount; v++) {
      s += valence(v);
    }
    return vertexCount == 0 ? 0 : s / vertexCount;
  }
}
