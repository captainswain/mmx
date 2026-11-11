import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_studio/state/studio_state.dart';
import 'package:mmx_studio/ui/screen.dart';

void main() {
  testWidgets('desktop controls expose names and actions without tooltips', (
    tester,
  ) async {
    final state = StudioState(loadStartup: false);
    addTearDown(state.dispose);
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: StudioScreen(state: state, enableRecovery: false)),
    );
    for (final label in [
      'Project',
      'Import mesh',
      'Export selected',
      'Navigate',
      'Select',
      'Sculpt',
      'Stamp',
      'Plane Cut',
      'Mirror',
      'Extrude',
      'Separate Shells',
      'Remesh',
      'Reduce',
      'Make Solid',
      'Hollow',
      'Analysis',
      'Supports',
      'Modify',
      'Print / Layout',
      'Wireframe',
      'Print bed',
      'Frame selection',
    ]) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(node.getSemanticsData().label, label);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: '$label must expose an actionable named control',
      );
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    }
    expect(tester.getSemantics(find.bySemanticsLabel('Undo')).label, 'Undo');
    expect(tester.getSemantics(find.bySemanticsLabel('Redo')).label, 'Redo');
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Navigate'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    final sculpt = tester.getSemantics(find.bySemanticsLabel('Sculpt'));
    tester.binding.performSemanticsAction(
      ui.SemanticsActionEvent(
        nodeId: sculpt.id,
        viewId: tester.view.viewId,
        type: SemanticsAction.tap,
      ),
    );
    await tester.pump();
    expect(state.tool, StudioTool.sculpt);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Sculpt'))
          .getSemanticsData()
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    final radius = tester.getSemantics(find.bySemanticsLabel('Size'));
    expect(
      radius.getSemanticsData().hasAction(SemanticsAction.increase),
      isTrue,
    );
    expect(
      radius.getSemanticsData().hasAction(SemanticsAction.decrease),
      isTrue,
    );
    handle.dispose();
  });
}
