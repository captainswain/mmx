import 'package:flutter/material.dart';

import 'state/studio_state.dart';
import 'ui/screen.dart';

/// Optional `--tool=<name>` argument so a build can be launched straight into
/// a tool panel (used for screenshots and smoke checks).
void main(List<String> args) {
  StudioTool? initial;
  for (final arg in args) {
    if (!arg.startsWith('--tool=')) continue;
    final name = arg.substring('--tool='.length);
    for (final t in StudioTool.values) {
      if (t.name == name) initial = t;
    }
  }
  runApp(MmxStudioApp(initialTool: initial));
}

class MmxStudioApp extends StatelessWidget {
  final StudioTool? initialTool;
  const MmxStudioApp({super.key, this.initialTool});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D6F),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Mesh Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: base,
        scaffoldBackgroundColor: const Color(0xFF16181B),
        sliderTheme: const SliderThemeData(
          trackHeight: 2,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
      ),
      home: StudioScreen(initialTool: initialTool),
    );
  }
}
