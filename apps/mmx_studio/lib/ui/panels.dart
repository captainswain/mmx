import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mmx_core/mmx_core.dart';

import '../state/studio_state.dart';

/// Left tool rail, mirroring the shipped Meshmixer action bars
/// (Meshmix / Import / Select / Sculpt / Stamp / Edits / Analysis / Shaders /
/// Separate / Export / Print).
class LeftRail extends StatelessWidget {
  final StudioState state;
  const LeftRail({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    const items = <(StudioTool, IconData, String)>[
      (StudioTool.navigate, Icons.pan_tool_alt_outlined, 'Navigate'),
      (StudioTool.select, Icons.highlight_alt, 'Select'),
      (StudioTool.sculpt, Icons.brush_outlined, 'Sculpt'),
      (StudioTool.planeCut, Icons.content_cut, 'Plane Cut'),
      (StudioTool.mirror, Icons.flip, 'Mirror'),
      (StudioTool.extrude, Icons.open_in_full, 'Extrude'),
      (StudioTool.separate, Icons.call_split, 'Separate Shells'),
      (StudioTool.remesh, Icons.grid_on, 'Remesh'),
      (StudioTool.reduce, Icons.compress, 'Reduce'),
      (StudioTool.makeSolid, Icons.hexagon_outlined, 'Make Solid'),
      (StudioTool.hollow, Icons.donut_large, 'Hollow'),
      (StudioTool.analysis, Icons.analytics_outlined, 'Analysis'),
      (StudioTool.supports, Icons.foundation_outlined, 'Supports'),
      (StudioTool.modify, Icons.auto_fix_high, 'Modify'),
      (StudioTool.print, Icons.view_in_ar_outlined, 'Print / Layout'),
    ];
    return Container(
      width: 58,
      color: const Color(0xFF1B1E22),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                    child: Tooltip(
                      message: item.$3,
                      child: Material(
                        color: state.tool == item.$1
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => state.setTool(item.$1),
                          child: SizedBox(
                            height: 40,
                            child: Icon(item.$2,
                                size: 21,
                                color: state.tool == item.$1
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Wireframe',
            icon: Icon(Icons.grid_4x4, color: state.wireframe ? Colors.tealAccent : Colors.white38),
            onPressed: state.toggleWireframe,
          ),
          IconButton(
            tooltip: 'Print bed',
            icon: Icon(Icons.crop_free, color: state.showBed ? Colors.tealAccent : Colors.white38),
            onPressed: state.toggleBed,
          ),
          IconButton(
            tooltip: 'Frame selection',
            icon: const Icon(Icons.center_focus_strong, color: Colors.white54),
            onPressed: state.frameSelection,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Right-hand properties panel. Contents change with the active tool.
class PropertiesPanel extends StatelessWidget {
  final StudioState state;
  const PropertiesPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      color: const Color(0xFF1B1E22),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          _SceneSection(state: state),
          const Divider(height: 26),
          ..._toolSection(context),
        ],
      ),
    );
  }

  List<Widget> _toolSection(BuildContext context) {
    switch (state.tool) {
      case StudioTool.navigate:
        return <Widget>[
          _sectionTitle('View'),
          _kv('Camera', 'orbit / shift-drag pan / scroll zoom'),
          _kv('Objects', '${state.doc.objects.length}'),
          _kv('Undo depth', '${state.doc.undoDepth}'),
          _kv('Memory', '${(state.doc.memoryBytes / 1e6).toStringAsFixed(1)} MB'),
        ];
      case StudioTool.select:
        return <Widget>[
          _sectionTitle('Selection'),
          _slider('Brush radius', state.brushRadius, 0.5, 80,
              (v) => state.brushRadius = v),
          Row(children: [
            _button(context, 'All', state.selectAll),
            _button(context, 'Expand', state.expandSelection),
            _button(context, 'Contract', state.contractSelection),
            _button(context, 'Clear', state.clearSelection),
          ]),
          const SizedBox(height: 8),
          _kv('Selected faces', '${state.selection?.count ?? 0}'),
          const SizedBox(height: 8),
          _sectionTitle('Selection actions'),
          Row(children: [
            _button(context, 'Discard', _discardSelection),
            _button(context, 'Remesh', state.doRemesh),
            _button(context, 'Reduce', state.doReduce),
          ]),
          Row(children: [
            _button(context, 'Extract', _extractSelection),
            _button(context, 'Smooth', _smoothSelection),
          ]),
        ];
      case StudioTool.sculpt:
        return <Widget>[
          _sectionTitle('Brush'),
          DropdownButtonFormField<BrushOp>(
            initialValue: state.brushOp,
            decoration: const InputDecoration(labelText: 'Type', isDense: true),
            items: BrushOp.values
                .map((op) => DropdownMenuItem(value: op, child: Text(op.name)))
                .toList(),
            onChanged: (v) => state.brushOp = v ?? BrushOp.draw,
          ),
          const SizedBox(height: 8),
          _slider('Size', state.brushRadius, 0.5, 80, (v) => state.brushRadius = v),
          _slider('Strength', state.brushStrength, 0.02, 1.0, (v) => state.brushStrength = v),
          _kv('Secondary (right drag)', 'smooth'),
          const SizedBox(height: 6),
          const Text(
            'Left-drag on the surface to sculpt. Dynamic refinement splits '
            'edges inside the brush as you go.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ];
      case StudioTool.planeCut:
        return <Widget>[
          _sectionTitle('Plane Cut'),
          _slider('Offset', state.planeOffset, -50, 50, (v) => state.planeOffset = v),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Fill cut', style: TextStyle(fontSize: 13)),
            value: state.planeFill,
            onChanged: (v) => state.planeFill = v,
          ),
          const SizedBox(height: 6),
          _button(context, 'Cut (discard top)', state.doPlaneCut),
        ];
      case StudioTool.mirror:
        return <Widget>[
          _sectionTitle('Mirror'),
          _slider('Plane offset X', state.mirrorPlaneOffset, -60, 60,
              (v) => state.mirrorPlaneOffset = v),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep original', style: TextStyle(fontSize: 13)),
            value: state.mirrorKeepOriginal,
            onChanged: (v) {
              state.mirrorKeepOriginal = v;
              state.notify();
            },
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Weld seam', style: TextStyle(fontSize: 13)),
            value: state.mirrorWeld,
            onChanged: (v) {
              state.mirrorWeld = v;
              state.notify();
            },
          ),
          const SizedBox(height: 6),
          _button(context, 'Mirror', state.doMirror),
        ];
      case StudioTool.extrude:
        return <Widget>[
          _sectionTitle('Extrude'),
          _slider('Distance', state.extrudeDistance, 0.5, 40,
              (v) => state.extrudeDistance = v),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Smooth boundary', style: TextStyle(fontSize: 13)),
            value: state.extrudeSmooth,
            onChanged: (v) {
              state.extrudeSmooth = v;
              state.notify();
            },
          ),
          const SizedBox(height: 6),
          _kv('Selected faces', '${state.selection?.count ?? 0}'),
          const SizedBox(height: 6),
          _button(context, 'Extrude selection', state.doExtrude),
          const SizedBox(height: 8),
          const Text(
            'Select a region first (Select tool), then extrude it along the '
            'surface normal. A skirt is built from the selection boundary.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ];
      case StudioTool.separate:
        return <Widget>[
          _sectionTitle('Separate Shells'),
          _kv('Objects', '${state.doc.objects.length}'),
          _kv('Shells in selection', '${state.shellCount}'),
          const SizedBox(height: 8),
          _button(context, 'Separate shells', state.doSeparateShells),
          const SizedBox(height: 8),
          const Text(
            'Splits every disconnected shell into its own scene object, '
            'largest first.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ];
      case StudioTool.remesh:
        return <Widget>[
          _sectionTitle('Remesh'),
          _slider('Density', state.remeshDensity, 0.05, 1.0, (v) => state.remeshDensity = v),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Preserve group boundaries',
                style: TextStyle(fontSize: 13)),
            value: state.remeshGroupAware,
            onChanged: (v) {
              state.remeshGroupAware = v;
              state.notify();
            },
          ),
          const SizedBox(height: 6),
          const Text(
            'Isotropic remeshing: split long edges, collapse short ones, '
            'flip to valence six, relax tangentially and reproject. With '
            'group boundaries on, the remesher pins internal group seams '
            '(VariationalRemesher behaviour).',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _button(context, 'Face groups', state.doGenerateFaceGroups),
            _button(context, 'Remesh',
                () => state.doRemesh(groupAware: state.remeshGroupAware)),
          ]),
        ];
      case StudioTool.reduce:
        return <Widget>[
          _sectionTitle('Reduce'),
          _slider('Keep fraction', state.reducePercent, 0.02, 0.95,
              (v) => state.reducePercent = v),
          _kv('Target faces',
              '${(state.activeMesh?.faceCount ?? 0) * state.reducePercent ~/ 1}'),
          const SizedBox(height: 8),
          _button(context, 'Reduce', state.doReduce),
        ];
      case StudioTool.makeSolid:
        return <Widget>[
          _sectionTitle('Make Solid'),
          DropdownButtonFormField<SolidMode>(
            initialValue: state.solidMode,
            decoration: const InputDecoration(labelText: 'Routine', isDense: true),
            items: SolidMode.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.name)))
                .toList(),
            onChanged: (v) => state.solidMode = v ?? SolidMode.accurate,
          ),
          _slider('Grid resolution', state.solidResolution, 32, 256,
              (v) => state.solidResolution = v),
          _slider('Offset', state.solidOffset, -20, 20, (v) => state.solidOffset = v),
          _slider('Smoothing', state.solidSmoothing.toDouble(), 0, 8,
              (v) => state.solidSmoothing = v.round()),
          const SizedBox(height: 8),
          _button(context, 'Make Solid', state.doMakeSolid),
        ];
      case StudioTool.hollow:
        return <Widget>[
          _sectionTitle('Hollow'),
          _slider('Wall thickness', state.hollowThickness, 0.4, 20,
              (v) => state.hollowThickness = v),
          _slider('Escape holes', state.hollowHoles.toDouble(), 0, 8,
              (v) => state.hollowHoles = v.round()),
          _slider('Grid resolution', state.solidResolution, 32, 256,
              (v) => state.solidResolution = v),
          const SizedBox(height: 8),
          _button(context, 'Hollow', state.doHollow),
        ];
      case StudioTool.modify:
        return <Widget>[
          _sectionTitle('Surface'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _button(context, 'Flip normals', state.doFlipNormals),
            _button(context, 'Smooth', state.doSmoothMesh),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Flip normals honours the current face selection; Smooth is '
            'Taubin (volume preserving) over the whole mesh.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
          const SizedBox(height: 10),
          _sectionTitle('Placement'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _button(context, 'Drop to bed', state.doDropToBed),
            _button(context, 'Center on bed', state.doCenterOnBed),
          ]),
          const SizedBox(height: 10),
          _sectionTitle('Object'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _button(context, 'Duplicate', state.doDuplicate),
            _button(context, 'Combine all', state.doCombineAll),
          ]),
          const SizedBox(height: 8),
          _slider('Pattern columns', state.patternCountX.toDouble(), 1, 8,
              (v) => state.patternCountX = v.round()),
          _slider('Pattern rows', state.patternCountZ.toDouble(), 1, 8,
              (v) => state.patternCountZ = v.round()),
          _slider('Pattern gap', state.patternGap, 0.5, 20,
              (v) => state.patternGap = v),
          _button(context, 'Make pattern', state.doMakePattern),
          const SizedBox(height: 10),
          _sectionTitle('Primitive'),
          DropdownButtonFormField<PrimitiveKind>(
            initialValue: state.primitiveKind,
            decoration: const InputDecoration(labelText: 'Fit', isDense: true),
            items: PrimitiveKind.values
                .map((k) => DropdownMenuItem(value: k, child: Text(k.name)))
                .toList(),
            onChanged: (v) {
              state.primitiveKind = v ?? PrimitiveKind.box;
              state.notify();
            },
          ),
          const SizedBox(height: 4),
          _button(context, 'Replace with primitive', state.doFitPrimitive),
          const SizedBox(height: 10),
          _sectionTitle('Measure'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _button(context, 'Measure', state.doMeasure),
            _button(context, 'Clearance', state.doClearance),
          ]),
        ];
      case StudioTool.analysis:
        return <Widget>[
          _sectionTitle('Analysis'),
          _slider('Thickness threshold', state.thicknessThreshold, 0.1, 20,
              (v) => state.thicknessThreshold = v),
          _slider('Overhang angle', state.overhangAngle, 10, 80,
              (v) => state.overhangAngle = v),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _button(context, 'Thickness', () => state.doAnalysis(AnalysisOverlay.thickness)),
            _button(context, 'Overhang', () => state.doAnalysis(AnalysisOverlay.overhang)),
            _button(context, 'Stability', () => state.doAnalysis(AnalysisOverlay.stability)),
            _button(context, 'Clear', () => state.doAnalysis(AnalysisOverlay.none)),
          ]),
          const SizedBox(height: 10),
          _sectionTitle('Repair'),
          Row(children: [
            _button(context, 'Inspector', state.inspectMesh),
            _button(context, 'Auto repair', state.autoRepair),
          ]),
        ];
      case StudioTool.supports:
        return <Widget>[
          _sectionTitle('Supports'),
          _slider('Overhang angle', state.supportAngle, 10, 80,
              (v) => state.supportAngle = v),
          _slider('Density', state.supportDensity, 0.05, 1.0,
              (v) => state.supportDensity = v),
          const SizedBox(height: 8),
          _button(context, 'Generate support forest', state.doSupports),
          const SizedBox(height: 8),
          const Text(
            'Tapered posts with base discs plus struts that respect the '
            'maximum strut angle. Generated as a separate object.',
            style: TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ];
      case StudioTool.print:
        return <Widget>[
          _sectionTitle('Print / Layout'),
          _kv('Bed', '200 x 200 mm'),
          const SizedBox(height: 6),
          _button(context, 'Pack objects on bed', _packAll),
          const SizedBox(height: 6),
          _button(context, 'Slice report', _sliceReport),
        ];
    }
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: Colors.white60)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _slider(String label, double value, double min, double max,
      void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 12)),
        ]),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (v) {
            onChanged(v);
            state.notify();
          },
        ),
      ],
    );
  }

  Widget _button(BuildContext context, String label, Future<void> Function() fn) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          textStyle: const TextStyle(fontSize: 11),
        ),
        onPressed: state.busy ? null : () => fn(),
        child: Text(label),
      ),
    );
  }

  Future<void> _discardSelection() async {
    final obj = state.selected;
    final sel = state.selection;
    if (obj == null || sel == null) return;
    final mesh = obj.mesh;
    final mask = sel.faceMask;
    await state.runOp('Discard selection', () async {
      final keep = <int>[];
      for (var f = 0; f < mesh.faceCount; f++) {
        if (mask[f] != 0) continue;
        keep.addAll(<int>[
          mesh.indices[f * 3],
          mesh.indices[f * 3 + 1],
          mesh.indices[f * 3 + 2],
        ]);
      }
      final out = TriMesh(mesh.positions, Uint32List.fromList(keep));
      out.compact();
      return out;
    });
  }

  Future<void> _extractSelection() async {
    final obj = state.selected;
    final sel = state.selection;
    if (obj == null || sel == null) return;
    final mesh = obj.mesh;
    final mask = sel.faceMask;
    final builder = MeshBuilder();
    final map = <int, int>{};
    for (var f = 0; f < mesh.faceCount; f++) {
      if (mask[f] == 0) continue;
      final ids = <int>[];
      for (var k = 0; k < 3; k++) {
        final v = mesh.indices[f * 3 + k];
        ids.add(map.putIfAbsent(
            v, () => builder.addVertex(mesh.vx(v), mesh.vy(v), mesh.vz(v))));
      }
      builder.addTriangle(ids[0], ids[1], ids[2]);
    }
    if (builder.faceCount == 0) return;
    await state.addObject(builder.build(), 'Extracted region');
  }

  Future<void> _smoothSelection() async {
    final obj = state.selected;
    final sel = state.selection;
    if (obj == null || sel == null) return;
    final mesh = obj.mesh;
    final mask = sel.faceMask;
    await state.runOp('Smooth selection', () async {
      var m = mesh.clone();
      for (var i = 0; i < 12; i++) {
        final topo = MeshTopology(m);
        final next = Float32List.fromList(m.positions);
        for (var v = 0; v < m.vertexCount; v++) {
          var inside = false;
          for (final f in topo.facesOfVertex(v)) {
            if (f < mask.length && mask[f] != 0) {
              inside = true;
              break;
            }
          }
          if (!inside) continue;
          final nb = topo.neighborsOfVertex(v);
          if (nb.isEmpty) continue;
          var sx = 0.0, sy = 0.0, sz = 0.0;
          for (final w in nb) {
            sx += m.vx(w);
            sy += m.vy(w);
            sz += m.vz(w);
          }
          final k = nb.length;
          next[v * 3] = 0.5 * m.vx(v) + 0.5 * sx / k;
          next[v * 3 + 1] = 0.5 * m.vy(v) + 0.5 * sy / k;
          next[v * 3 + 2] = 0.5 * m.vz(v) + 0.5 * sz / k;
        }
        m.positions = next;
      }
      return m;
    });
  }

  Future<void> _packAll() async {
    final meshes = state.doc.objects.map((o) => o.worldMesh()).toList();
    if (meshes.isEmpty) return;
    final result = Packer.pack(meshes, bedWidth: 200, bedDepth: 200, quality: 1);
    for (var i = 0; i < result.placed.length; i++) {
      final p = result.placed[i];
      final obj = state.doc.objects[p.index];
      obj.transform = Float64List.fromList(p.transform);
    }
    state.status = 'Packed ${result.placed.length} objects '
        '(${(result.bedUtilization * 100).toStringAsFixed(1)}% bed use)';
    await state.render();
  }

  Future<void> _sliceReport() async {
    final obj = state.selected;
    if (obj == null) return;
    final r = Slicer.slice(obj.worldMesh(), layerHeight: 0.2);
    state.status = 'Slicing: ${r.layers.length} layers at 0.2mm '
        '(${r.elapsedMs} ms)';
    state.notify();
  }
}

class _SceneSection extends StatelessWidget {
  final StudioState state;
  const _SceneSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('OBJECTS',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        const SizedBox(height: 6),
        for (final o in state.doc.objects)
          InkWell(
            onTap: () {
              state.selectedObjectId = o.id;
              state.selection = null;
              state.notify();
              state.render();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 3),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: o.id == state.selectedObjectId
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                      o.id == state.selectedObjectId
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 14,
                      color: Colors.white54),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(o.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  Text('${o.mesh.faceCount}',
                      style: const TextStyle(fontSize: 10, color: Colors.white38)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
