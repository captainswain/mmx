import 'dart:io';
import 'package:mmx_core/mmx_core.dart';
void main(){
  final m = MeshIO.readBytes('sphere.obj', File('/data/re/meshmixer/extract/meshmixer/models/sphere.obj').readAsBytesSync());
  final o = OverhangAnalysis.run(m, angleDegrees: 45);
  print('overhangArea=${o.overhangArea} total=${o.totalArea} faces=${o.overhangFaces}/${m.faceCount} vol=${m.signedVolume()}');
  final s = StabilityAnalysis.run(m);
  print('com=${s.centerOfMass} contacts=${s.contactPoints.length} inside=${s.centerInsideSupport} tip=${s.minTipAngleDegrees} bedY=${m.bounds().minY}');
  print('bounds=${m.bounds().minX},${m.bounds().minY},${m.bounds().minZ} .. ${m.bounds().maxX},${m.bounds().maxY},${m.bounds().maxZ}');
  print('hull=${s.contactPoints.take(6).toList()}');
}
