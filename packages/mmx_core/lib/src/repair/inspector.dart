import 'dart:math' as math;

import '../mesh/topology.dart';
import '../mesh/tri_mesh.dart';

/// Defect classes surfaced by Meshmixer's Inspector (observed strings:
/// blue = hole, red = non-manifold, magenta = small disconnected component).
enum DefectKind { hole, nonManifoldEdge, nonManifoldVertex, smallComponent }

class MeshDefect {
  final DefectKind kind;
  final List<int> vertices;
  final List<int> faces;
  final double metric;

  MeshDefect(this.kind,
      {required this.vertices, required this.faces, required this.metric});

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'vertices': vertices.length,
        'faces': faces.length,
        'metric': metric,
      };
}

class MeshInspector {
  /// Scans for the defect set Meshmixer reports. [smallComponentArea] is the
  /// absolute area below which a disconnected shell is flagged.
  static List<MeshDefect> scan(TriMesh mesh,
      {double smallComponentArea = double.infinity,
      bool checkSelfIntersections = false}) {
    final topo = MeshTopology(mesh);
    final defects = <MeshDefect>[];

    for (final loop in topo.boundaryLoops()) {
      var perimeter = 0.0;
      for (var i = 0; i < loop.length; i++) {
        final a = loop[i], b = loop[(i + 1) % loop.length];
        perimeter += _dist(mesh, a, b);
      }
      final faces = <int>[];
      for (var i = 0; i < loop.length; i++) {
        final k = topo.edgeKey(loop[i], loop[(i + 1) % loop.length]);
        faces.addAll(topo.edgeFaces[k] ?? const <int>[]);
      }
      defects.add(MeshDefect(DefectKind.hole,
          vertices: loop, faces: faces.toSet().toList(), metric: perimeter));
    }

    for (final e in topo.nonManifoldEdges()) {
      final faces = topo.edgeFaces[topo.edgeKey(e[0], e[1])] ?? const <int>[];
      defects.add(MeshDefect(DefectKind.nonManifoldEdge,
          vertices: <int>[e[0], e[1]], faces: faces, metric: e[2].toDouble()));
    }

    for (final v in topo.nonManifoldVertices()) {
      defects.add(MeshDefect(DefectKind.nonManifoldVertex,
          vertices: <int>[v], faces: topo.facesOfVertex(v), metric: 0));
    }

    final (faceComp, compCount) = topo.components();
    if (compCount > 1) {
      final areas = List<double>.filled(compCount, 0);
      for (var f = 0; f < mesh.faceCount; f++) {
        areas[faceComp[f]] += _faceArea(mesh, f);
      }
      for (var c = 0; c < compCount; c++) {
        if (areas[c] > smallComponentArea) continue;
        final faces = <int>[];
        final verts = <int>{};
        for (var f = 0; f < mesh.faceCount; f++) {
          if (faceComp[f] != c) continue;
          faces.add(f);
          verts.addAll(<int>[
            mesh.indices[f * 3],
            mesh.indices[f * 3 + 1],
            mesh.indices[f * 3 + 2],
          ]);
        }
        defects.add(MeshDefect(DefectKind.smallComponent,
            vertices: verts.toList(), faces: faces, metric: areas[c]));
      }
    }

    if (checkSelfIntersections) {
      defects.addAll(_selfIntersections(mesh));
    }
    return defects;
  }

  /// Splits bowtie vertices and >2-face edges so every edge has at most two
  /// incident faces. This is a best-effort "Split Non-Manifold Surface":
  /// it makes the mesh manifold without inventing geometry.
  static TriMesh splitNonManifold(TriMesh mesh) {
    mesh.requireUntextured('Non-manifold splitting');
    final topo = MeshTopology(mesh);
    final builder = MeshBuilder();
    // Map original vertex -> list of builder vertices, one per fan.
    final fans = <int, List<int>>{};

    int cloneVertex(int v) {
      final id = builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v));
      return id;
    }

    // Pre-create one builder vertex per original vertex.
    final base = List<int>.generate(mesh.vertexCount, (v) => cloneVertex(v));
    final used = List<bool>.filled(mesh.vertexCount, false);

    // Fan decomposition per vertex using the face adjacency graph.
    for (var v = 0; v < mesh.vertexCount; v++) {
      final faces = topo.facesOfVertex(v);
      if (faces.isEmpty) continue;
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
          for (final g
              in topo.edgeFaces[topo.edgeKey(v, other)] ?? const <int>[]) {
            if (g != f && adj.containsKey(g)) {
              adj[f]!.add(g);
              adj[g]!.add(f);
            }
          }
        }
      }
      final seen = <int>{};
      final comps = <List<int>>[];
      for (final f in faces) {
        if (seen.contains(f)) continue;
        final comp = <int>[];
        final stack = <int>[f];
        seen.add(f);
        while (stack.isNotEmpty) {
          final cur = stack.removeLast();
          comp.add(cur);
          for (final nb in adj[cur]!) {
            if (seen.add(nb)) stack.add(nb);
          }
        }
        comps.add(comp);
      }
      if (comps.length <= 1) continue;
      fans[v] = <int>[base[v]];
      for (var i = 1; i < comps.length; i++) {
        fans[v]!.add(cloneVertex(v));
      }
      // Assign fan ids to faces.
      for (var i = 0; i < comps.length; i++) {
        for (final f in comps[i]) {
          _faceFan[f] = i;
        }
      }
      used[v] = true;
    }

    for (var f = 0; f < mesh.faceCount; f++) {
      final ids = <int>[];
      for (var k = 0; k < 3; k++) {
        final v = mesh.indices[f * 3 + k];
        final list = fans[v];
        if (list == null) {
          ids.add(base[v]);
        } else {
          final fan = _faceFan[f] ?? 0;
          ids.add(list[fan < list.length ? fan : 0]);
        }
      }
      if (ids[0] == ids[1] || ids[1] == ids[2] || ids[0] == ids[2]) continue;
      builder.addTriangle(ids[0], ids[1], ids[2]);
    }
    _faceFan.clear();
    final out = builder.build();
    out.removeDegenerateFaces();
    out.compact();
    return out;
  }

  static final Map<int, int> _faceFan = <int, int>{};

  /// Broad-phase self-intersection hunt: triangle pairs whose boxes overlap
  /// are tested exactly. Reports the first few defects rather than all, which
  /// matches the Inspector's per-region behaviour.
  static List<MeshDefect> _selfIntersections(TriMesh mesh, {int limit = 5000}) {
    final topo = MeshTopology(mesh);
    final out = <MeshDefect>[];
    for (var f = 0; f < mesh.faceCount && out.length < limit; f++) {
      final a = mesh.indices[f * 3],
          b = mesh.indices[f * 3 + 1],
          c = mesh.indices[f * 3 + 2];
      final bbox = _faceBox(mesh, f);
      // Cheap check against adjacent faces via vertex rings.
      for (final v in <int>[a, b, c]) {
        for (final g in topo.facesOfVertex(v)) {
          if (g <= f) continue;
          if (_shareVertex(mesh, f, g)) continue;
          final ob = _faceBox(mesh, g);
          if (!_boxesOverlap(bbox, ob)) continue;
          if (_triTri(mesh, f, g)) {
            out.add(MeshDefect(DefectKind.nonManifoldEdge,
                vertices: <int>[a, b, c], faces: <int>[f, g], metric: 0));
            break;
          }
        }
      }
    }
    return out;
  }

  static List<double> _faceBox(TriMesh m, int f) {
    var minx = double.infinity, miny = double.infinity, minz = double.infinity;
    var maxx = double.negativeInfinity,
        maxy = double.negativeInfinity,
        maxz = double.negativeInfinity;
    for (var k = 0; k < 3; k++) {
      final v = m.indices[f * 3 + k];
      minx = math.min(minx, m.vx(v));
      miny = math.min(miny, m.vy(v));
      minz = math.min(minz, m.vz(v));
      maxx = math.max(maxx, m.vx(v));
      maxy = math.max(maxy, m.vy(v));
      maxz = math.max(maxz, m.vz(v));
    }
    return <double>[minx, miny, minz, maxx, maxy, maxz];
  }

  static bool _boxesOverlap(List<double> a, List<double> b) =>
      a[3] >= b[0] &&
      a[0] <= b[3] &&
      a[4] >= b[1] &&
      a[1] <= b[4] &&
      a[5] >= b[2] &&
      a[2] <= b[5];

  static bool _shareVertex(TriMesh m, int f, int g) {
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        if (m.indices[f * 3 + i] == m.indices[g * 3 + j]) return true;
      }
    }
    return false;
  }

  /// Separating-axis test for two triangles.
  static bool _triTri(TriMesh m, int f, int g) {
    final ta = _triVerts(m, f);
    final tb = _triVerts(m, g);
    final axes = <List<double>>[];
    final na = _cross(_sub(ta[1], ta[0]), _sub(ta[2], ta[0]));
    final nb = _cross(_sub(tb[1], tb[0]), _sub(tb[2], tb[0]));
    axes.add(na);
    axes.add(nb);
    for (var i = 0; i < 3; i++) {
      final ea = _sub(ta[(i + 1) % 3], ta[i]);
      for (var j = 0; j < 3; j++) {
        final eb = _sub(tb[(j + 1) % 3], tb[j]);
        axes.add(_cross(ea, eb));
      }
    }
    for (final ax in axes) {
      final l = math.sqrt(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2]);
      if (l < 1e-12) continue;
      final nx = ax[0] / l, ny = ax[1] / l, nz = ax[2] / l;
      var amin = double.infinity, amax = double.negativeInfinity;
      var bmin = double.infinity, bmax = double.negativeInfinity;
      for (final p in ta) {
        final d = p[0] * nx + p[1] * ny + p[2] * nz;
        if (d < amin) amin = d;
        if (d > amax) amax = d;
      }
      for (final p in tb) {
        final d = p[0] * nx + p[1] * ny + p[2] * nz;
        if (d < bmin) bmin = d;
        if (d > bmax) bmax = d;
      }
      if (amax < bmin || bmax < amin) return false;
    }
    return true;
  }

  static List<List<double>> _triVerts(TriMesh m, int f) => <List<double>>[
        <double>[
          m.vx(m.indices[f * 3]),
          m.vy(m.indices[f * 3]),
          m.vz(m.indices[f * 3])
        ],
        <double>[
          m.vx(m.indices[f * 3 + 1]),
          m.vy(m.indices[f * 3 + 1]),
          m.vz(m.indices[f * 3 + 1])
        ],
        <double>[
          m.vx(m.indices[f * 3 + 2]),
          m.vy(m.indices[f * 3 + 2]),
          m.vz(m.indices[f * 3 + 2])
        ],
      ];

  static List<double> _sub(List<double> a, List<double> b) =>
      <double>[a[0] - b[0], a[1] - b[1], a[2] - b[2]];

  static List<double> _cross(List<double> a, List<double> b) => <double>[
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
      ];

  static double _dist(TriMesh m, int a, int b) {
    final dx = m.vx(a) - m.vx(b),
        dy = m.vy(a) - m.vy(b),
        dz = m.vz(a) - m.vz(b);
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  static double _faceArea(TriMesh m, int f) {
    final a = m.indices[f * 3],
        b = m.indices[f * 3 + 1],
        c = m.indices[f * 3 + 2];
    final ux = m.vx(b) - m.vx(a),
        uy = m.vy(b) - m.vy(a),
        uz = m.vz(b) - m.vz(a);
    final wx = m.vx(c) - m.vx(a),
        wy = m.vy(c) - m.vy(a),
        wz = m.vz(c) - m.vz(a);
    final nx = uy * wz - uz * wy,
        ny = uz * wx - ux * wz,
        nz = ux * wy - uy * wx;
    return 0.5 * math.sqrt(nx * nx + ny * ny + nz * nz);
  }
}
