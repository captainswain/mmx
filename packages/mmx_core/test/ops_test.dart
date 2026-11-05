import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('analysis', () {
    test('thickness finds a thin spot on a hollowed shell', () {
      final mesh = loadModel('sphere.obj');
      final thin = Solidifier.hollow(mesh,
          thickness: mesh.bounds().extentX * 0.04, holes: 0, resolution: 80).mesh;
      final t = ThicknessAnalysis.run(thin, threshold: 0);
      print('thickness: min=${t.minThickness.toStringAsFixed(3)} '
          'mean=${t.meanThickness.toStringAsFixed(3)}');
      expect(t.minThickness, greaterThan(0));
      expect(t.minThickness, lessThan(mesh.bounds().diagonal * 0.3));
    });

    test('overhang analysis flags downward faces', () {
      final mesh = loadModel('sphere.obj');
      final o = OverhangAnalysis.run(mesh, angleDegrees: 45);
      expect(o.overhangFaces.length, greaterThan(0));
      expect(o.overhangArea, greaterThan(0));
      expect(o.overhangArea, lessThan(o.totalArea));
    });

    test('stability reports centre of mass inside the base', () {
      final mesh = loadModel('sphere.obj');
      final s = StabilityAnalysis.run(mesh);
      expect(s.centerInsideSupport, isTrue);
      expect(s.contactPoints.length, greaterThan(2));
      expect(s.minTipAngleDegrees, greaterThan(1));
    });
  });

  group('supports', () {
    test('generates posts for an overhanging shape', () {
      final mesh = loadModel('sphere.obj');
      // Lift the sphere so its bottom overhangs above the bed.
      final lifted = mesh.clone();
      lifted.transform(Float64List.fromList(<double>[
        1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, mesh.bounds().extentY * 0.5, 0, 1,
      ]));
      final sw = Stopwatch()..start();
      final result = SupportGenerator.generate(lifted,
          settings: const SupportSettings(density: 0.4, postDiameter: 1.5), bedY: 0);
      sw.stop();
      print('supports: posts=${result.postCount} struts=${result.strutCount} '
          'faces=${result.supports.faceCount} ${sw.elapsedMilliseconds}ms');
      expect(result.postCount, greaterThan(3));
      expect(result.supports.faceCount, greaterThan(0));
      expect(result.supports.validate(), isEmpty);
    });
  });

  group('packing', () {
    test('places several objects on a bed', () {
      final meshes = <TriMesh>[
        loadModel('sphere.obj'),
        loadModel('plane.obj'),
        loadModel('elephant.obj'),
      ];
      final result = Packer.pack(meshes,
          bedWidth: 300, bedDepth: 300, border: 5, quality: 1, allowRotation: true);
      print('packing: placed=${result.placed.length} unplaced=${result.unplaced.length} '
          'util=${(result.bedUtilization * 100).toStringAsFixed(1)}%');
      expect(result.placed.length, 3);
      for (final p in result.placed) {
        expect(p.x, greaterThanOrEqualTo(0));
        expect(p.x, lessThanOrEqualTo(300));
      }
    });
  });

  group('slicing', () {
    test('produces closed contours per layer', () {
      final mesh = loadModel('sphere.obj');
      final result = Slicer.slice(mesh, layerHeight: mesh.bounds().extentY / 20);
      final closed = result.layers.expand((l) => l.loops).where((l) => l.closed).length;
      print('slicing: ${result.layers.length} layers, closed loops=$closed');
      expect(result.layers.length, greaterThan(5));
      expect(closed, greaterThan(0));
    });
  });

  group('tools', () {
    test('plane cut halves the mesh and caps it', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final cut = PlaneCut.cut(mesh,
          point: <double>[0, b.minY + b.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          keepPositive: true);
      expect(cut.faceCount, greaterThan(0));
      expect(cut.signedVolume(), greaterThan(0));
      expect(cut.signedVolume(), lessThan(mesh.signedVolume()));
      final loops = MeshTopology(cut).boundaryLoops();
      expect(loops, isEmpty, reason: 'filled cut should be watertight');
    });

    test('plane cut supports the remeshed fill mode', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final cut = PlaneCut.cut(mesh,
          point: <double>[0, b.minY + b.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          fill: true,
          fillMode: HoleFillMode.flatRemeshed);
      expect(cut.faceCount, greaterThan(0));
      expect(cut.signedVolume(), greaterThan(0));
      expect(MeshTopology(cut).boundaryLoops(), isEmpty);
    });

    test('plane cut fixed fill caps the cut', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final cut = PlaneCut.cut(mesh,
          point: <double>[0, b.minY + b.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          fill: true,
          fillMode: HoleFillMode.fixed);
      expect(MeshTopology(cut).boundaryLoops(), isEmpty);
    });

    test('plane cut slice groups tags one side without changing geometry', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final grouped = PlaneCut.sliceGroups(mesh,
          point: <double>[0, b.minY + b.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          groupId: 7);
      expect(grouped.faceCount, mesh.faceCount);
      expect(grouped.signedVolume(), closeTo(mesh.signedVolume(), 1e-6));
      expect(grouped.faceGroups, isNotNull);
      expect(grouped.faceGroups!.contains(7), isTrue);
      expect(grouped.faceGroups!.contains(0), isTrue);
    });

    test('sculpt draw displaces the surface', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final center = <double>[(b.minX + b.maxX) / 2, b.maxY, (b.minZ + b.maxZ) / 2];
      final before = mesh.bounds().maxY;
      final sculpted = Sculptor.apply(mesh,
          op: BrushOp.draw, center: center, radius: b.extentX * 0.25, strength: 0.8);
      expect(sculpted.bounds().maxY, greaterThan(before));
      expect(sculpted.validate(), isEmpty);
    });

    test('brush selection and expand work', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final sel = Selection.sphereBrush(mesh,
          <double>[(b.minX + b.maxX) / 2, b.maxY, (b.minZ + b.maxZ) / 2], b.extentX * 0.3);
      final n = sel.count;
      expect(n, greaterThan(0));
      sel.expand(mesh);
      expect(sel.count, greaterThan(n));
    });

    test('face groups segment by angle', () {
      final mesh = loadModel('plane.obj');
      final groups = FaceGroups.generate(mesh, angleThresholdDegrees: 30);
      expect(groups.length, mesh.faceCount);
    });
  });

  group('document', () {
    test('undo and redo restore objects', () {
      final doc = Document();
      final obj = doc.add(loadModel('sphere.obj'));
      // Snapshots record the state *before* an action, as in Meshmixer's
      // history nodes.
      doc.snapshot('reduce');
      obj.mesh = Decimator.reduce(obj.mesh, percentage: 0.2);
      final reduced = obj.mesh.faceCount;
      expect(doc.undo(), isTrue);
      expect(doc.objects.first.mesh.faceCount, greaterThan(reduced));
      expect(doc.redo(), isTrue);
      expect(doc.objects.first.mesh.faceCount, reduced);
    });
  });
}
