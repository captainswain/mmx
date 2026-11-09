import 'dart:convert';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

Map<String, Object> cameraMetadata(Camera camera) => {
      'yaw': camera.yaw,
      'pitch': camera.pitch,
      'distance': camera.distance,
      'fov': camera.fovDegrees,
      'near': camera.near,
      'far': camera.far,
      'target': camera.target,
    };

void main() {
  final unusable = <String, Camera>{
    'FOV reciprocal overflow': Camera(fovDegrees: 1e-308),
    'projection depth overflow': Camera(near: 1e308, far: 1.7e308),
    'near-plane reciprocal overflow': Camera(near: 5e-324, far: 1e-323),
    'projection depth underflow': Camera(near: 1e-200, far: 1e-190),
    'view normalization overflow': Camera(distance: 1e308),
    'eye position overflow':
        Camera(distance: 1e308, target: [1.7e308, 1.7e308, 1.7e308]),
    'unrepresentable eye offset': Camera(target: [1e100, 1e100, 1e100]),
  };

  test('project writer rejects finite but numerically unusable cameras', () {
    for (final entry in unusable.entries) {
      expect(() => ProjectIO.write(ProjectData([], camera: entry.value)),
          throwsFormatException,
          reason: entry.key);
    }
  });

  test('project reader rejects unusable camera metadata before installation',
      () {
    final original = ZipArchive.read(ProjectIO.write(ProjectData([])));
    for (final entry in unusable.entries) {
      final manifest =
          jsonDecode(utf8.decode(original.first.data)) as Map<String, dynamic>;
      manifest['camera'] = cameraMetadata(entry.value);
      final malformed = ZipArchive.write([
        ZipEntry('manifest.json',
            Uint8List.fromList(utf8.encode(jsonEncode(manifest)))),
        ...original.skip(1),
      ]);
      expect(() => ProjectIO.read(malformed), throwsFormatException,
          reason: entry.key);
    }
  });

  test('usable cameras round-trip across scale without arbitrary limits', () {
    final cameras = [
      Camera(fovDegrees: 1e-10),
      Camera(fovDegrees: 179.999999),
      for (final scale in [1e-100, 1e-20, 1.0, 1e20, 1e100])
        Camera(
          target: [scale, -scale, scale],
          distance: 3 * scale,
          near: .001 * scale,
          far: 100 * scale,
        ),
    ];
    for (final camera in cameras) {
      final restored =
          ProjectIO.read(ProjectIO.write(ProjectData([], camera: camera)))
              .camera;
      expect(cameraMetadata(restored), cameraMetadata(camera));
      expect(
          restored.viewProjection(1).every((value) => value.isFinite), isTrue);
    }
  });
}
