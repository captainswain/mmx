import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_studio/state/studio_state.dart';
import 'package:mmx_studio/ui/panels.dart';

/// Frame settlement alone can finish before an isolate releases its edit lock.
Future<void> settleStudioInteraction(
  WidgetTester tester,
  StudioState state,
) async {
  await tester.pump();
  for (var i = 0; i < 500 && state.interactionLocked; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(state.interactionLocked, isFalse, reason: state.status);
  await tester.pumpAndSettle();
}

/// Reach properties through the same affordance used in compact desktop windows.
Future<void> openPropertiesPanel(WidgetTester tester) async {
  final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
  final button = find.byTooltip('Tool properties');
  debugPrint(
    'Properties layout: ${tester.getSize(find.byType(Scaffold)).width} '
    'logical pixels; compact drawer: ${button.evaluate().isNotEmpty}',
  );
  if (button.evaluate().isNotEmpty && !scaffold.isEndDrawerOpen) {
    await tester.tap(button);
    await tester.pumpAndSettle();
  }
  expect(find.byType(PropertiesPanel), findsOneWidget);
}

/// Dismiss the compact drawer through its scrim before viewport pointer input.
Future<void> closePropertiesPanel(WidgetTester tester) async {
  final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
  if (!scaffold.isEndDrawerOpen) return;
  final screen = tester.getRect(find.byType(Scaffold));
  final drawer = tester.getRect(find.byType(Drawer));
  expect(drawer.left, greaterThan(screen.left));
  await tester.tapAt(Offset((screen.left + drawer.left) / 2, screen.center.dy));
  await tester.pumpAndSettle();
  expect(scaffold.isEndDrawerOpen, isFalse);
}
