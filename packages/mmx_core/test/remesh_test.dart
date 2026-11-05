import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_core/src/remesh/collapse_mesh.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('decimation', () {
    test('reduces to a face budget without destroying the shape', () {
      final mesh = loadModel('dog.obj');
      final sw = Stopwatch()..start();
      final reduced = Decimator.reduce(mesh, percentage: 0.25);
      sw.stop();
      expect(reduced.faceCount, lessThan(mesh.faceCount));
      expect(reduced.faceCount, lessThanOrEqualTo((mesh.faceCount * 0.30).round()));
      expect(reduced.validate(), isEmpty);
      final volRatio = reduced.signedVolume() / mesh.signedVolume();
      final areaRatio = reduced.surfaceArea() / mesh.surfaceArea();
      print('dog reduce: ${mesh.faceCount} -> ${reduced.faceCount} faces in '
          '${sw.elapsedMilliseconds}ms, volume ratio ${volRatio.toStringAsFixed(3)}, '
          'area ratio ${areaRatio.toStringAsFixed(3)}');
      expect(volRatio, greaterThan(0.85));
      expect(volRatio, lessThan(1.15));
      expect(areaRatio, greaterThan(0.8));
    });

    test('triangle budget is respected', () {
      final mesh = loadModel('bunnyr.obj');
      final reduced = Decimator.reduce(mesh, targetFaceCount: 2000);
      print('bunny budget: ${mesh.faceCount} -> ${reduced.faceCount}');
      expect(reduced.faceCount, lessThanOrEqualTo(2000 + 50));
      expect(reduced.faceCount, greaterThan(1000));
    });

    test('uniform mode uses shortest-edge collapses', () {
      final mesh = loadModel('bunnyr.obj');
      final reduced = Decimator.reduce(mesh,
          targetFaceCount: 2000, uniform: true);
      print('bunny uniform: ${mesh.faceCount} -> ${reduced.faceCount}');
      expect(reduced.faceCount, lessThanOrEqualTo(2050));
      expect(reduced.validate(), isEmpty);
      expect(reduced.signedVolume(), greaterThan(0));
    });
    test('max deviation stops collapsing early', () {
      final mesh = loadModel('sphere.obj');
      final reduced = Decimator.reduce(mesh,
          targetFaceCount: 1000, maxDeviation: 0.01);
      expect(reduced.faceCount, greaterThan(1000));
      expect(reduced.validate(), isEmpty);
    });
  });

  group('isotropic remeshing', () {
    test('linear subdivision preserves the surface exactly', () {
      final mesh = loadModel('sphere.obj');
      final sub = IsotropicRemesher.linearSubdivide(mesh);
      expect(sub.faceCount, mesh.faceCount * 4);
      expect(sub.signedVolume(),
          closeTo(mesh.signedVolume(), mesh.signedVolume().abs() * 1e-6));
      expect(MeshTopology(sub).boundaryLoops(), isEmpty);
    });

    test('adaptive density remeshing stays watertight', () {
      final mesh = loadModel('sphere.obj');
      final target = mesh.bounds().diagonal / 30.0;
      for (final density in <double>[0.2, 0.5, 0.8]) {
        final out = IsotropicRemesher.remesh(mesh,
            targetEdgeLength: target,
            iterations: 3,
            adaptiveDensity: density);
        expect(out.faceCount, greaterThan(0));
        expect(MeshTopology(out).boundaryLoops(), isEmpty);
        expect(MeshTopology(out).components().$2, 1);
        expect(MeshTopology(out).nonManifoldEdges(), isEmpty);
      }
    });

    test('reports whether adaptive remeshing fell back', () {
      final mesh = loadModel('sphere.obj');
      final target = mesh.bounds().diagonal / 30.0;
      final adaptive = IsotropicRemesher.remeshDetailed(mesh,
          targetEdgeLength: target, iterations: 2, adaptiveDensity: 0.5);
      expect(adaptive.usedUniformFallback, isFalse);
      expect(adaptive.fallbackReason, isNull);
      expect(adaptive.mesh.faceCount, greaterThan(0));

      final bowtie = TriMesh(
        Float32List.fromList(<double>[
          -1, 0, 0,
          1, 0, 0,
          0, 1, 0,
          0, -1, 0,
          0, 0, 1,
        ]),
        Uint32List.fromList(<int>[
          0, 1, 2,
          0, 1, 3,
          0, 1, 4,
        ]),
      );
      final fallback = IsotropicRemesher.remeshDetailed(bowtie,
          targetEdgeLength: 1.0, iterations: 2, adaptiveDensity: 0.5);
      expect(fallback.usedUniformFallback, isTrue);
      expect(fallback.fallbackReason, isNotNull);
    });

    test('produces near-uniform edges', () {
      final mesh = loadModel('sphere.obj');
      final target = mesh.bounds().diagonal / 30.0;
      final sw = Stopwatch()..start();
      final remeshed = IsotropicRemesher.remesh(mesh, targetEdgeLength: target, iterations: 4);
      sw.stop();
      expect(remeshed.validate(), isEmpty);
      expect(remeshed.faceCount, greaterThan(0));
      final topo = MeshTopology(remeshed);
      var sum = 0.0;
      var count = 0;
      for (final e in topo.edgeFaces.keys) {
        final n = remeshed.vertexCount;
        final a = e ~/ n, b = e % n;
        final dx = remeshed.vx(a) - remeshed.vx(b);
        final dy = remeshed.vy(a) - remeshed.vy(b);
        final dz = remeshed.vz(a) - remeshed.vz(b);
        sum += (dx * dx + dy * dy + dz * dz).abs();
        count++;
      }
      final rms = (sum / count);
      final meanEdge = rms <= 0 ? 0.0 : _sqrt(rms);
      print('sphere remesh: ${mesh.faceCount} -> ${remeshed.faceCount} faces, '
          'target=$target meanEdge=${meanEdge.toStringAsFixed(4)} '
          'avgValence=${topo.averageValence().toStringAsFixed(2)} '
          '${sw.elapsedMilliseconds}ms');
      expect(meanEdge, greaterThan(target * 0.6));
      expect(meanEdge, lessThan(target * 1.6));
      // Remeshing a sphere should stay close to the original radius.
      final b = remeshed.bounds();
      final original = mesh.bounds();
      expect((b.diagonal - original.diagonal).abs() / original.diagonal, lessThan(0.1));
    });

    test('reports progress and preserves sharp features', () {
      final mesh = loadModel('sphere.obj');
      var calls = 0;
      final out = IsotropicRemesher.remesh(mesh,
          targetEdgeLength: mesh.bounds().diagonal / 20.0,
          iterations: 2,
          progress: (done, total) {
            calls++;
            expect(done, lessThanOrEqualTo(total));
          });
      expect(calls, greaterThanOrEqualTo(2));
      expect(out.validate(), isEmpty);

      final cube = TriMesh(
        Float32List.fromList(<double>[
          -1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1,
          -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1,
        ]),
        Uint32List.fromList(<int>[
          0, 2, 1, 0, 3, 2,
          4, 5, 6, 4, 6, 7,
          0, 1, 5, 0, 5, 4,
          1, 2, 6, 1, 6, 5,
          2, 3, 7, 2, 7, 6,
          3, 0, 4, 3, 4, 7,
        ]),
      );
      final sharp = IsotropicRemesher.remesh(cube,
          targetEdgeLength: cube.bounds().diagonal / 8.0,
          iterations: 1,
          preserveSharp: true,
          sharpAngleDegrees: 30);
      expect(sharp.faceCount, greaterThan(0));
      expect(sharp.validate(), isEmpty);
      expect(MeshTopology(sharp).boundaryLoops(), isEmpty);
    });

    test('preserves an open boundary', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final open = PlaneCut.cut(mesh,
          point: <double>[0, b.minY + b.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          fill: false);
      final before = MeshTopology(open).boundaryLoops().length;
      final out = IsotropicRemesher.remesh(open,
          targetEdgeLength: open.bounds().diagonal / 25.0,
          iterations: 1,
          preserveBoundary: true);
      expect(out.validate(), isEmpty);
      expect(MeshTopology(out).boundaryLoops().length, before);
    });
  });

  group('collapse mesh', () {
    test('rejects sharp constraints and accepts an interior collapse', () {
      final mesh = loadModel('sphere.obj');
      final cm = CollapseMesh(mesh);
      final key = cm.edgeCount.keys.first;
      final n = mesh.vertexCount;
      final a = key ~/ n, b = key % n;
      final mx = (mesh.vx(a) + mesh.vx(b)) * 0.5;
      final my = (mesh.vy(a) + mesh.vy(b)) * 0.5;
      final mz = (mesh.vz(a) + mesh.vz(b)) * 0.5;
      expect(cm.tryCollapse(a, b, mx, my, mz, sharp: <int>{a, b}), isFalse);
      expect(cm.tryCollapse(a, b, mx, my, mz), isTrue);
      final out = cm.build();
      expect(out.validate(), isEmpty);
      expect(MeshTopology(out).nonManifoldEdges(), isEmpty);
    });

    test('rejects a boundary-to-interior collapse', () {
      final mesh = loadModel('sphere.obj');
      final bounds = mesh.bounds();
      final open = PlaneCut.cut(mesh,
          point: <double>[0, bounds.minY + bounds.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          fill: false);
      final topo = MeshTopology(open);
      final boundary = <int>{
        for (final e in topo.boundaryEdges()) ...[e[0], e[1]],
      };
      final cm = CollapseMesh(open);
      int? foundA, foundB;
      for (final key in cm.edgeCount.keys) {
        final n = open.vertexCount;
        final a = key ~/ n, b = key % n;
        if (boundary.contains(a) != boundary.contains(b)) {
          foundA = a;
          foundB = b;
          break;
        }
      }
      expect(foundA, isNotNull);
      final a = foundA!, b = foundB!;
      expect(
          cm.tryCollapse(
            a,
            b,
            (open.vx(a) + open.vx(b)) * 0.5,
            (open.vy(a) + open.vy(b)) * 0.5,
            (open.vz(a) + open.vz(b)) * 0.5,
            preserveBoundary: true,
          ),
          isFalse);
    });

    test('rejects a collapse that would duplicate a face', () {
      final mesh = TriMesh(
        Float32List.fromList(<double>[
          0, 0, 0,
          1, 0, 0,
          0, 1, 0,
          0, 0, 1,
          1, 1, 1,
        ]),
        Uint32List.fromList(<int>[
          0, 1, 2,
          0, 3, 2,
          1, 3, 4,
        ]),
      );
      final cm = CollapseMesh(mesh);
      expect(
          cm.tryCollapse(1, 3, 0.5, 0.0, 0.5),
          isFalse);
      expect(cm.build().faceCount, 3);
    });
  });
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 30; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}
