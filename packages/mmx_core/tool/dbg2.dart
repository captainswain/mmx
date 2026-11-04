import 'dart:io';
import 'package:mmx_core/mmx_core.dart';
void main(){
  final m = MeshIO.readBytes('sphere.obj', File('/data/re/meshmixer/extract/meshmixer/models/sphere.obj').readAsBytesSync());
  final s = StabilityAnalysis.run(m);
  print('contacts=${s.contactPoints.length} inside=${s.centerInsideSupport} tip=${s.minTipAngleDegrees}');
  print('contacts sample=${s.contactPoints.take(5).toList()}');
  print('com=${s.centerOfMass}');
}
