import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_core/mmx_core.dart';
import 'package:mmx_studio/state/studio_state.dart';
import 'package:mmx_studio/ui/screen.dart';

class SaveState extends StudioState {
  SaveState() : super(loadStartup: false) {
    selectedObjectId = doc.add(TriMesh(Float32List(0), Uint32List(0))).id;
    dirty = true;
  }
  final writes = <String>[];
  @override
  Future<void> render() async {}
  @override
  Future<bool> saveProject(String path) async {
    writes.add(path);
    dirty = false;
    return true;
  }

  @override
  Future<void> exportSelected(String path) async => writes.add(path);
}

void main() {
  for (final export in [false, true]) {
    testWidgets('existing ${export ? 'export' : 'project'} requires Replace', (
      tester,
    ) async {
      late Directory dir;
      late File file;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('mmx-overwrite-');
        file = File('${dir.path}/existing.${export ? 'stl' : 'mmx'}');
        await file.writeAsString('original data');
      });
      addTearDown(() => dir.delete(recursive: true));
      final state = SaveState();
      addTearDown(state.dispose);
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getSavePath' ? file.path : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: StudioScreen(state: state, enableRecovery: false)),
      );
      Future<void> chooseFile() async {
        if (export) {
          await tester.tap(find.byTooltip('Export selected'));
        } else {
          await tester.tap(find.byTooltip('Project'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save project as…'));
        }
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
      }

      await chooseFile();
      expect(find.text('Replace existing file?'), findsOneWidget);
      expect(state.writes, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.writes, isEmpty);
      expect(state.dirty, isTrue);
      await tester.runAsync(() async {
        expect(await file.readAsString(), 'original data');
      });
      await chooseFile();
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(state.writes, [file.path]);
    });
  }
}
