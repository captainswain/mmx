import 'dart:io';
import 'dart:typed_data';

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
      final generated = ComplexTools.generate(parts);
      expect(generated.faceCount, combined.faceCount);
      expect(MeshTopology(generated).components().$2, 2);
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

    test('adds a tube to an existing mesh', () {
      final mesh = loadModel('sphere.obj');
      final combined = AddTube.addTo(
        mesh,
        <List<double>>[
          <double>[0, 0, 0],
          <double>[0, 0, 10],
        ],
        radius: 1.0,
        segments: 8,
      );
      expect(combined.faceCount, greaterThan(mesh.faceCount));
      expect(MeshTopology(combined).components().$2, 2);
      final unchanged = AddTube.addTo(mesh, <List<double>>[]);
      expect(unchanged.faceCount, mesh.faceCount);
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

    test('creates a fan from explicit points', () {
      final polygon = MakePolygon.fromPoints(<List<double>>[
        <double>[0, 0, 0],
        <double>[1, 0, 0],
        <double>[1, 0, 1],
        <double>[0, 0, 1],
      ]);
      expect(polygon.faceCount, 2);
      expect(polygon.surfaceArea(), closeTo(1.0, 1e-6));
      expect(MakePolygon.fromPoints(<List<double>>[
        <double>[0, 0, 0],
        <double>[1, 0, 0],
      ]).faceCount, 0);
    });

    test('triangulates a concave polygon without overlapping', () {
      final lShape = <List<double>>[
        <double>[0, 0, 0],
        <double>[2, 0, 0],
        <double>[2, 0, 1],
        <double>[1, 0, 1],
        <double>[1, 0, 2],
        <double>[0, 0, 2],
      ];
      final polygon = MakePolygon.fromPoints(lShape);
      expect(polygon.faceCount, 4);
      expect(polygon.surfaceArea(), closeTo(3.0, 1e-6));
      final reversed = MakePolygon.fromPoints(lShape.reversed.toList());
      expect(reversed.faceCount, 4);
      expect(reversed.surfaceArea(), closeTo(3.0, 1e-6));
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
      final point = Pivot.atPoint(<double>[1, 2, 3]);
      expect(point.position, <double>[1, 2, 3]);
      expect(point.normal, <double>[0, 1, 0]);
      final degenerate = Pivot.atPoint(<double>[1, 2, 3], normal: <double>[0, 0, 0]);
      expect(degenerate.normal, <double>[0, 1, 0]);
    });
  });

  group('unwrap', () {
    test('planar projection produces normalized UVs', () {
      final mesh = loadModel('sphere.obj');
      final uv = Unwrap.planar(mesh, axis: 1);
      expect(uv.uv.length, mesh.vertexCount * 2);
      expect(uv.uv.every((v) => v >= 0 && v <= 1), isTrue);
    });

    test('supports x and z projections', () {
      final mesh = loadModel('sphere.obj');
      for (final axis in <int>[0, 2]) {
        final uv = Unwrap.planar(mesh, axis: axis);
        expect(uv.uv.length, mesh.vertexCount * 2);
        expect(uv.uv.every((v) => v >= 0 && v <= 1), isTrue);
      }
    });

    test('unwraps each connected component separately', () {
      final a = loadModel('sphere.obj');
      final b = a.clone();
      for (var i = 0; i < b.vertexCount; i++) {
        b.positions[i * 3] += 30.0;
      }
      final combined = Modify.combine(<TriMesh>[a, b]);
      final parts = Unwrap.perComponent(combined, axis: 1);
      expect(parts.length, 2);
      for (final part in parts) {
        expect(part.uv.length, part.mesh.vertexCount * 2);
        expect(part.uv.every((v) => v >= 0 && v <= 1), isTrue);
      }
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

    test('bend rotates vertices around an axis', () {
      final mesh = loadModel('sphere.obj');
      final b = mesh.bounds();
      final bent = SoftMove.bend(mesh,
          center: <double>[0, 0, 0],
          axis: <double>[0, 1, 0],
          angle: 0.5,
          radius: b.diagonal);
      expect(bent.vertexCount, mesh.vertexCount);
      expect(bent.validate(), isEmpty);
      expect(bent.signedVolume(), isNot(equals(mesh.signedVolume())));
      final unchanged = SoftMove.bend(mesh,
          center: <double>[0, 0, 0],
          axis: <double>[0, 0, 0],
          angle: 0.5,
          radius: b.diagonal);
      expect(unchanged.signedVolume(), closeTo(mesh.signedVolume(), 1e-6));
    });
  });

  group('hole smooth fill', () {
    test('relaxes only the filled patch', () {
      final mesh = loadModel('sphere.obj');
      final keep = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (f == 0) continue;
        keep.addAll(<int>[
          mesh.indices[f * 3],
          mesh.indices[f * 3 + 1],
          mesh.indices[f * 3 + 2],
        ]);
      }
      final holed = TriMesh(mesh.positions, Uint32List.fromList(keep));
      final loop = MeshTopology(holed).boundaryLoops().first;
      final filled = HoleFiller.fill(holed,
          mode: HoleFillMode.smooth, smoothIterations: 5);
      expect(MeshTopology(filled).boundaryLoops(), isEmpty);
      final loopSet = loop.toSet();
      for (var v = 0; v < mesh.vertexCount; v++) {
        if (loopSet.contains(v)) continue;
        expect(filled.vx(v), closeTo(mesh.vx(v), 1e-9));
        expect(filled.vy(v), closeTo(mesh.vy(v), 1e-9));
        expect(filled.vz(v), closeTo(mesh.vz(v), 1e-9));
      }
    });
  });
}
