import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mmx_core/mmx_core.dart';

enum StudioTool {
  navigate,
  select,
  sculpt,
  stamp,
  planeCut,
  mirror,
  extrude,
  separate,
  remesh,
  reduce,
  makeSolid,
  hollow,
  supports,
  modify,
  analysis,
  print,
}

enum AnalysisOverlay { none, thickness, overhang, stability, deviation }

/// Application state: document, camera, active tool parameters, viewport
/// image, and the operator plumbing that runs heavy kernels off the UI thread.
class StudioState extends ChangeNotifier {
  final Document doc = Document();
  Camera camera = Camera(yaw: 0.7, pitch: 0.3, distance: 3);
  StudioTool tool = StudioTool.navigate;
  AnalysisOverlay overlay = AnalysisOverlay.none;
  bool wireframe = false;
  bool showBed = true;
  bool busy = false;
  bool _disposed = false;
  String status = 'Ready';

  int? selectedObjectId;
  int shellCount = 0;
  Selection? selection;
  Uint8List? overlayColors;

  ui.Image? frame;
  int frameWidth = 900;
  int frameHeight = 640;
  bool _renderQueued = false;
  int lastRenderMs = 0;

  // Tool parameters (mirrors Meshmixer panel ranges).
  double brushRadius = 8;
  double brushStrength = 0.5;
  BrushOp brushOp = BrushOp.draw;
  StampPattern stampPattern = StampPattern.circle;
  double stampRadius = 8;
  double stampHeight = 2;
  double remeshDensity = 0.5;
  double reducePercent = 0.5;
  double solidResolution = 128;
  SolidMode solidMode = SolidMode.accurate;
  double solidOffset = 0;
  int solidSmoothing = 0;
  double hollowThickness = 2;
  int hollowHoles = 3;
  double supportAngle = 45;
  double supportDensity = 0.5;
  double thicknessThreshold = 1.0;
  double overhangAngle = 45;
  double planeOffset = 0;
  bool planeFill = true;
  double mirrorPlaneOffset = 0;
  bool mirrorKeepOriginal = true;
  bool mirrorWeld = true;
  double extrudeDistance = 5;
  bool extrudeSmooth = true;
  int patternCountX = 3;
  int patternCountZ = 2;
  double patternGap = 2;
  PrimitiveKind primitiveKind = PrimitiveKind.box;
  bool remeshGroupAware = false;

  StudioState() {
    _loadStartupModel();
  }

  SceneObject? get selected {
    final id = selectedObjectId;
    if (id == null) return null;
    return doc.byId(id);
  }

  TriMesh? get activeMesh => selected?.mesh;

  Future<void> _loadStartupModel() async {
    final candidates = <String>[
      '/data/re/meshmixer/extract/meshmixer/models/bunnyr.obj',
      '/data/re/meshmixer/extract/meshmixer/models/dog.obj',
    ];
    for (final path in candidates) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final mesh = MeshIO.readBytes(path, f.readAsBytesSync());
      _install(mesh, path.split('/').last);
      await render();
      return;
    }
    // Bundled fallback so the app is self-contained on any machine.
    try {
      final data = await rootBundle.load('assets/models/bunnyr.obj');
      final mesh = MeshIO.readBytes('bunnyr.obj', data.buffer.asUint8List());
      _install(mesh, 'bunnyr.obj (bundled)');
    } catch (e) {
      status = 'No model loaded: $e';
    }
    await render();
  }

  void _install(TriMesh mesh, String name) {
    final obj = doc.add(mesh, name: name);
    selectedObjectId = obj.id;
    _frameObject(obj);
    status = 'Loaded ${obj.name}: ${mesh.faceCount} faces';
  }

  void _frameObject(SceneObject obj) {
    final b = obj.worldBounds();
    camera.frame(b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ);
  }

  // ---------------------------------------------------------------- camera
  void orbit(double dx, double dy) {
    camera.orbit(-dx * 0.006, dy * 0.006);
    _scheduleRender();
  }

  void pan(double dx, double dy) {
    camera.pan(dx, dy);
    _scheduleRender();
  }

  void zoom(double delta) {
    camera.zoom(delta > 0 ? 0.92 : 1.08);
    _scheduleRender();
  }

  void frameSelection() {
    final obj = selected;
    if (obj == null) return;
    _frameObject(obj);
    _scheduleRender();
  }

  // ----------------------------------------------------------------- render
  void _scheduleRender() {
    if (_renderQueued) return;
    _renderQueued = true;
    Future<void>.microtask(() async {
      _renderQueued = false;
      await render();
    });
  }

  Future<void> render() async {
    final objects = <RenderObject>[];
    for (final o in doc.objects) {
      if (!o.visible) continue;
      final mask = (o.id == selectedObjectId && selection != null)
          ? selection!.faceMask
          : null;
      Float32List? colors;
      if (o.id == selectedObjectId &&
          overlay != AnalysisOverlay.none &&
          overlayColors != null) {
        colors = _expandFaceColors(o.mesh, overlayColors!);
      }
      objects.add(
        RenderObject(
          o.mesh,
          transform: o.transform,
          color: _materialColor(o),
          faceMask: mask,
          faceColors: colors,
        ),
      );
    }
    final opts = RenderOptions(
      width: frameWidth,
      height: frameHeight,
      wireframe: wireframe,
      showBed: showBed,
      bedSize: 200,
      background: const <double>[0.086, 0.094, 0.11],
    );
    final sw = Stopwatch()..start();
    final rgba = Rasterizer.render(objects, camera, opts);
    sw.stop();
    lastRenderMs = sw.elapsedMilliseconds;
    final img = await _decode(rgba, frameWidth, frameHeight);
    if (_disposed) {
      img.dispose();
      return;
    }
    frame?.dispose();
    frame = img;
    notify();
  }

  static Future<ui.Image> _decode(Uint8List rgba, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static List<double> _materialColor(SceneObject o) {
    const palette = <List<double>>[
      <double>[0.76, 0.70, 0.60],
      <double>[0.55, 0.66, 0.76],
      <double>[0.72, 0.58, 0.55],
      <double>[0.60, 0.74, 0.62],
    ];
    return palette[o.id % palette.length];
  }

  /// Expands per-vertex analysis values into per-face RGB.
  static Float32List _expandFaceColors(TriMesh mesh, Uint8List perVertex) {
    final out = Float32List(mesh.faceCount * 3);
    for (var f = 0; f < mesh.faceCount; f++) {
      var v = 0;
      for (var k = 0; k < 3; k++) {
        v = mathMax(v, perVertex[mesh.indices[f * 3 + k]]);
      }
      final t = v / 255.0;
      // Blue (safe) -> yellow -> red (bad)
      final r = (t < 0.5 ? t * 2 : 1.0);
      final g = (t < 0.5 ? 0.6 + t * 0.8 : 1.0 - (t - 0.5) * 1.6);
      final b = (t < 0.5 ? 1.0 - t * 1.6 : 0.2);
      out[f * 3] = r;
      out[f * 3 + 1] = g;
      out[f * 3 + 2] = b;
    }
    return out;
  }

  // ------------------------------------------------------------- selection
  Future<void> pickAndSelect(double sx, double sy) async {
    final obj = selected;
    if (obj == null) return;
    final ray = camera.screenToRay(
      sx,
      sy,
      frameWidth.toDouble(),
      frameHeight.toDouble(),
    );
    final bvh = TriangleBVH.build(obj.worldMesh());
    final hit = bvh.raycast(ray.origin, ray.direction);
    if (hit == null) {
      status = 'No surface under cursor';
      notify();
      return;
    }
    final world = obj.worldMesh();
    final sel = Selection.sphereBrush(world, hit.point, brushRadius);
    selection = sel;
    status = 'Selected ${sel.count} faces';
    await render();
  }

  Future<void> selectAll() async {
    final obj = selected;
    if (obj == null) return;
    selection = Selection(
      Uint8List(obj.mesh.faceCount)..fillRange(0, obj.mesh.faceCount, 1),
      obj.mesh.faceCount,
    );
    await render();
  }

  Future<void> expandSelection() async {
    final obj = selected;
    if (obj == null || selection == null) return;
    selection!.expand(obj.mesh);
    await render();
  }

  Future<void> contractSelection() async {
    final obj = selected;
    if (obj == null || selection == null) return;
    selection!.contract(obj.mesh);
    await render();
  }

  Future<void> clearSelection() async {
    selection = null;
    await render();
  }

  // --------------------------------------------------------------- sculpt
  Future<void> sculptAt(double sx, double sy, {bool secondary = false}) async {
    final obj = selected;
    if (obj == null) return;
    final ray = camera.screenToRay(
      sx,
      sy,
      frameWidth.toDouble(),
      frameHeight.toDouble(),
    );
    final bvh = TriangleBVH.build(obj.mesh);
    final hit = bvh.raycast(ray.origin, ray.direction);
    if (hit == null) return;
    final op = secondary ? BrushOp.smooth : brushOp;
    final center = hit.point;
    final radius = brushRadius;
    final strength = brushStrength;
    final dir = ray.direction;
    doc.snapshot('Sculpt ${op.name}');
    final mesh = obj.mesh;
    final result = await Isolate.run(
      () => Sculptor.apply(
        mesh,
        op: op,
        center: center,
        radius: radius,
        strength: strength,
        direction: <double>[-dir[0], -dir[1], -dir[2]],
        refine: true,
      ),
    );
    obj.mesh = result;
    status = 'Sculpted (${result.faceCount} faces)';
    await render();
  }

  // ------------------------------------------------------------ operations
  Future<void> runOp(String label, Future<TriMesh> Function() fn) async {
    final obj = selected;
    if (obj == null) return;
    busy = true;
    status = '$label...';
    notify();
    try {
      final sw = Stopwatch()..start();
      final result = await fn();
      sw.stop();
      doc.snapshot(label);
      obj.mesh = result;
      selection = null;
      overlay = AnalysisOverlay.none;
      overlayColors = null;
      refreshShellCount();
      status =
          '$label done in ${sw.elapsedMilliseconds} ms '
          '(${result.vertexCount} verts, ${result.faceCount} faces)';
    } catch (e) {
      status = '$label failed: $e';
    } finally {
      busy = false;
      await render();
    }
  }

  Future<void> doRemesh({bool groupAware = false}) async {
    final obj = selected;
    if (obj == null) return;
    final target = obj.mesh.bounds().diagonal * (0.02 + remeshDensity * 0.06);
    final mesh = obj.mesh;
    final preserveGroups = groupAware && mesh.faceGroups != null;
    await runOp(
      'Remesh',
      () => Isolate.run(
        () => IsotropicRemesher.remesh(
          mesh,
          targetEdgeLength: target,
          iterations: 5,
          preserveGroupBoundaries: preserveGroups,
        ),
      ),
    );
  }

  Future<void> doReduce() async {
    final obj = selected;
    if (obj == null) return;
    final pct = reducePercent;
    final mesh = obj.mesh;
    await runOp(
      'Reduce',
      () => Isolate.run(() => Decimator.reduce(mesh, percentage: pct)),
    );
  }

  Future<void> doMakeSolid() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final res = solidResolution.toInt();
    final mode = solidMode;
    final offset = solidOffset;
    final smooth = solidSmoothing;
    await runOp(
      'Make Solid',
      () => Isolate.run(
        () => Solidifier.makeSolid(
          mesh,
          mode: mode,
          resolution: res,
          offset: offset,
          smoothing: smooth,
        ).mesh,
      ),
    );
  }

  Future<void> doHollow() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final t = hollowThickness;
    final holes = hollowHoles;
    final res = solidResolution.toInt();
    await runOp(
      'Hollow',
      () => Isolate.run(
        () => Solidifier.hollow(
          mesh,
          thickness: t,
          holes: holes,
          holeRadius: t * 1.2,
          resolution: res,
        ).mesh,
      ),
    );
  }

  Future<void> doPlaneCut() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final b = mesh.bounds();
    final y = (b.minY + b.maxY) / 2 + planeOffset;
    final fill = planeFill;
    await runOp(
      'Plane Cut',
      () => Isolate.run(
        () => PlaneCut.cut(
          mesh,
          point: <double>[0, y, 0],
          normal: <double>[0, 1, 0],
          keepPositive: true,
          fill: fill,
        ),
      ),
    );
  }

  Future<void> doMirror() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final offset = mirrorPlaneOffset;
    final keep = mirrorKeepOriginal;
    final weld = mirrorWeld;
    final diag = mesh.bounds().diagonal;
    await runOp(
      'Mirror',
      () => Isolate.run(
        () => Mirror.mirror(
          mesh,
          point: <double>[offset, 0, 0],
          normal: <double>[1, 0, 0],
          keepOriginal: keep,
          weldTolerance: weld ? diag * 1e-4 : 0,
        ),
      ),
    );
  }

  Future<void> doExtrude() async {
    final obj = selected;
    if (obj == null) return;
    final sel = selection;
    if (sel == null || sel.count == 0) {
      status = 'Extrude needs a face selection';
      notify();
      return;
    }
    final mesh = obj.mesh;
    final mask = sel.faceMask;
    final distance = extrudeDistance;
    final smooth = extrudeSmooth;
    await runOp(
      'Extrude',
      () => Isolate.run(
        () => Extruder.extrude(
          mesh,
          faceMask: mask,
          distance: distance,
          smoothBoundary: smooth,
        ),
      ),
    );
  }

  Future<void> doSeparateShells() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final shells = await Isolate.run(() => ShellSeparator.separate(mesh));
    if (shells.length <= 1) {
      status = 'Single shell, nothing to separate';
      notify();
      return;
    }
    doc.snapshot('Separate shells');
    obj.mesh = shells.first;
    for (var i = 1; i < shells.length; i++) {
      doc.add(shells[i], name: '${obj.name} shell ${i + 1}');
    }
    status = 'Separated into ${shells.length} shells';
    selection = null;
    await render();
  }

  // ------------------------------------------------------- remaining edits
  Future<void> doStamp() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final mask = selection?.faceMask;
    final pattern = stampPattern;
    final radius = stampRadius;
    final height = stampHeight;
    await runOp(
      'Stamp',
      () => Isolate.run(() {
        var cx = 0.0, cy = 0.0, cz = 0.0;
        var n = 0;
        if (mask != null) {
          for (var f = 0; f < mesh.faceCount; f++) {
            if (f >= mask.length || mask[f] == 0) continue;
            for (var k = 0; k < 3; k++) {
              final v = mesh.indices[f * 3 + k];
              cx += mesh.vx(v);
              cy += mesh.vy(v);
              cz += mesh.vz(v);
              n++;
            }
          }
        }
        if (n == 0) {
          var best = 0;
          for (var v = 1; v < mesh.vertexCount; v++) {
            if (mesh.vy(v) > mesh.vy(best)) best = v;
          }
          cx = mesh.vx(best);
          cy = mesh.vy(best);
          cz = mesh.vz(best);
          n = 1;
        }
        return StampTool.apply(
          mesh,
          center: <double>[cx / n, cy / n, cz / n],
          radius: radius,
          height: height,
          pattern: pattern,
        );
      }),
    );
  }

  Future<void> doFlipNormals() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final mask = selection?.faceMask;
    await runOp(
      'Flip normals',
      () => Isolate.run(() => Modify.flipNormals(mesh, faceMask: mask)),
    );
  }

  Future<void> doSmoothMesh() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    await runOp(
      'Smooth',
      () => Isolate.run(() => Modify.smooth(mesh, iterations: 8)),
    );
  }

  Future<void> doDropToBed() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    await runOp('Drop to bed', () => Isolate.run(() => Modify.dropToBed(mesh)));
  }

  Future<void> doCenterOnBed() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    await runOp(
      'Center on bed',
      () => Isolate.run(() => Modify.centerOnBed(mesh)),
    );
  }

  Future<void> doDuplicate() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final offset = mesh.bounds().extentX + 2;
    final copy = await Isolate.run(
      () => Modify.duplicate(mesh, offset: <double>[offset, 0, 0]),
    );
    doc.snapshot('Duplicate');
    final added = doc.add(copy, name: '${obj.name} copy');
    selectedObjectId = added.id;
    selection = null;
    status = 'Duplicated ${obj.name}';
    await render();
  }

  Future<void> doCombineAll() async {
    final obj = selected;
    if (obj == null || doc.objects.length < 2) {
      status = 'Combine needs at least two objects';
      notify();
      return;
    }
    final sources = doc.objects.map((o) => o.worldMesh()).toList();
    final combined = await Isolate.run(() => Modify.combine(sources));
    doc.snapshot('Combine');
    obj.mesh = combined;
    obj.transform = identity4();
    for (final other in doc.objects.toList()) {
      if (other.id != obj.id) doc.remove(other.id);
    }
    selection = null;
    refreshShellCount();
    status = 'Combined ${sources.length} objects into ${obj.name}';
    await render();
  }

  Future<void> doMakePattern() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final cx = patternCountX;
    final cz = patternCountZ;
    final gap = patternGap;
    await runOp(
      'Pattern',
      () => Isolate.run(
        () => Modify.makePattern(mesh, countX: cx, countZ: cz, gap: gap),
      ),
    );
  }

  Future<void> doFitPrimitive() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    final kind = primitiveKind;
    await runOp(
      'Fit primitive',
      () => Isolate.run(() => Modify.fitPrimitive(mesh, kind)),
    );
  }

  Future<void> doGenerateFaceGroups() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    await runOp(
      'Generate face groups',
      () => Isolate.run(() {
        final m = mesh.clone();
        m.faceGroups = FaceGroups.generate(m);
        return m;
      }),
    );
  }

  Future<void> doMeasure() async {
    final obj = selected;
    if (obj == null) return;
    busy = true;
    notify();
    final mesh = obj.mesh;
    final r = await Isolate.run(() => Modify.measure(mesh));
    final d = r.dimensions.map((v) => v.toStringAsFixed(2)).join(' x ');
    status =
        'Measure: $d | area ${r.surfaceArea.toStringAsFixed(1)} | '
        'volume ${r.volume.toStringAsFixed(1)} | ${r.shellCount} shell(s) | '
        '${r.watertight ? "watertight" : "${r.boundaryEdgeCount} boundary edges"}';
    busy = false;
    notify();
  }

  Future<void> doClearance() async {
    final obj = selected;
    if (obj == null) return;
    SceneObject? other;
    for (final o in doc.objects) {
      if (o.id != obj.id) {
        other = o;
        break;
      }
    }
    if (other == null) {
      status = 'Clearance needs a second object';
      notify();
      return;
    }
    busy = true;
    notify();
    final a = obj.worldMesh();
    final b = other.worldMesh();
    final gap = await Isolate.run(() => Modify.clearance(a, b));
    status = gap.isFinite
        ? 'Clearance ${obj.name} / ${other.name}: ${gap.toStringAsFixed(2)}'
        : 'Clearance: no surface found';
    busy = false;
    notify();
  }

  Future<void> doStitchCracks() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    await runOp(
      'Stitch cracks',
      () => Isolate.run(() => Bridge.stitchNearest(mesh)),
    );
  }

  Future<void> doAlignToTarget() async {
    final obj = selected;
    if (obj == null) return;
    SceneObject? target;
    for (final o in doc.objects) {
      if (o.id != obj.id) {
        target = o;
        break;
      }
    }
    if (target == null) {
      status = 'Align needs a second object';
      notify();
      return;
    }
    busy = true;
    notify();
    final source = obj.worldMesh();
    final targetMesh = target.worldMesh();
    final t = await Isolate.run(
      () => AlignTool.solve(source, targetMesh, iterations: 40),
    );
    final aligned = obj.worldMesh();
    aligned.transform(t);
    doc.snapshot('Align to target');
    obj.mesh = aligned;
    obj.transform = identity4();
    final rms = await Isolate.run(
      () => AlignTool.rmsDistance(obj.mesh, targetMesh),
    );
    selection = null;
    busy = false;
    status =
        'Aligned ${obj.name} to ${target.name} '
        '(RMS ${rms.toStringAsFixed(2)} mm)';
    await render();
  }

  Future<void> doSupports() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.worldMesh();
    final angle = supportAngle;
    final density = supportDensity;
    final result = await Isolate.run(
      () => SupportGenerator.generate(
        mesh,
        settings: SupportSettings(
          overhangAngleDegrees: angle,
          density: density,
        ),
      ),
    );
    if (result.supports.faceCount == 0) {
      status = 'No overhangs above ${angle.toStringAsFixed(0)}°';
      notify();
      return;
    }
    doc.snapshot('Supports');
    final supportObj = doc.add(result.supports, name: 'Supports');
    supportObj.transform = identity4();
    status = 'Supports: ${result.postCount} posts, ${result.strutCount} struts';
    await render();
  }

  Future<void> doAnalysis(AnalysisOverlay mode) async {
    final obj = selected;
    if (obj == null) return;
    busy = true;
    status = 'Analysing...';
    notify();
    final mesh = obj.mesh;
    Uint8List colors;
    String summary;
    switch (mode) {
      case AnalysisOverlay.thickness:
        final th = thicknessThreshold;
        final r = await Isolate.run(
          () => ThicknessAnalysis.run(mesh, threshold: th),
        );
        colors = _normalizeToBytes(r.perVertex, th * 2);
        summary =
            'min ${r.minThickness.toStringAsFixed(2)}, '
            'mean ${r.meanThickness.toStringAsFixed(2)}, '
            '${r.belowThresholdCount} verts below $th';
      case AnalysisOverlay.overhang:
        final angle = overhangAngle;
        final r = await Isolate.run(
          () => OverhangAnalysis.run(mesh, angleDegrees: angle),
        );
        colors = _normalizeToBytes(r.perVertexSeverity, 1.0);
        summary =
            '${r.faceCount} overhang faces, '
            '${(100 * r.overhangArea / (r.totalArea == 0 ? 1 : r.totalArea)).toStringAsFixed(1)}% of area';
      case AnalysisOverlay.stability:
        final r = await Isolate.run(() => StabilityAnalysis.run(mesh));
        colors = Uint8List(mesh.vertexCount);
        summary =
            'COM (${r.centerOfMass.map((v) => v.toStringAsFixed(1)).join(', ')}) '
            '${r.centerInsideSupport ? "inside" : "OUTSIDE"} base, '
            'tip ${r.minTipAngleDegrees.toStringAsFixed(1)}°';
      case AnalysisOverlay.deviation:
        colors = Uint8List(mesh.vertexCount);
        summary = 'Deviation requires a reference object';
      case AnalysisOverlay.none:
        colors = Uint8List(mesh.vertexCount);
        summary = 'No overlay';
    }
    overlayColors = colors;
    overlay = mode;
    status = summary;
    busy = false;
    await render();
  }

  static Uint8List _normalizeToBytes(Float32List values, double maxValue) {
    final out = Uint8List(values.length);
    final m = maxValue <= 0 ? 1.0 : maxValue;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!v.isFinite) {
        out[i] = 0;
        continue;
      }
      out[i] = (255 * (v / m).clamp(0.0, 1.0)).round();
    }
    return out;
  }

  // ------------------------------------------------------------ inspection
  Future<void> inspectMesh() async {
    final obj = selected;
    if (obj == null) return;
    busy = true;
    notify();
    final mesh = obj.mesh;
    final defects = await Isolate.run(() => MeshInspector.scan(mesh));
    final counts = <String, int>{};
    for (final d in defects) {
      counts[d.kind.name] = (counts[d.kind.name] ?? 0) + 1;
    }
    status = 'Inspector: ${counts.isEmpty ? "clean" : counts.toString()}';
    busy = false;
    await render();
  }

  Future<void> autoRepair() async {
    final obj = selected;
    if (obj == null) return;
    final mesh = obj.mesh;
    await runOp('Auto Repair', () async {
      var m = mesh;
      m = Weld.weldVertices(m, tolerance: m.bounds().diagonal * 1e-5);
      Weld.removeDuplicateFaces(m);
      m = MeshInspector.splitNonManifold(m);
      m = HoleFiller.fill(m, mode: HoleFillMode.smooth);
      return m;
    });
  }

  // ----------------------------------------------------------------- scene
  Future<void> addObject(TriMesh mesh, String name) async {
    doc.snapshot('Add $name');
    final obj = doc.add(mesh, name: name);
    selectedObjectId = obj.id;
    _frameObject(obj);
    status = 'Added $name';
    await render();
  }

  Future<void> importPath(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      status = 'Missing: $path';
      notify();
      return;
    }
    final bytes = f.readAsBytesSync();
    if (path.toLowerCase().endsWith('.mix')) {
      final objects = MixIO.read(bytes);
      if (objects.isEmpty) {
        status = 'No mesh found in $path';
        notify();
        return;
      }
      doc.snapshot('Import $path');
      SceneObject? first;
      for (final o in objects) {
        final obj = doc.add(o.mesh, name: o.name);
        first ??= obj;
      }
      selectedObjectId = first!.id;
      selection = null;
      _frameObject(first);
      status =
          'Imported ${objects.length} object(s) from ${path.split('/').last}';
      await render();
      return;
    }
    final mesh = MeshIO.readBytes(path, bytes);
    await addObject(mesh, path.split('/').last);
  }

  Future<void> exportSelected(String path) async {
    final obj = selected;
    if (obj == null) return;
    final bytes = MeshIO.writeBytes(path, obj.worldMesh());
    await File(path).writeAsBytes(bytes);
    status = 'Exported $path';
    notify();
  }

  Future<void> undo() async {
    if (doc.undo()) {
      status = 'Undo';
      await render();
    }
  }

  Future<void> redo() async {
    if (doc.redo()) {
      status = 'Redo';
      await render();
    }
  }

  /// Counts shells on demand; building topology on every panel rebuild would
  /// be wasteful for large meshes.
  void refreshShellCount() {
    final mesh = activeMesh;
    shellCount = mesh == null ? 0 : MeshTopology(mesh).components().$2;
  }

  void notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    frame?.dispose();
    super.dispose();
  }

  void setTool(StudioTool t) {
    tool = t;
    if (t == StudioTool.separate) refreshShellCount();
    status = 'Tool: ${t.name}';
    notify();
  }

  void toggleWireframe() {
    wireframe = !wireframe;
    _scheduleRender();
  }

  void toggleBed() {
    showBed = !showBed;
    _scheduleRender();
  }

  void setFrameSize(int w, int h) {
    if (w == frameWidth && h == frameHeight) return;
    frameWidth = w;
    frameHeight = h;
    _scheduleRender();
  }
}

int mathMax(int a, int b) => a > b ? a : b;
