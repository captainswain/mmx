import 'dart:io';
import 'package:mmx_core/mmx_core.dart';

void main() {
  final f = File('/data/re/meshmixer/extract/meshmixer/models/bunnyr.obj');
  final mesh = MeshIO.readBytes('bunnyr.obj', f.readAsBytesSync());
  print('input: ${mesh.vertexCount} verts, ${mesh.faceCount} faces');
  void t(String label, void Function() fn) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    print('${label.padRight(22)} ${sw.elapsedMilliseconds} ms');
  }
  late TriMesh r;
  t('topology+bvh', () {
    final topo = MeshTopology(mesh);
    final bvh = TriangleBVH.build(mesh);
    print('  valence=${topo.averageValence().toStringAsFixed(2)} nodes=${bvh.nodeCount}');
  });
  t('reduce 50%', () { r = Decimator.reduce(mesh, percentage: 0.5); });
  print('  -> ${r.faceCount} faces');
  t('remesh isotropic', () { r = IsotropicRemesher.remesh(mesh, targetEdgeLength: 2.0, iterations: 4); });
  print('  -> ${r.faceCount} faces');
  t('make solid 128', () { r = Solidifier.makeSolid(mesh, resolution: 128).mesh; });
  print('  -> ${r.faceCount} faces, vol ${r.signedVolume().toStringAsFixed(0)}');
  t('hollow', () { r = Solidifier.hollow(mesh, thickness: 2, holes: 3, resolution: 96).mesh; });
  print('  -> ${r.faceCount} faces');
  t('thickness scan', () { final x = ThicknessAnalysis.run(mesh, threshold: 1); print('  min=${x.minThickness.toStringAsFixed(2)}'); });
  t('supports', () { final x = SupportGenerator.generate(mesh, bedY: mesh.bounds().minY); print('  posts=${x.postCount}'); });
  t('pack 6 objects', () {
    final list = List<TriMesh>.generate(6, (_) => mesh.clone());
    final p = Packer.pack(list, bedWidth: 300, bedDepth: 300);
    print('  placed=${p.placed.length}');
  });
  t('slice 0.2mm', () { final s = Slicer.slice(mesh, layerHeight: 0.2); print('  layers=${s.layers.length}'); });
  t('render 960x640', () {
    final cam = Camera();
    final b = mesh.bounds();
    cam.frame(b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ);
    Rasterizer.render(<RenderObject>[RenderObject(mesh, transform: identity4(), color: <double>[0.8, 0.75, 0.65])], cam, const RenderOptions());
  });
}
