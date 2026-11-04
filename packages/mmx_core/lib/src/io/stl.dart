import 'dart:typed_data';

import '../mesh/tri_mesh.dart';

/// Binary and ASCII STL.
class StlIO {
  /// Reads binary STL. Vertices are welded on an exact-bit basis so shared
  /// corners become shared vertices (STL stores three floats per triangle).
  static TriMesh readBinary(Uint8List bytes) {
    if (bytes.length < 84) return TriMesh.empty();
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint32(80, Endian.little);
    final available = (bytes.length - 84) ~/ 50;
    final n = count < available ? count : available;
    final builder = MeshBuilder();
    final weld = <String, int>{};
    int vkey(double x, double y, double z) {
      final k = '${x.toStringAsPrecision(9)}|${y.toStringAsPrecision(9)}|${z.toStringAsPrecision(9)}';
      return weld.putIfAbsent(k, () => builder.addVertex(x, y, z));
    }

    for (var i = 0; i < n; i++) {
      final off = 84 + i * 50 + 12;
      final ax = bd.getFloat32(off, Endian.little);
      final ay = bd.getFloat32(off + 4, Endian.little);
      final az = bd.getFloat32(off + 8, Endian.little);
      final bx = bd.getFloat32(off + 12, Endian.little);
      final by = bd.getFloat32(off + 16, Endian.little);
      final bz = bd.getFloat32(off + 20, Endian.little);
      final cx = bd.getFloat32(off + 24, Endian.little);
      final cy = bd.getFloat32(off + 28, Endian.little);
      final cz = bd.getFloat32(off + 32, Endian.little);
      builder.addTriangle(vkey(ax, ay, az), vkey(bx, by, bz), vkey(cx, cy, cz));
    }
    final mesh = builder.build();
    mesh.removeDegenerateFaces();
    return mesh;
  }

  static TriMesh readAscii(String text) {
    final builder = MeshBuilder();
    final weld = <String, int>{};
    int vkey(double x, double y, double z) {
      final k = '${x.toStringAsPrecision(9)}|${y.toStringAsPrecision(9)}|${z.toStringAsPrecision(9)}';
      return weld.putIfAbsent(k, () => builder.addVertex(x, y, z));
    }

    final verts = <int>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('vertex')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final x = double.parse(parts[1]);
      final y = double.parse(parts[2]);
      final z = double.parse(parts[3]);
      verts.add(vkey(x, y, z));
      if (verts.length == 3) {
        builder.addTriangle(verts[0], verts[1], verts[2]);
        verts.clear();
      }
    }
    final mesh = builder.build();
    mesh.removeDegenerateFaces();
    return mesh;
  }

  static Uint8List writeBinary(TriMesh mesh) {
    final n = mesh.faceCount;
    final out = Uint8List(84 + n * 50);
    final bd = ByteData.sublistView(out);
    final header = 'Binary STL exported by mmx_core'.codeUnits;
    for (var i = 0; i < header.length && i < 80; i++) {
      out[i] = header[i];
    }
    bd.setUint32(80, n, Endian.little);
    for (var f = 0; f < n; f++) {
      final a = mesh.indices[f * 3], b = mesh.indices[f * 3 + 1], c = mesh.indices[f * 3 + 2];
      final ax = mesh.vx(a), ay = mesh.vy(a), az = mesh.vz(a);
      final bx = mesh.vx(b), by = mesh.vy(b), bz = mesh.vz(b);
      final cx = mesh.vx(c), cy = mesh.vy(c), cz = mesh.vz(c);
      final ux = bx - ax, uy = by - ay, uz = bz - az;
      final wx = cx - ax, wy = cy - ay, wz = cz - az;
      var nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
      final len = (nx * nx + ny * ny + nz * nz);
      if (len > 1e-20) {
        final inv = 1.0 / _sqrt(len);
        nx *= inv;
        ny *= inv;
        nz *= inv;
      }
      final off = 84 + f * 50;
      bd.setFloat32(off, nx, Endian.little);
      bd.setFloat32(off + 4, ny, Endian.little);
      bd.setFloat32(off + 8, nz, Endian.little);
      bd.setFloat32(off + 12, ax, Endian.little);
      bd.setFloat32(off + 16, ay, Endian.little);
      bd.setFloat32(off + 20, az, Endian.little);
      bd.setFloat32(off + 24, bx, Endian.little);
      bd.setFloat32(off + 28, by, Endian.little);
      bd.setFloat32(off + 32, bz, Endian.little);
      bd.setFloat32(off + 36, cx, Endian.little);
      bd.setFloat32(off + 40, cy, Endian.little);
      bd.setFloat32(off + 44, cz, Endian.little);
      bd.setUint16(off + 48, 0, Endian.little);
    }
    return out;
  }

  static String writeAscii(TriMesh mesh, {String name = 'mmx_core'}) {
    final sb = StringBuffer('solid $name\n');
    for (var f = 0; f < mesh.faceCount; f++) {
      final a = mesh.indices[f * 3], b = mesh.indices[f * 3 + 1], c = mesh.indices[f * 3 + 2];
      sb.writeln('  facet normal 0 0 0');
      sb.writeln('    outer loop');
      sb.writeln('      vertex ${mesh.vx(a)} ${mesh.vy(a)} ${mesh.vz(a)}');
      sb.writeln('      vertex ${mesh.vx(b)} ${mesh.vy(b)} ${mesh.vz(b)}');
      sb.writeln('      vertex ${mesh.vx(c)} ${mesh.vy(c)} ${mesh.vz(c)}');
      sb.writeln('    endloop');
      sb.writeln('  endfacet');
    }
    sb.writeln('endsolid $name');
    return sb.toString();
  }

  static double _sqrt(double v) {
    // Local Newton sqrt to keep this file dependency free.
    if (v <= 0) return 0;
    var x = v;
    for (var i = 0; i < 20; i++) {
      x = 0.5 * (x + v / x);
    }
    return x;
  }
}
