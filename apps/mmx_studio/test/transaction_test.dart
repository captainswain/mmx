import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_studio/state/studio_state.dart';

TriMesh triangle() => TriMesh(
  Float32List.fromList([0, 0, 0, 1, 0, 0, 0, 1, 0]),
  Uint32List.fromList([0, 1, 2]),
);

void main() {
  testWidgets('stale completion cannot undo a newer document replacement', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = StudioState(loadStartup: false);
      state.frameWidth = 32;
      state.frameHeight = 32;
      state.selectedObjectId = state.doc.add(triangle()).id;
      final completion = Completer<TriMesh>();
      final pending = state.runOp('delayed', () => completion.future);
      state.doc.replaceObjects([SceneObject(99, 'replacement', triangle())]);
      completion.complete(TriMesh.empty());
      await pending;
      expect(state.doc.objects.single.id, 99);
      expect(state.activeMesh!.faceCount, 1);
      state.dispose();
    });
  });
  testWidgets('cancelled edit and failed edit preserve scene and history', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = StudioState(loadStartup: false);
      state.frameWidth = 32;
      state.frameHeight = 32;
      state.selectedObjectId = state.doc.add(triangle()).id;
      final completion = Completer<TriMesh>();
      final edit = state.runOp('delayed', () => completion.future);
      expect(state.busy, true);
      await state.undo();
      state.cancelOperation();
      completion.complete(TriMesh.empty());
      await edit;
      expect(state.activeMesh!.faceCount, 1);
      expect(state.doc.canUndo, false);
      expect(state.busy, false);
      await state.runOp(
        'fail',
        () async => throw const FormatException('test'),
      );
      expect(state.activeMesh!.faceCount, 1);
      expect(state.busy, false);
      state.dispose();
    });
  });
  testWidgets(
    'save reopen restores objects and failure preserves dirty scene',
    (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('mmx-studio');
        final state = StudioState(loadStartup: false);
        state.frameWidth = 32;
        state.frameHeight = 32;
        try {
          await state.addObject(triangle(), 'first');
          await state.addObject(triangle(), 'second');
          state.selected!.pivot = Pivot.atPoint([1, 2, 3]);
          expect(state.dirty, true);
          expect(
            await state.saveProject('${dir.path}/scene.mmx'),
            true,
            reason: state.status,
          );
          expect(state.dirty, false);
          await state.doFlipNormals();
          expect(state.dirty, true);
          expect(
            await state.openProject('${dir.path}/scene.mmx'),
            true,
            reason: state.status,
          );
          expect(state.doc.objects.length, 2);
          expect(state.selected!.pivot!.position, [1, 2, 3]);
          expect(state.dirty, false);
          await state.doFlipNormals();
          expect(await state.openProject('${dir.path}/missing.mmx'), false);
          expect(state.doc.objects.length, 2);
          expect(state.dirty, true);
        } finally {
          state.dispose();
          await dir.delete(recursive: true);
        }
      });
    },
  );
  testWidgets('undo and redo clear topology dependent selections', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final state = StudioState(loadStartup: false);
      state.frameWidth = 32;
      state.frameHeight = 32;
      await state.addObject(triangle(), 'mesh');
      await state.selectAll();
      await state.doFlipNormals();
      expect(state.selection, isNull);
      await state.selectAll();
      await state.undo();
      expect(state.selection, isNull);
      await state.redo();
      expect(state.selection, isNull);
      state.dispose();
    });
  });
}
