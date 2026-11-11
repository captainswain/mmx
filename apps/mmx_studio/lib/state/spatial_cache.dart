import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';

/// A bounded, single-object cache. Revisions cover in-place geometry edits;
/// identity and transform comparisons also cover replacement and preview edits.
class SceneSpatialCache {
  TriMesh? _mesh;
  int? _revision;
  int? _objectId;
  Float64List? _transform;
  TriMesh? _world;
  TriangleBVH? _bvh;
  MeshTopology? _topology;

  int bvhBuilds = 0;
  int topologyBuilds = 0;

  void clear() {
    _mesh = null;
    _revision = null;
    _world = null;
    _bvh = null;
    _topology = null;
    _transform = null;
    _objectId = null;
  }

  void _prepare(SceneObject object, int revision) {
    if (!identical(_mesh, object.mesh) ||
        _revision != revision ||
        _objectId != object.id) {
      clear();
      _mesh = object.mesh;
      _revision = revision;
      _objectId = object.id;
    }
    final transform = _transform;
    if (transform == null || !_sameTransform(transform, object.transform)) {
      _world = null;
      _bvh = null;
      _transform = Float64List.fromList(object.transform);
    }
  }

  TriMesh worldMesh(SceneObject object, int revision) {
    _prepare(object, revision);
    return _world ??= object.worldMesh();
  }

  TriangleBVH bvh(SceneObject object, int revision) {
    _prepare(object, revision);
    if (_bvh == null) {
      _bvh = TriangleBVH.build(worldMesh(object, revision));
      bvhBuilds++;
    }
    return _bvh!;
  }

  MeshTopology topology(SceneObject object, int revision) {
    _prepare(object, revision);
    if (_topology == null) {
      _topology = MeshTopology(object.mesh);
      topologyBuilds++;
    }
    return _topology!;
  }

  static bool _sameTransform(Float64List a, Float64List b) {
    for (var i = 0; i < 16; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
