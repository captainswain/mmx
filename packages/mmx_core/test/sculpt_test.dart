import 'dart:io';
import 'dart:math' as math;

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('crease brush', () {
    test('pulls the surface toward the brush centre and stays valid', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final center = <double>[
        (b.minX + b.maxX) / 2,
        b.maxY,
        (b.minZ + b.maxZ) / 2,
      ];
      final creased = Sculptor.apply(mesh,
          op: BrushOp.crease,
          center: center,
          radius: b.extentX * 0.2,
          strength: 0.6);
      expect(creased.faceCount, mesh.faceCount);
      expect(creased.validate(), isEmpty);
      var moved = 0;
      for (var v = 0; v < mesh.vertexCount; v++) {
        if (creased.vx(v) != mesh.vx(v) ||
            creased.vy(v) != mesh.vy(v) ||
            creased.vz(v) != mesh.vz(v)) {
          moved++;
        }
      }
      expect(moved, greaterThan(0));
      expect(creased.signedVolume(), greaterThan(0));
    });
  });

  group('twist brush', () {
    test('rotates vertices around the local normal without NaN', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final center = <double>[0, b.maxY, 0];
      final radius = b.extentX * 0.25;
      final twisted = Sculptor.apply(mesh,
          op: BrushOp.twist,
          center: center,
          radius: radius,
          strength: 0.8);
      expect(twisted.faceCount, mesh.faceCount);
      expect(twisted.validate(), isEmpty);
      for (var i = 0; i < twisted.positions.length; i++) {
        expect(twisted.positions[i].isFinite, isTrue);
      }
      // A vertex near the brush edge moves tangentially, so its distance to
      // the centre is approximately preserved.
      var checked = 0;
      for (var v = 0; v < mesh.vertexCount; v++) {
        final d = math.sqrt(math.pow(mesh.vx(v) - center[0], 2) +
            math.pow(mesh.vy(v) - center[1], 2) +
            math.pow(mesh.vz(v) - center[2], 2));
        if (d < radius * 0.5 || d > radius) continue;
        final d2 = math.sqrt(math.pow(twisted.vx(v) - center[0], 2) +
            math.pow(twisted.vy(v) - center[1], 2) +
            math.pow(twisted.vz(v) - center[2], 2));
        expect(d2, closeTo(d, d * 0.1));
        checked++;
      }
      expect(checked, greaterThan(0));
    });
  });
}
