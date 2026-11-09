import 'dart:math' as math;
import 'dart:typed_data';

import '../geom/bbox.dart';
import '../mesh/tri_mesh.dart';
import '../tools/pivot.dart';

/// A named object in the scene: mesh plus transform, visibility and metadata.
class SceneObject {
  final int id;
  String name;
  TriMesh mesh;
  Float64List transform;
  bool visible;
  bool isTarget;
  Pivot? pivot;

  SceneObject(this.id, this.name, this.mesh, {Float64List? transform})
      : transform = transform ?? identity4(),
        visible = true,
        isTarget = false;

  SceneObject clone() => SceneObject(id, name, mesh.clone(),
      transform: Float64List.fromList(transform))
    ..visible = visible
    ..isTarget = isTarget
    ..pivot = pivot == null
        ? null
        : Pivot(
            position: List<double>.from(pivot!.position),
            normal: List<double>.from(pivot!.normal));

  BBox worldBounds() {
    final m = mesh.clone();
    m.transform(transform);
    return m.bounds();
  }

  TriMesh worldMesh() {
    final m = mesh.clone();
    m.transform(transform);
    return m;
  }
}

/// Snapshot-based undo stack with a byte budget, mirroring Meshmixer's
/// "MaxUndoMemorySize" preference and its history-node based undo.
class Document {
  final List<SceneObject> objects = <SceneObject>[];
  int _nextId = 1;
  int revision = 0;

  void replaceObjects(List<SceneObject> replacement) {
    objects
      ..clear()
      ..addAll(replacement.map((o) => o.clone()));
    _nextId = objects.fold<int>(0, (n, o) => math.max(n, o.id)) + 1;
    _undo.clear();
    _redo.clear();
    revision++;
  }

  /// Capture a rollback point, including both history stacks.
  void Function() checkpoint() {
    final saved = objects.map((o) => o.clone()).toList();
    final undo = List<_Snapshot>.from(_undo),
        redo = List<_Snapshot>.from(_redo);
    final next = _nextId;
    return () {
      objects
        ..clear()
        ..addAll(saved);
      _undo
        ..clear()
        ..addAll(undo);
      _redo
        ..clear()
        ..addAll(redo);
      _nextId = next;
      revision++;
    };
  }

  static int objectBytes(SceneObject o) =>
      o.mesh.positions.lengthInBytes +
      o.mesh.indices.lengthInBytes +
      (o.mesh.faceGroups?.lengthInBytes ?? 0) +
      (o.mesh.vertexColors?.lengthInBytes ?? 0) +
      o.transform.lengthInBytes +
      (o.pivot == null ? 0 : 48);

  int get historyBytes => [..._undo, ..._redo].fold(
      0, (n, s) => n + s.objects.fold<int>(0, (n, o) => n + objectBytes(o)));

  void _trimHistory() {
    while (
        historyBytes > maxUndoBytes && (_undo.isNotEmpty || _redo.isNotEmpty)) {
      if (_undo.isNotEmpty) {
        _undo.removeAt(0);
      } else {
        _redo.removeAt(0);
      }
    }
  }

  int maxUndoBytes;
  final List<_Snapshot> _undo = <_Snapshot>[];
  final List<_Snapshot> _redo = <_Snapshot>[];

  Document({this.maxUndoBytes = 512 * 1024 * 1024});

  SceneObject add(TriMesh mesh, {String? name}) {
    final obj =
        SceneObject(_nextId++, name ?? 'Object ${objects.length + 1}', mesh);
    objects.add(obj);
    revision++;
    return obj;
  }

  void remove(int id) {
    objects.removeWhere((o) => o.id == id);
    revision++;
  }

  SceneObject? byId(int id) {
    for (final o in objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  int get memoryBytes {
    var total = 0;
    for (final o in objects) {
      total += objectBytes(o);
    }
    return total;
  }

  void snapshot(String label) {
    final snap = _Snapshot(label, objects.map((o) => o.clone()).toList());
    _undo.add(snap);
    _redo.clear();
    revision++;
    _trimHistory();
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  bool undo() {
    if (_undo.isEmpty) return false;
    final snap = _undo.removeLast();
    _redo.add(_Snapshot(snap.label, objects.map((o) => o.clone()).toList()));
    _restore(snap);
    revision++;
    _trimHistory();
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final snap = _redo.removeLast();
    _undo.add(_Snapshot(snap.label, objects.map((o) => o.clone()).toList()));
    _restore(snap);
    revision++;
    _trimHistory();
    return true;
  }

  void _restore(_Snapshot snap) {
    objects
      ..clear()
      ..addAll(snap.objects.map((o) => o.clone()));
    var maxId = 0;
    for (final o in objects) {
      if (o.id > maxId) maxId = o.id;
    }
    _nextId = maxId + 1;
  }
}

class _Snapshot {
  final String label;
  final List<SceneObject> objects;
  _Snapshot(this.label, this.objects);
}

Float64List identity4() => Float64List.fromList(<double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
    ]);

/// Column-major translation.
Float64List translation4(double x, double y, double z) =>
    Float64List.fromList(<double>[
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      1,
      0,
      x,
      y,
      z,
      1,
    ]);

Float64List scale4(double s) => Float64List.fromList(<double>[
      s,
      0,
      0,
      0,
      0,
      s,
      0,
      0,
      0,
      0,
      s,
      0,
      0,
      0,
      0,
      1,
    ]);

/// Rotation about an arbitrary axis (column-major).
Float64List rotation4(double ax, double ay, double az, double radians) {
  final l = ax * ax + ay * ay + az * az;
  if (l < 1e-20) return identity4();
  final n = 1.0 / (l > 0 ? math.sqrt(l) : 1);
  final x = ax * n, y = ay * n, z = az * n;
  final c = math.cos(radians), s = math.sin(radians), t = 1 - c;
  return Float64List.fromList(<double>[
    t * x * x + c,
    t * x * y - s * z,
    t * x * z + s * y,
    0,
    t * x * y + s * z,
    t * y * y + c,
    t * y * z - s * x,
    0,
    t * x * z - s * y,
    t * y * z + s * x,
    t * z * z + c,
    0,
    0,
    0,
    0,
    1,
  ]);
}

/// Multiplies column-major 4x4 matrices: a * b.
Float64List multiply4(Float64List a, Float64List b) {
  final out = Float64List(16);
  for (var col = 0; col < 4; col++) {
    for (var row = 0; row < 4; row++) {
      var s = 0.0;
      for (var k = 0; k < 4; k++) {
        s += a[k * 4 + row] * b[col * 4 + k];
      }
      out[col * 4 + row] = s;
    }
  }
  return out;
}
