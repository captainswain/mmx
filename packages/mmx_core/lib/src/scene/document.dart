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
    ..pivot = pivot;

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
  int maxUndoBytes;
  final List<_Snapshot> _undo = <_Snapshot>[];
  final List<_Snapshot> _redo = <_Snapshot>[];

  Document({this.maxUndoBytes = 512 * 1024 * 1024});

  SceneObject add(TriMesh mesh, {String? name}) {
    final obj =
        SceneObject(_nextId++, name ?? 'Object ${objects.length + 1}', mesh);
    objects.add(obj);
    return obj;
  }

  void remove(int id) {
    objects.removeWhere((o) => o.id == id);
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
      total += o.mesh.positions.lengthInBytes + o.mesh.indices.lengthInBytes;
    }
    return total;
  }

  void snapshot(String label) {
    final snap = _Snapshot(label, objects.map((o) => o.clone()).toList());
    _undo.add(snap);
    _redo.clear();
    while (_undo.isNotEmpty && _undoBytes() > maxUndoBytes) {
      _undo.removeAt(0);
    }
  }

  int _undoBytes() {
    var total = 0;
    for (final s in _undo) {
      for (final o in s.objects) {
        total += o.mesh.positions.lengthInBytes + o.mesh.indices.lengthInBytes;
      }
    }
    return total;
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
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final snap = _redo.removeLast();
    _undo.add(_Snapshot(snap.label, objects.map((o) => o.clone()).toList()));
    _restore(snap);
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
  final n = 1.0 / (l > 0 ? _sqrt(l) : 1);
  final x = ax * n, y = ay * n, z = az * n;
  final c = _cos(radians), s = _sin(radians), t = 1 - c;
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

double _sqrt(double v) {
  var x = v;
  for (var i = 0; i < 20; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

double _cos(double v) {
  // Range reduction then Taylor series; avoids importing dart:math here.
  var x = v % 6.283185307179586;
  if (x > 3.141592653589793) x -= 6.283185307179586;
  var term = 1.0, sum = 1.0;
  for (var i = 1; i < 12; i++) {
    term *= -x * x / ((2 * i - 1) * (2 * i));
    sum += term;
  }
  return sum;
}

double _sin(double v) {
  var x = v % 6.283185307179586;
  if (x > 3.141592653589793) x -= 6.283185307179586;
  var term = x, sum = x;
  for (var i = 1; i < 12; i++) {
    term *= -x * x / ((2 * i) * (2 * i + 1));
    sum += term;
  }
  return sum;
}
