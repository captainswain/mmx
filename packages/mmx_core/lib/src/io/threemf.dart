import 'dart:convert';
import 'dart:typed_data';

import '../mesh/tri_mesh.dart';
import 'zip.dart';

/// 3MF (3D Manufacturing Format) import/export.
///
/// The shipped Meshmixer binary imports 3MF through the bundled lib3mf; this is
/// a dependency-free reader/writer for the core mesh payload of an OPC package.
class ThreeMfIO {
  static const String _contentTypes = '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
</Types>''';

  static const String _rels = '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>''';

  /// [unit] is one of micron, millimeter, centimeter, inch, foot, meter.
  static Uint8List write(TriMesh mesh, {String unit = 'millimeter', String name = 'mmx'}) {
    final sb = StringBuffer();
    sb.write('<?xml version="1.0" encoding="UTF-8"?>\n');
    sb.write('<model unit="$unit" xml:lang="en-US" '
        'xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n');
    sb.write('  <metadata name="Title">$name</metadata>\n');
    sb.write('  <resources>\n');
    sb.write('    <object id="1" type="model">\n');
    sb.write('      <mesh>\n        <vertices>\n');
    for (var i = 0; i < mesh.vertexCount; i++) {
      sb.write('          <vertex x="${_f(mesh.vx(i))}" y="${_f(mesh.vy(i))}" '
          'z="${_f(mesh.vz(i))}"/>\n');
    }
    sb.write('        </vertices>\n        <triangles>\n');
    for (var f = 0; f < mesh.faceCount; f++) {
      sb.write('          <triangle v1="${mesh.indices[f * 3]}" '
          'v2="${mesh.indices[f * 3 + 1]}" v3="${mesh.indices[f * 3 + 2]}"/>\n');
    }
    sb.write('        </triangles>\n      </mesh>\n    </object>\n');
    sb.write('  </resources>\n');
    sb.write('  <build>\n    <item objectid="1"/>\n  </build>\n</model>\n');

    return ZipArchive.write(<ZipEntry>[
      ZipEntry('[Content_Types].xml', Uint8List.fromList(utf8.encode(_contentTypes))),
      ZipEntry('_rels/.rels', Uint8List.fromList(utf8.encode(_rels))),
      ZipEntry('3D/3dmodel.model', Uint8List.fromList(utf8.encode(sb.toString()))),
    ]);
  }

  static TriMesh read(Uint8List bytes) {
    final entries = ZipArchive.read(bytes);
    if (entries.isEmpty) return TriMesh.empty();
    ZipEntry? model;
    for (final e in entries) {
      if (e.name.toLowerCase().endsWith('.model')) {
        model = e;
        break;
      }
    }
    if (model == null) return TriMesh.empty();
    final xml = utf8.decode(model.data, allowMalformed: true);
    return _parseModel(xml);
  }

  static TriMesh _parseModel(String xml) {
    final builder = MeshBuilder();
    final vertexRe = RegExp(r'<vertex\b([^>]*)/?>', caseSensitive: false);
    final triangleRe = RegExp(r'<triangle\b([^>]*)/?>', caseSensitive: false);
    for (final m in vertexRe.allMatches(xml)) {
      final attrs = _attrs(m.group(1) ?? '');
      final x = double.tryParse(attrs['x'] ?? '');
      final y = double.tryParse(attrs['y'] ?? '');
      final z = double.tryParse(attrs['z'] ?? '');
      if (x == null || y == null || z == null) continue;
      builder.addVertex(x, y, z);
    }
    for (final m in triangleRe.allMatches(xml)) {
      final attrs = _attrs(m.group(1) ?? '');
      final a = int.tryParse(attrs['v1'] ?? '');
      final b = int.tryParse(attrs['v2'] ?? '');
      final c = int.tryParse(attrs['v3'] ?? '');
      if (a == null || b == null || c == null) continue;
      builder.addTriangle(a, b, c);
    }
    final mesh = builder.build();
    mesh.removeDegenerateFaces();
    return mesh;
  }

  static Map<String, String> _attrs(String source) {
    final out = <String, String>{};
    final re = RegExp(r'([A-Za-z_:][A-Za-z0-9_.:-]*)\s*=\s*"([^"]*)"');
    for (final m in re.allMatches(source)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  static String _f(double v) {
    // 6 decimals is plenty for millimetre-scale geometry and keeps files small.
    final s = v.toStringAsFixed(6);
    return s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '') : s;
  }
}
