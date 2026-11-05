import 'dart:io';

import 'package:mmx_core/mmx_core.dart';
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
