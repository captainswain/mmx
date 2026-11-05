import '../mesh/topology.dart';
import '../mesh/tri_mesh.dart';
import '../remesh/isotropic.dart';
import '../repair/bridge.dart';
import '../repair/weld.dart';
import '../spatial/bvh.dart';
import 'solidifier.dart';

class BooleanResult {
  final TriMesh mesh;
  final bool usedFallback;
  final String? fallbackReason;

  const BooleanResult(this.mesh, {this.usedFallback = false, this.fallbackReason});
}

/// Mesh-level boolean composition: classify triangles by containment, keep the
/// requested side of each input, then stitch the resulting boundary loops.
///
/// This is the remesh-and-stitch family Meshmixer describes for its Precise
/// boolean, as opposed to [Solidifier.boolean], which performs grid CSG. It
/// falls back to the grid implementation when stitching cannot close the
/// result.
class PreciseBoolean {
  static TriMesh compute(
    TriMesh a,
    TriMesh b,
    BooleanOp op, {
    double? edgeLength,
    int resolution = 160,
  }) {
    return computeDetailed(a, b, op, edgeLength: edgeLength, resolution: resolution).mesh;
  }

  static BooleanResult computeDetailed(
    TriMesh a,
    TriMesh b,
    BooleanOp op, {
    double? edgeLength,
    int resolution = 160,
  }) {
    var left = a;
    var right = b;
    if (edgeLength != null && edgeLength > 0) {
      left = _remesh(left, edgeLength);
      right = _remesh(right, edgeLength);
    }

    final bvhLeft = TriangleBVH.build(left);
    final bvhRight = TriangleBVH.build(right);

    final builder = MeshBuilder();
    final groups = <int>[];
    void addFace(TriMesh m, int f, {bool flip = false}) {
      final i0 = m.indices[f * 3];
      final i1 = m.indices[f * 3 + 1];
      final i2 = m.indices[f * 3 + 2];
      final v0 = builder.addVertex(m.vx(i0), m.vy(i0), m.vz(i0));
      final v1 = builder.addVertex(m.vx(i1), m.vy(i1), m.vz(i1));
      final v2 = builder.addVertex(m.vx(i2), m.vy(i2), m.vz(i2));
      if (flip) {
        builder.addTriangle(v0, v2, v1);
      } else {
        builder.addTriangle(v0, v1, v2);
      }
      groups.add(m.faceGroups == null ? 0 : m.faceGroups![f]);
    }

    final keepLeftInside = op == BooleanOp.intersection;
    final keepRightInside = op != BooleanOp.union;

    for (var f = 0; f < left.faceCount; f++) {
      final inside = _inside(bvhRight, left, f);
      if (inside == keepLeftInside) addFace(left, f);
    }
    for (var f = 0; f < right.faceCount; f++) {
      final inside = _inside(bvhLeft, right, f);
      if (inside == keepRightInside) {
        addFace(right, f, flip: op == BooleanOp.difference);
      }
    }

    var out = builder.build();
    if (out.faceCount == 0) {
      return BooleanResult(
        Solidifier.boolean(a, b, op, resolution: resolution).mesh,
        usedFallback: true,
        fallbackReason: 'empty mesh-level result',
      );
    }
    out = Weld.weldVertices(out, tolerance: 1e-5);
    out = Bridge.stitchNearest(
        out,
        maxGap: out.bounds().diagonal * 0.25,
        maxPairs: 64);
    out = Weld.weldCracks(out, tolerance: 1e-5);
    out.removeDegenerateFaces();
    out.compact();

    if (MeshTopology(out).boundaryLoops().isNotEmpty ||
        out.signedVolume().abs() < 1e-9) {
      return BooleanResult(
        Solidifier.boolean(a, b, op, resolution: resolution).mesh,
        usedFallback: true,
        fallbackReason: MeshTopology(out).boundaryLoops().isNotEmpty
            ? 'stitching left boundary loops'
            : 'zero-volume result',
      );
    }
    return BooleanResult(out);
  }

  static TriMesh _remesh(TriMesh mesh, double edgeLength) {
    return IsotropicRemesher.remesh(
      mesh,
      targetEdgeLength: edgeLength,
      iterations: 3,
      preserveBoundary: false,
    );
  }

  static bool _inside(TriangleBVH bvh, TriMesh mesh, int face) {
    final a = mesh.indices[face * 3];
    final b = mesh.indices[face * 3 + 1];
    final c = mesh.indices[face * 3 + 2];
    final x = (mesh.vx(a) + mesh.vx(b) + mesh.vx(c)) / 3.0;
    final y = (mesh.vy(a) + mesh.vy(b) + mesh.vy(c)) / 3.0;
    final z = (mesh.vz(a) + mesh.vz(b) + mesh.vz(c)) / 3.0;
    const inv = 0.5773502691896258;
    final hits = bvh.raycastAll(<double>[x, y, z], <double>[inv, inv, inv]);
    return hits.length.isOdd;
  }
}
