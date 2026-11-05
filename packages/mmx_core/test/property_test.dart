import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_core/src/remesh/collapse_mesh.dart';
import 'package:test/test.dart';

TriMesh cube() => TriMesh(
      Float32List.fromList(<double>[
        -1,
        -1,
        -1,
        1,
        -1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        -1,
        -1,
        -1,
        1,
        1,
        -1,
        1,
        1,
        1,
        1,
        -1,
        1,
        1,
      ]),
      Uint32List.fromList(<int>[
        0,
        2,
        1,
        0,
        3,
        2,
        4,
        5,
        6,
        4,
        6,
        7,
        0,
        1,
        5,
        0,
        5,
        4,
        1,
        2,
        6,
        1,
        6,
        5,
        2,
        3,
        7,
        2,
        7,
        6,
        3,
        0,
        4,
        3,
        4,
        7,
      ]),
    );

void main() {
  test('randomly perturbed closed cubes remesh manifold', () {
    final rng = math.Random(42);
    for (var i = 0; i < 8; i++) {
      final mesh = cube();
      for (var v = 0; v < mesh.vertexCount; v++) {
        mesh.positions[v * 3] += (rng.nextDouble() - 0.5) * 0.2;
        mesh.positions[v * 3 + 1] += (rng.nextDouble() - 0.5) * 0.2;
        mesh.positions[v * 3 + 2] += (rng.nextDouble() - 0.5) * 0.2;
      }
      final out = IsotropicRemesher.remesh(
        mesh,
        targetEdgeLength: 0.5,
        iterations: 2,
        preserveSharp: true,
      );
      expect(out.faceCount, greaterThan(0));
      expect(out.validate(), isEmpty);
      expect(MeshTopology(out).boundaryLoops(), isEmpty);
      expect(MeshTopology(out).nonManifoldEdges(), isEmpty);
      expect(MeshTopology(out).components().$2, 1);
    }
  });

  test('random collapse sequences never create non-manifold output', () {
    final rng = math.Random(7);
    for (var round = 0; round < 8; round++) {
      final mesh = cube();
      final state = CollapseMesh(mesh);
      final n = mesh.vertexCount;
      final keys = state.edgeCount.keys.toList();
      for (var step = 0; step < 6; step++) {
        final key = keys[rng.nextInt(keys.length)];
        final a = key ~/ n, b = key % n;
        state.tryCollapse(
          a,
          b,
          (mesh.vx(a) + mesh.vx(b)) * 0.5,
          (mesh.vy(a) + mesh.vy(b)) * 0.5,
          (mesh.vz(a) + mesh.vz(b)) * 0.5,
        );
      }
      final out = state.build();
      if (out.faceCount > 0) {
        expect(out.validate(), isEmpty);
        expect(MeshTopology(out).nonManifoldEdges(), isEmpty);
      }
    }
  });
}
