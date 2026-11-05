import 'dart:io';
import 'dart:math' as math;

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = 'test/fixtures/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('stamp', () {
    test('a circular stamp raises the surface and keeps the mesh valid', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final center = <double>[0, b.maxY, 0];
      final stamped = StampTool.apply(mesh,
          center: center,
          radius: b.extentX * 0.25,
          height: 2.0,
          pattern: StampPattern.circle);
      expect(stamped.faceCount, mesh.faceCount);
      expect(stamped.validate(), isEmpty);
      expect(stamped.bounds().maxY, greaterThan(mesh.bounds().maxY));
      expect(stamped.signedVolume(), greaterThan(mesh.signedVolume()));
      for (var i = 0; i < stamped.positions.length; i++) {
        expect(stamped.positions[i].isFinite, isTrue);
      }
    });

    test('a ring leaves the centre vertex untouched', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final center = <double>[0, b.maxY, 0];
      final stamped = StampTool.apply(mesh,
          center: center,
          radius: b.extentX * 0.25,
          height: 2.0,
          pattern: StampPattern.ring);
      var best = 0;
      var bestD = double.infinity;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final d = math.sqrt(math.pow(mesh.vx(v) - center[0], 2) +
            math.pow(mesh.vy(v) - center[1], 2) +
            math.pow(mesh.vz(v) - center[2], 2));
        if (d < bestD) {
          bestD = d;
          best = v;
        }
      }
      expect(stamped.vx(best), closeTo(mesh.vx(best), 1e-4));
      expect(stamped.vy(best), closeTo(mesh.vy(best), 1e-4));
      expect(stamped.vz(best), closeTo(mesh.vz(best), 1e-4));
    });
  });
}
