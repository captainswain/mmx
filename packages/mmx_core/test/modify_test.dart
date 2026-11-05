import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = 'test/fixtures/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('flip normals', () {
    test('reverses winding and signed volume', () {
      final mesh = loadModel('sphere.obj');
      final flipped = Modify.flipNormals(mesh);
      expect(flipped.faceCount, mesh.faceCount);
      expect(flipped.surfaceArea(), closeTo(mesh.surfaceArea(), 1e-2));
      expect(flipped.signedVolume(), closeTo(-mesh.signedVolume(), 1e-2));
    });

    test('face mask restricts the flip', () {
      final mesh = loadModel('sphere.obj');
      final mask = Uint8List(mesh.faceCount)
        ..fillRange(0, mesh.faceCount ~/ 2, 1);
      final flipped = Modify.flipNormals(mesh, faceMask: mask);
      final changed = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (flipped.indices[f * 3 + 1] != mesh.indices[f * 3 + 1]) {
          changed.add(f);
        }
      }
      expect(changed.length, mesh.faceCount ~/ 2);
    });
  });

  group('smooth', () {
    test('taubin smoothing keeps volume and closes nothing new', () {
      final mesh = loadModel('sphere.obj');
      final smoothed = Modify.smooth(mesh, iterations: 6);
      expect(smoothed.faceCount, mesh.faceCount);
      expect(smoothed.signedVolume(),
          closeTo(mesh.signedVolume(), mesh.signedVolume().abs() * 0.05));
      expect(smoothed.validate(), isEmpty);
    });
  });

  group('placement', () {
    test('drop to bed puts the lowest point on the bed', () {
      final mesh = loadModel('sphere.obj');
      final dropped = Modify.dropToBed(mesh, bedY: 0);
      expect(dropped.bounds().minY, closeTo(0, 1e-3));
    });

    test('center on bed centers the footprint', () {
      final mesh = loadModel('sphere.obj');
      final placed = Modify.centerOnBed(mesh);
      final b = placed.bounds();
      expect(b.minY, closeTo(0, 1e-3));
      expect((b.minX + b.maxX) / 2, closeTo(0, 1e-3));
      expect((b.minZ + b.maxZ) / 2, closeTo(0, 1e-3));
    });
  });

  group('duplicate and combine', () {
    test('duplicate offsets geometry', () {
      final mesh = loadModel('sphere.obj');
      final copy = Modify.duplicate(mesh, offset: <double>[10, 0, 0]);
      expect(copy.faceCount, mesh.faceCount);
      expect(copy.bounds().minX, closeTo(mesh.bounds().minX + 10, 1e-3));
    });

    test('combine joins meshes and preserves shells', () {
      final mesh = loadModel('sphere.obj');
      final joined = Modify.combine(<TriMesh>[
        mesh,
        Modify.duplicate(mesh,
            offset: <double>[mesh.bounds().extentX * 2, 0, 0]),
      ]);
      expect(joined.faceCount, mesh.faceCount * 2);
      expect(MeshTopology(joined).components().$2, 2);
      expect(joined.signedVolume(),
          closeTo(mesh.signedVolume() * 2, mesh.signedVolume().abs() * 0.02));
    });
  });

  group('pattern', () {
    test('grid pattern multiplies faces by the requested count', () {
      final mesh = loadModel('sphere.obj');
      final pattern = Modify.makePattern(mesh, countX: 3, countZ: 2, gap: 1);
      expect(pattern.faceCount, mesh.faceCount * 6);
      expect(MeshTopology(pattern).components().$2, 6);
    });
  });

  group('fit primitive', () {
    test('box primitive matches the input bounds and is closed', () {
      final mesh = loadModel('sphere.obj');
      final box = Modify.fitPrimitive(mesh, PrimitiveKind.box);
      final a = mesh.bounds(), b = box.bounds();
      expect(b.extentX, closeTo(a.extentX, 1e-2));
      expect(b.extentY, closeTo(a.extentY, 1e-2));
      expect(b.extentZ, closeTo(a.extentZ, 1e-2));
      expect(MeshTopology(box).boundaryLoops(), isEmpty);
    });

    test('sphere primitive is closed and centred on the input', () {
      final mesh = loadModel('sphere.obj');
      final sphere = Modify.fitPrimitive(mesh, PrimitiveKind.sphere);
      final c = sphere.centroid();
      final mc = mesh.centroid();
      expect(c[0], closeTo(mc[0], 1e-2));
      expect(c[2], closeTo(mc[2], 1e-2));
      expect(MeshTopology(sphere).boundaryLoops(), isEmpty);
      expect(sphere.signedVolume(), greaterThan(0));
    });
  });

  group('measure', () {
    test('reports dimensions, area, volume and watertightness', () {
      final mesh = loadModel('sphere.obj');
      final m = Modify.measure(mesh);
      expect(m.dimensions.length, 3);
      expect(m.dimensions[0], closeTo(mesh.bounds().extentX, 1e-2));
      expect(m.surfaceArea, closeTo(mesh.surfaceArea(), 1e-2));
      expect(m.volume, greaterThan(0));
      expect(m.shellCount, 1);
      expect(m.watertight, isTrue);
    });
  });

  group('clearance', () {
    test('reports the gap between two separated spheres', () {
      final mesh = loadModel('sphere.obj');
      final r = mesh.bounds().extentX / 2;
      final other = Modify.duplicate(mesh, offset: <double>[2 * r + 5, 0, 0]);
      final gap = Modify.clearance(mesh, other);
      expect(gap, closeTo(5, 0.25));
    });
  });

  group('group-aware remesh', () {
    test('preserves face groups and both group ids', () {
      final mesh = loadModel('sphere.obj');
      final groups = Uint16List(mesh.faceCount);
      for (var f = 0; f < mesh.faceCount; f++) {
        groups[f] = f < mesh.faceCount ~/ 2 ? 0 : 1;
      }
      mesh.faceGroups = groups;
      final remeshed = IsotropicRemesher.remesh(
        mesh,
        targetEdgeLength: mesh.bounds().diagonal * 0.08,
        iterations: 2,
        preserveGroupBoundaries: true,
      );
      expect(remeshed.faceGroups, isNotNull);
      expect(remeshed.faceGroups!.length, remeshed.faceCount);
      expect(remeshed.faceGroups!.toSet(), containsAll(<int>[0, 1]));
      expect(remeshed.signedVolume(),
          closeTo(mesh.signedVolume(), mesh.signedVolume().abs() * 0.15));
    });
  });
}
