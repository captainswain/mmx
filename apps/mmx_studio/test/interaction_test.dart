import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_studio/state/manipulator.dart';
import 'package:mmx_studio/state/spatial_cache.dart';
import 'package:mmx_studio/state/studio_state.dart';
import 'package:mmx_studio/ui/gizmo.dart';
import 'package:mmx_studio/ui/viewport.dart';

TriMesh sphere() => Modify.fitPrimitive(
  TriMesh(Float32List.fromList([-5, -5, -5, 5, 5, 5]), Uint32List(0)),
  PrimitiveKind.sphere,
);
StudioState makeState() {
  final state = StudioState(loadStartup: false)
    ..frameWidth = 160
    ..frameHeight = 120;
  state.selectedObjectId = state.doc.add(sphere()).id;
  state.frameSelection();
  return state;
}

class RenderFailureState extends StudioState {
  RenderFailureState() : super(loadStartup: false);
  bool failNextRender = false;
  @override
  Future<void> render() async {
    if (failNextRender) {
      failNextRender = false;
      throw StateError('Injected render failure');
    }
  }
}

void main() {
  testWidgets('failed and cancelled imports restore source attachments', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = RenderFailureState();
      final dir = await Directory.systemTemp.createTemp('mmx-rollback-');
      try {
        state.selectedObjectId = state.doc.add(sphere()).id;
        final existing = ProjectSourceAttachment(
          name: 'prior.mix',
          bytes: Uint8List.fromList([1, 2, 3]),
        );
        state.sourceAttachments.add(existing);
        final source = MixIO.write([MixObject(name: 'import', mesh: sphere())]);
        final path = '${dir.path}/incoming.mix';
        await File(path).writeAsBytes(source);
        state.failNextRender = true;
        await state.importPath(path);
        expect(state.status, contains('Injected render failure'));
        expect(state.doc.objects.length, 1);
        expect(state.doc.canUndo, false);
        expect(state.sourceAttachments, [existing]);
        void cancelWhenComputing() {
          if (state.operationPhase == 'Computing') {
            state.removeListener(cancelWhenComputing);
            state.cancelOperation();
          }
        }

        state.addListener(cancelWhenComputing);
        await state.importPath(path);
        expect(state.status, contains('cancelled'));
        expect(state.doc.objects.length, 1);
        expect(state.sourceAttachments, [existing]);
        final projectPath = '${dir.path}/incoming.mmx';
        await File(projectPath).writeAsBytes(
          ProjectIO.write(ProjectData([SceneObject(99, 'incoming', sphere())])),
        );
        state.addListener(cancelWhenComputing);
        expect(await state.openProject(projectPath), false);
        expect(state.doc.objects.single.id, isNot(99));
        expect(state.sourceAttachments, [existing]);
        expect(state.projectPath, isNull);
        expect(await state.openProject('${dir.path}/missing.mmx'), false);
        expect(state.sourceAttachments, [existing]);
      } finally {
        state.dispose();
        await dir.delete(recursive: true);
      }
    });
  });
  testWidgets('cancelled stroke preserves a newer external document', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = makeState();
      expect(state.beginSculptStroke(), true);
      final dab = state.queueSculptSample(80, 60);
      state.doc.replaceObjects([SceneObject(99, 'replacement', sphere())]);
      await state.cancelInteraction();
      await dab;
      expect(state.doc.objects.single.id, 99);
      expect(state.gestureActive, false);
      state.dispose();
    });
  });
  testWidgets('dispose aborts in-flight stroke and restores its checkpoint', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = makeState();
      final original = List<double>.from(state.activeMesh!.positions);
      state.beginSculptStroke();
      await state.queueSculptSample(80, 60);
      final pending = state.queueSculptSample(82, 60);
      state.dispose();
      await pending;
      await state.endSculptStroke(cancel: true);
      expect(state.gestureActive, false);
      expect(state.doc.undoDepth, 0);
      expect(state.activeMesh!.positions, original);
    });
  });
  testWidgets('native projects retain original mix bytes after editing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = makeState();
      final dir = await Directory.systemTemp.createTemp('mmx-source-');
      try {
        final source = MixIO.write([
          MixObject(name: 'original', mesh: sphere()),
        ]);
        final path = '${dir.path}/original.mix';
        await File(path).writeAsBytes(source);
        await state.importPath(path);
        expect(state.sourceAttachments.single.bytes, source);
        await state.doFlipNormals();
        expect(
          await state.saveProject('${dir.path}/scene.mmx'),
          true,
          reason: state.status,
        );
        state.sourceAttachments.clear();
        expect(
          await state.openProject('${dir.path}/scene.mmx'),
          true,
          reason: state.status,
        );
        expect(state.sourceAttachments.single.name, 'original.mix');
        expect(state.sourceAttachments.single.bytes, source);
      } finally {
        state.dispose();
        await dir.delete(recursive: true);
      }
    });
  });
  test(
    'spatial cache reuses hits and invalidates on mesh revision and transform',
    () {
      final cache = SceneSpatialCache();
      final object = SceneObject(1, 'sphere', sphere());
      final first = cache.bvh(object, 1), topology = cache.topology(object, 1);
      expect(identical(cache.bvh(object, 1), first), true);
      expect(identical(cache.topology(object, 1), topology), true);
      object.transform = translation4(10, 0, 0);
      expect(identical(cache.bvh(object, 1), first), false);
      expect(identical(cache.topology(object, 1), topology), true);
      final transformed = cache.bvh(object, 1);
      expect(identical(cache.bvh(object, 2), transformed), false);
      expect(cache.bvhBuilds, 3);
      expect(cache.worldMesh(object, 2).bounds().minX, closeTo(5, 1e-6));
    },
  );
  test(
    'inverse affine pivot conversion handles nonuniform scale and rotation',
    () {
      final scale = identity4()
        ..[0] = 2
        ..[5] = 3
        ..[10] = 4;
      final transform = multiply4(
        translation4(7, 9, 11),
        multiply4(rotation4(0, 1, 0, .7), scale),
      );
      final p = [1.0, 2.0, 3.0];
      final world = transformPoint(transform, p);
      final local = inverseTransformPoint(transform, world);
      for (var i = 0; i < 3; i++) {
        expect(local[i], closeTo(p[i], 1e-10));
      }
      expect(
        () => inverseTransformPoint(Float64List(16), world),
        throwsFormatException,
      );
    },
  );
  testWidgets(
    'axis gestures commit one undo step and rotate around a world pivot',
    (tester) async {
      await tester.runAsync(() async {
        final state = makeState();
        final object = state.selected!;
        object.transform = translation4(10, 0, 0);
        object.pivot = Pivot.atPoint([2, 0, 0]);
        state.setManipulatorMode(ManipulatorMode.translate);
        expect(state.beginManipulator(0), true);
        state.updateManipulator(2);
        state.updateManipulator(3);
        await state.endManipulator();
        expect(state.doc.undoDepth, 1);
        expect(state.selected!.transform[12], 13);
        await state.undo();
        expect(state.selected!.transform[12], 10);
        final pivot = objectPivotWorld(state.selected!);
        state.setManipulatorMode(ManipulatorMode.rotate);
        expect(state.beginManipulator(2), true);
        state.updateManipulator(math.pi / 2);
        await state.endManipulator();
        final after = objectPivotWorld(state.selected!);
        for (var i = 0; i < 3; i++) {
          expect(after[i], closeTo(pivot[i], 1e-9));
        }
        state.setManipulatorMode(ManipulatorMode.pivot);
        expect(state.beginManipulator(0), true);
        state.updateManipulator(4);
        await state.endManipulator(cancel: true);
        expect(objectPivotWorld(state.selected!), after);
        state.dispose();
      });
    },
  );
  testWidgets(
    'sculpt stroke groups dabs and cancelled stroke restores history',
    (tester) async {
      await tester.runAsync(() async {
        final state = makeState();
        state.brushRadius = 1.2;
        state.brushStrength = .1;
        final original = List<double>.from(state.activeMesh!.positions);
        expect(state.beginSculptStroke(), true);
        await state.queueSculptSample(80, 60);
        await state.queueSculptSample(83, 61);
        await state.endSculptStroke();
        expect(state.doc.undoDepth, 1, reason: state.status);
        expect(state.activeMesh!.positions, isNot(equals(original)));
        await state.undo();
        expect(state.activeMesh!.positions, original);
        final depth = state.doc.undoDepth;
        expect(state.beginSculptStroke(), true);
        await state.queueSculptSample(80, 60);
        await state.endSculptStroke(cancel: true);
        expect(state.doc.undoDepth, depth);
        expect(state.activeMesh!.positions, original);
        state.dispose();
      });
    },
  );
  testWidgets(
    'unitless import converts inches once and rejects invalid scale',
    (tester) async {
      await tester.runAsync(() async {
        final state = makeState();
        final dir = await Directory.systemTemp.createTemp('mmx-units-');
        try {
          final obj = File('${dir.path}/inch.obj');
          await obj.writeAsString('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n');
          await state.importPath(obj.path, unitScale: 25.4);
          expect(state.activeMesh!.bounds().extentX, closeTo(25.4, 1e-5));
          final count = state.doc.objects.length;
          await state.importPath(obj.path, unitScale: double.nan);
          expect(state.doc.objects.length, count);
          expect(state.status, contains('Invalid import units'));
          final three = File('${dir.path}/millimeters.3mf');
          await three.writeAsBytes(ThreeMfIO.write(sphere()));
          await state.importPath(three.path, unitScale: 25.4);
          expect(state.activeMesh!.bounds().extentX, closeTo(10, 1e-4));
        } finally {
          state.dispose();
          await dir.delete(recursive: true);
        }
      });
    },
  );
  testWidgets('viewport axis drag changes transform and creates undo', (
    tester,
  ) async {
    late StudioState state;
    await tester.runAsync(() async {
      state = makeState();
      await state.render();
    });
    state.setManipulatorMode(ManipulatorMode.translate);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (context, _) => MeshViewport(state: state),
          ),
        ),
      ),
    );
    await tester.pump();
    final finder = find.byType(MeshViewport);
    final size = tester.getSize(finder), offset = tester.getTopLeft(finder);
    final projection = GizmoProjection.forState(state, size)!;
    final handle = projection.handles[0]!;
    final delta = (handle - projection.origin) * .5;
    final gesture = await tester.startGesture(offset + handle);
    await gesture.moveTo(offset + handle + delta);
    await gesture.up();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(state.doc.undoDepth, 1);
    expect(state.selected!.transform[12], greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
