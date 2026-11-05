import 'dart:io';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

const String modelsDir = '/data/re/meshmixer/extract/meshmixer/models';

TriMesh loadModel(String name) =>
    MeshIO.readBytes(name, File('$modelsDir/$name').readAsBytesSync());

void main() {
  group('complex tools', () {
    test('split and join connected shells', () {
      final a = loadModel('sphere.obj');
      final b = a.clone();
      for (var i = 0; i < b.vertexCount; i++) {
        b.positions[i * 3] += 30.0;
      }
      final combined = Modify.combine(<TriMesh>[a, b]);
      final parts = ComplexTools.split(combined);
      expect(parts.length, 2);
      expect(parts.every((p) => p.faceCount > 0), isTrue);
      final joined = ComplexTools.join(parts);
      expect(joined.faceCount, combined.faceCount);
      expect(MeshTopology(joined).components().$2, 2);
      final filtered = ComplexTools.filter(combined, minFaces: 100);
      expect(filtered.faceCount, combined.faceCount);
    });
  });

  group('add tube', () {
    test('builds a watertight capped tube', () {
      final tube = AddTube.build(<List<double>>[
        <double>[0, 0, 0],
        <double>[0, 0, 10],
        <double>[5, 0, 15],
      ], radius: 1.0, segments: 12);
      expect(tube.faceCount, greaterThan(0));
      expect(MeshTopology(tube).boundaryLoops(), isEmpty);
      expect(MeshTopology(tube).components().$2, 1);
      expect(tube.signedVolume(), greaterThan(0));
      expect(tube.bounds().extentZ, greaterThan(14));
    });
  });

  group('make polygon', () {
    test('creates a fan from a boundary loop', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final cut = PlaneCut.cut(mesh,
          point: <double>[0, b.minY + b.extentY * 0.5, 0],
          normal: <double>[0, 1, 0],
          fill: false);
      final loop = MeshTopology(cut).boundaryLoops().first;
      final polygon = MakePolygon.fromLoop(cut, loop);
      expect(polygon.faceCount, loop.length - 2);
      expect(polygon.surfaceArea(), greaterThan(0));
    });
  });

  group('make part', () {
    test('extracts a face region and solidifies it', () {
      final mesh = loadModel('sphere.obj');
      final faces = <int>{for (var i = 0; i < 100; i++) i};
      final part = ComplexTools.extract(mesh, faces);
      expect(part.faceCount, 100);
      final solid = ComplexTools.makeSolidPart(mesh, faces, resolution: 64);
      expect(solid.faceCount, greaterThan(0));
      expect(MeshTopology(solid).boundaryLoops(), isEmpty);
    });
  });

  group('pivot', () {
    test('creates a pivot at a vertex with a unit normal', () {
      final mesh = loadModel('sphere.obj');
      final pivot = Pivot.atVertex(mesh, 0);
      expect(pivot.position.length, 3);
      final n = pivot.normal;
      final len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
      expect(len, closeTo(1.0, 1e-6));
    });
  });

  group('unwrap', () {
    test('planar projection produces normalized UVs', () {
      final mesh = loadModel('sphere.obj');
      final uv = Unwrap.planar(mesh, axis: 1);
      expect(uv.uv.length, mesh.vertexCount * 2);
      expect(uv.uv.every((v) => v >= 0 && v <= 1), isTrue);
    });
  });

  group('soft move', () {
    test('displaces vertices near a handle', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final moved = SoftMove.apply(mesh,
          center: <double>[b.maxX, 0, 0],
          offset: <double>[2, 0, 0],
          radius: 4.0);
      expect(moved.vertexCount, mesh.vertexCount);
      expect(moved.bounds().maxX, greaterThan(b.maxX));
      expect(moved.signedVolume(), isNot(equals(mesh.signedVolume())));
    });
  });
}
