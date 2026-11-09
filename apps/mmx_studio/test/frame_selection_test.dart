import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_studio/state/studio_state.dart';

List<double> cameraValues(Camera camera) => [
  ...camera.target,
  camera.yaw,
  camera.pitch,
  camera.distance,
  camera.near,
  camera.far,
  camera.fovDegrees,
];

void main() {
  testWidgets('framing an empty Boolean result preserves a savable camera', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('mmx-empty-frame-');
      final state = StudioState(loadStartup: false)
        ..frameWidth = 32
        ..frameHeight = 32;
      try {
        final box = Modify.fitPrimitive(
          TriMesh(Float32List.fromList([-1, -1, -1, 1, 1, 1]), Uint32List(0)),
          PrimitiveKind.box,
        );
        await state.addObject(box, 'first');
        final firstId = state.selectedObjectId!;
        await state.addObject(box.clone(), 'second');
        await state.transformSelected(translation4(10, 0, 0));
        await state.doBoolean(firstId, BooleanOp.intersection);
        expect(state.activeMesh!.faceCount, 0, reason: state.status);
        expect(state.activeMesh!.bounds().isEmpty, true);
        final before = cameraValues(state.camera);
        expect(before.every((value) => value.isFinite), true);

        state.frameSelection();

        expect(cameraValues(state.camera), before);
        final path = '${dir.path}/empty-result.mmx';
        expect(await state.saveProject(path), true, reason: state.status);
        final saved = ProjectIO.read(await File(path).readAsBytes());
        expect(cameraValues(saved.camera), before);
        expect(
          saved.objects
              .firstWhere((o) => o.id == saved.selectedId)
              .mesh
              .faceCount,
          0,
        );
      } finally {
        state.dispose();
        await dir.delete(recursive: true);
      }
    });
  });
}
