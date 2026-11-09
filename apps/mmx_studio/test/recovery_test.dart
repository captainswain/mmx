import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_studio/state/studio_state.dart';
import 'package:mmx_studio/ui/screen.dart';

class RecoveryTestState extends StudioState {
  RecoveryTestState() : super(loadStartup: false);
  final finishAutosave = Completer<void>();
  int autosaveCount = 0;
  int saveCount = 0;
  @override
  Future<void> render() async {}

  @override
  Future<void> autosave(String path) async {
    if (!dirty) return;
    autosaveCount++;
    await finishAutosave.future;
    await File(path).writeAsString('older unsaved scene');
  }

  @override
  Future<bool> saveProject(String path) async {
    saveCount++;
    dirty = false;
    return true;
  }
}

Future<void> flushFilesystem(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

void main() {
  testWidgets('macOS save shortcut works from the initial viewport focus', (
    tester,
  ) async {
    final state = RecoveryTestState()
      ..dirty = true
      ..projectPath = '/unused/test.mmx';
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: StudioScreen(state: state, enableRecovery: false),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(state.saveCount, 1);
    } finally {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    }
  });

  testWidgets('saving joins an older recovery write before deleting it', (
    tester,
  ) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mmx-recovery-');
    });
    final state = RecoveryTestState()
      ..dirty = true
      ..projectPath = '${dir.path}/saved.mmx';
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StudioScreen(state: state, recoveryDirectory: () async => dir),
        ),
      );
      await flushFilesystem(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(state.autosaveCount, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(state.saveCount, 1);
      state.finishAutosave.complete();
      await flushFilesystem(tester);
      await tester.pump();
      expect(
        await tester.runAsync(() => File('${dir.path}/recovery.mmx').exists()),
        false,
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });

  testWidgets('unreadable recovery stays intact and is never autosaved over', (
    tester,
  ) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mmx-recovery-invalid-');
      await File('${dir.path}/recovery.mmx').writeAsString('corrupt recovery');
    });
    final state = RecoveryTestState();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StudioScreen(state: state, recoveryDirectory: () async => dir),
        ),
      );
      await flushFilesystem(tester);
      await tester.pumpAndSettle();
      expect(find.text('Recover unsaved project?'), findsOneWidget);
      await tester.tap(find.text('Recover'));
      await flushFilesystem(tester);
      await tester.pumpAndSettle();
      expect(state.status, contains('failed'));
      expect(state.dirty, false);
      await tester.pump(const Duration(minutes: 1));
      expect(state.autosaveCount, 0);
      expect(
        await tester.runAsync(
          () => File('${dir.path}/recovery.mmx').readAsString(),
        ),
        'corrupt recovery',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
