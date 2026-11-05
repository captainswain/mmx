import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = 'test/fixtures/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

Float64List rigid(double ax, double ay, double az, double angle, double tx,
    double ty, double tz) {
  final c = math.cos(angle), s = math.sin(angle);
  final l = math.sqrt(ax * ax + ay * ay + az * az);
  final x = ax / l, y = ay / l, z = az / l;
  final t = 1 - c;
  return Float64List.fromList(<double>[
    t * x * x + c,
    t * x * y - s * z,
    t * x * z + s * y,
    0,
    t * x * y + s * z,
    t * y * y + c,
    t * y * z - s * x,
    0,
    t * x * z - s * y,
    t * y * z + s * x,
    t * z * z + c,
    0,
    tx,
    ty,
    tz,
    1,
  ]);
}

void main() {
  group('align', () {
    test('recovers a known rigid offset', () {
      final target = loadModel('sphere.obj');
      final source = target.clone();
      source.transform(rigid(0, 0, 1, 0.4, 4.0, -2.0, 1.5));
      expect(AlignTool.rmsDistance(source, target), greaterThan(1.0));

      final aligned = AlignTool.align(source, target, iterations: 40);
      final rms = AlignTool.rmsDistance(aligned, target);
      expect(rms, lessThan(0.35));
      expect(aligned.signedVolume(),
          closeTo(target.signedVolume(), target.signedVolume() * 0.02));

      final a = aligned.bounds(), b = target.bounds();
      expect(a.minX, closeTo(b.minX, 0.2));
      expect(a.maxY, closeTo(b.maxY, 0.2));
    });

    test('already aligned input stays put', () {
      final target = loadModel('sphere.obj');
      final t = AlignTool.solve(target, target, iterations: 5);
      expect(t[0], closeTo(1, 0.01));
      expect(t[5], closeTo(1, 0.01));
      expect(t[10], closeTo(1, 0.01));
      expect(t[12].abs(), lessThan(0.1));
    });
  });
}
