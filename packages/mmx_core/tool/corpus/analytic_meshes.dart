import 'dart:typed_data';
import 'package:mmx_core/mmx_core.dart';

/// Independently specified outward unit cube, centered at the origin.
/// Analytic volume is 8*scale^3 and area is 24*scale^2.
TriMesh analyticCube({double scale = 1}) => TriMesh(
    Float32List.fromList([
      -1,
      -1,
      -1,
      1,
      -1,
      -1,
      1,
      1,
      -1,
      -1,
      1,
      -1,
      -1,
      -1,
      1,
      1,
      -1,
      1,
      1,
      1,
      1,
      -1,
      1,
      1,
    ].map((v) => v * scale).toList()),
    Uint32List.fromList([
      0,
      2,
      1,
      0,
      3,
      2,
      4,
      5,
      6,
      4,
      6,
      7,
      0,
      1,
      5,
      0,
      5,
      4,
      1,
      2,
      6,
      1,
      6,
      5,
      2,
      3,
      7,
      2,
      7,
      6,
      3,
      0,
      4,
      3,
      4,
      7,
    ]));

bool consistentWinding(TriMesh mesh) {
  final edges = <(int, int), int>{};
  for (var f = 0; f < mesh.faceCount; f++) {
    for (var k = 0; k < 3; k++) {
      final a = mesh.indices[f * 3 + k], b = mesh.indices[f * 3 + (k + 1) % 3];
      final key = a < b ? (a, b) : (b, a);
      edges.update(key, (n) => n + (a < b ? 1 : -1),
          ifAbsent: () => a < b ? 1 : -1);
    }
  }
  return edges.values.every((n) => n == 0);
}
