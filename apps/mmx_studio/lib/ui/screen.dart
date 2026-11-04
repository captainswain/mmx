import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_state.dart';
import 'panels.dart';
import 'viewport.dart';

class StudioScreen extends StatefulWidget {
  final StudioTool? initialTool;
  const StudioScreen({super.key, this.initialTool});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  final StudioState state = StudioState();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTool;
    if (initial != null) {
      state.setTool(initial);
    }
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final narrow = MediaQuery.sizeOf(context).width < 900;
        return Focus(
          autofocus: true,
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
              ): () =>
                  state.undo(),
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ): () =>
                  state.redo(),
              const SingleActivator(
                LogicalKeyboardKey.keyY,
                control: true,
              ): () =>
                  state.redo(),
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () =>
                  _showImport(context),
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () =>
                  _showExport(context),
            },
            child: Scaffold(
              key: _scaffoldKey,
              endDrawer: narrow
                  ? Drawer(width: 330, child: PropertiesPanel(state: state))
                  : null,
              appBar: AppBar(
                toolbarHeight: 46,
                backgroundColor: const Color(0xFF1B1E22),
                titleSpacing: 12,
                title: Row(
                  children: [
                    const Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: Colors.tealAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'MESH STUDIO',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (state.busy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.status,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: 'Undo',
                    icon: const Icon(Icons.undo, size: 18),
                    onPressed: state.doc.canUndo ? () => state.undo() : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    icon: const Icon(Icons.redo, size: 18),
                    onPressed: state.doc.canRedo ? () => state.redo() : null,
                  ),
                  IconButton(
                    tooltip: 'Import mesh',
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    onPressed: () => _showImport(context),
                  ),
                  IconButton(
                    tooltip: 'Export selected',
                    icon: const Icon(Icons.save_outlined, size: 18),
                    onPressed: () => _showExport(context),
                  ),
                  if (narrow)
                    IconButton(
                      tooltip: 'Tool properties',
                      icon: const Icon(Icons.tune, size: 18),
                      onPressed: () =>
                          _scaffoldKey.currentState?.openEndDrawer(),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;
                  return Row(
                    children: [
                      LeftRail(state: state),
                      Expanded(child: MeshViewport(state: state)),
                      if (!compact) PropertiesPanel(state: state),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showImport(BuildContext context) async {
    const roots = <String>[
      '/data/re/meshmixer/extract/meshmixer/models',
      '/data/mmx',
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import mesh'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: DefaultTabController(
            length: roots.length,
            child: Column(
              children: [
                TabBar(
                  tabs: roots.map((r) => Tab(text: r.split('/').last)).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: roots
                        .map((root) => _FileList(root: root))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected != null) {
      await state.importPath(selected);
    }
  }

  Future<void> _showExport(BuildContext context) async {
    final obj = state.selected;
    if (obj == null) return;
    final controller = TextEditingController(
      text: '/data/mmx/${obj.name.replaceAll(RegExp(r'\.[^.]+$'), '')}_out.stl',
    );
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Path (.stl / .obj / .ply)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (path != null) await state.exportSelected(path);
  }
}

class _FileList extends StatelessWidget {
  final String root;
  const _FileList({required this.root});

  @override
  Widget build(BuildContext context) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      return Center(child: Text('$root not found'));
    }
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.obj') ||
                  f.path.endsWith('.stl') ||
                  f.path.endsWith('.ply') ||
                  f.path.endsWith('.off'),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, i) {
        final f = files[i];
        final size = (f.lengthSync() / 1024).toStringAsFixed(0);
        return ListTile(
          dense: true,
          leading: const Icon(Icons.insert_drive_file_outlined, size: 16),
          title: Text(
            f.path.split('/').last,
            style: const TextStyle(fontSize: 12),
          ),
          subtitle: Text(
            '${f.path.split('/').sublist(0, f.path.split('/').length - 1).join('/')}  ·  $size KB',
            style: const TextStyle(fontSize: 10),
          ),
          onTap: () => Navigator.pop(context, f.path),
        );
      },
    );
  }
}
