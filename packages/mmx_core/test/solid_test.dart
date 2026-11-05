import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('precise boolean', () {
    test('mesh-level union/difference/intersection are watertight', () {
      final a = loadModel('sphere.obj');
      final b = a.clone();
      for (var i = 0; i < b.vertexCount; i++) {
        b.positions[i * 3] += 1.0;
      }
      for (final op in BooleanOp.values) {
        final out = PreciseBoolean.compute(a, b, op);
        final loops = MeshTopology(out).boundaryLoops();
        print('precise $op: faces=${out.faceCount} '
            'volume=${out.signedVolume().toStringAsFixed(3)} '
            'loops=${loops.length}');
        expect(out.faceCount, greaterThan(0));
        expect(loops, isEmpty, reason: '$op must be watertight');
        expect(out.signedVolume(), greaterThan(0));
      }
    });

    test('edgeLength remeshes the inputs before cutting', () {
      final a = loadModel('sphere.obj');
      final b = a.clone();
      for (var i = 0; i < b.vertexCount; i++) {
        b.positions[i * 3] += 1.0;
      }
      final out = PreciseBoolean.compute(a, b, BooleanOp.union,
          edgeLength: a.bounds().diagonal / 80.0);
      expect(out.faceCount, greaterThan(0));
      expect(MeshTopology(out).boundaryLoops(), isEmpty);
    });

    test('empty mesh-level result falls back to grid CSG', () {
      final a = loadModel('sphere.obj');
      final b = a.clone();
      final bounds = a.bounds();
      final c = <double>[
        (bounds.minX + bounds.maxX) / 2,
        (bounds.minY + bounds.maxY) / 2,
        (bounds.minZ + bounds.maxZ) / 2,
      ];
      b.transform(Float64List.fromList(<double>[
        1.5, 0, 0, 0,
        0, 1.5, 0, 0,
        0, 0, 1.5, 0,
        c[0] * (1 - 1.5), c[1] * (1 - 1.5), c[2] * (1 - 1.5), 1,
      ]));
      final result = PreciseBoolean.computeDetailed(a, b, BooleanOp.difference);
      expect(result.usedFallback, isTrue);
      expect(result.fallbackReason, contains('empty'));
      expect(result.mesh.signedVolume().abs(), lessThan(1e-6));
      expect(MeshTopology(result.mesh).boundaryLoops(), isEmpty);
    });

    test('stitching failure falls back to grid CSG', () {
      final a = loadModel('sphere.obj');
      final keep = <int>[];
      for (var f = 0; f < a.faceCount; f++) {
        if (f % 211 == 0) continue;
        keep.addAll(<int>[
          a.indices[f * 3],
          a.indices[f * 3 + 1],
          a.indices[f * 3 + 2],
        ]);
      }
      final open = TriMesh(a.positions, Uint32List.fromList(keep));
      final result = PreciseBoolean.computeDetailed(open, a.clone(), BooleanOp.union);
      expect(result.mesh.faceCount, greaterThan(0));
      expect(result.usedFallback, isTrue);
      expect(result.fallbackReason, isNotNull);
      expect(MeshTopology(result.mesh).boundaryLoops(), isEmpty);
    });
  });

  group('make solid', () {
    test('turns a sphere into a watertight solid', () {
      final mesh = loadModel('sphere.obj');
      final sw = Stopwatch()..start();
      final result = Solidifier.makeSolid(mesh, mode: SolidMode.fast, resolution: 96);
      sw.stop();
      final topo = MeshTopology(result.mesh);
      final loops = topo.boundaryLoops();
      final originalVolume = mesh.signedVolume();
      final solidVolume = result.mesh.signedVolume();
      print('solid: faces=${result.mesh.faceCount} cell=${result.cellSize.toStringAsFixed(3)} '
          'volume=${solidVolume.toStringAsFixed(1)} (orig ${originalVolume.toStringAsFixed(1)}) '
          'boundaryLoops=${loops.length} ${sw.elapsedMilliseconds}ms');
      expect(result.mesh.faceCount, greaterThan(100));
      expect(loops, isEmpty, reason: 'Make Solid must produce a closed surface');
      expect(solidVolume, greaterThan(0));
      expect((solidVolume - originalVolume).abs() / originalVolume, lessThan(0.15));
      // Fast mode reprojects the meshed surface onto the input, so its
      // vertices should sit on the original surface.
      final rms = AlignTool.rmsDistance(result.mesh, mesh);
      expect(rms, lessThan(result.cellSize));
    });

    test('fills holes before solidifying', () {
      final mesh = loadModel('dog.obj');
      final keep = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (f % 97 == 0) continue; // scatter holes
        keep.addAll(<int>[mesh.indices[f * 3], mesh.indices[f * 3 + 1], mesh.indices[f * 3 + 2]]);
      }
      final holed = TriMesh(mesh.positions, Uint32List.fromList(keep));
      final result = Solidifier.makeSolid(holed, mode: SolidMode.blocky, resolution: 72);
      expect(MeshTopology(result.mesh).boundaryLoops(), isEmpty);
    });
  });

  group('boolean', () {
    test('difference removes material', () {
      final sphere = loadModel('sphere.obj');
      final other = sphere.clone();
      other.transform(Float64List.fromList(<double>[
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        sphere.bounds().extentX * 0.35, 0, 0, 1,
      ]));
      final result = Solidifier.boolean(sphere, other, BooleanOp.difference, resolution: 80);
      final v = result.mesh.signedVolume();
      print('boolean diff: volume ${v.toStringAsFixed(1)} vs sphere ${sphere.signedVolume().toStringAsFixed(1)}, '
          'faces=${result.mesh.faceCount}');
      expect(v, greaterThan(0));
      expect(v, lessThan(sphere.signedVolume()));
      expect(MeshTopology(result.mesh).boundaryLoops(), isEmpty);
    });

    test('union of disjoint shapes yields two components', () {
      final sphere = loadModel('sphere.obj');
      final other = sphere.clone();
      final dx = sphere.bounds().extentX * 1.4;
      other.transform(Float64List.fromList(<double>[
        1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, dx, 0, 0, 1,
      ]));
      final result = Solidifier.boolean(sphere, other, BooleanOp.union, resolution: 64);
      final comps = MeshTopology(result.mesh).components().$2;
      expect(comps, 2);
    });
  });

  group('offset and hollow', () {
    test('offset grows the surface', () {
      final mesh = loadModel('sphere.obj');
      final grown = Solidifier.offsetSolid(mesh, mesh.bounds().extentX * 0.05, resolution: 96);
      expect(grown.mesh.signedVolume(), greaterThan(mesh.signedVolume()));
    });

    test('hollow produces a shell with escape holes', () {
      final mesh = loadModel('sphere.obj');
      final t = mesh.bounds().extentX * 0.08;
      final result = Solidifier.hollow(mesh,
          thickness: t, holes: 4, holeRadius: t * 1.2, resolution: 96);
      final vol = result.mesh.signedVolume();
      print('hollow: volume ${vol.toStringAsFixed(1)} vs solid ${mesh.signedVolume().toStringAsFixed(1)}, '
          'faces=${result.mesh.faceCount}');
      expect(vol, greaterThan(0));
      expect(vol, lessThan(mesh.signedVolume() * 0.6));
      expect(MeshTopology(result.mesh).boundaryLoops(), isEmpty);
    });

    test('hollow enforces a minimum wall thickness', () {
      final mesh = loadModel('sphere.obj');
      final t = mesh.bounds().extentX * 0.08;
      final result = Solidifier.hollow(mesh,
          thickness: t,
          holes: 0,
          resolution: 64,
          minThickness: t * 0.5);
      expect(result.mesh.faceCount, greaterThan(0));
      expect(result.mesh.signedVolume(), greaterThan(0));
      expect(MeshTopology(result.mesh).boundaryLoops(), isEmpty);
    });

    test('hollow supports an open top', () {
      final mesh = loadModel('sphere.obj');
      final t = mesh.bounds().extentX * 0.08;
      final result = Solidifier.hollow(mesh,
          thickness: t, holes: 0, resolution: 64, openTop: true);
      expect(result.mesh.faceCount, greaterThan(0));
    });
  });
}
