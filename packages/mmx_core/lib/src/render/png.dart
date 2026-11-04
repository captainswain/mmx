import 'dart:io';
import 'dart:typed_data';

/// Minimal PNG encoder for screenshots and headless rendering.
class PngEncoder {
  static Uint8List encodeRGBA(Uint8List rgba, int width, int height) {
    final raw = Uint8List(height * (width * 4 + 1));
    var o = 0;
    for (var y = 0; y < height; y++) {
      raw[o++] = 0; // filter type: none
      raw.setRange(o, o + width * 4, rgba, y * width * 4);
      o += width * 4;
    }
    final compressed = ZLibEncoder(level: 6).convert(raw);

    final out = BytesBuilder();
    out.add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    void chunk(String type, List<int> data) {
      final t = type.codeUnits;
      final len = ByteData(4)..setUint32(0, data.length, Endian.big);
      out.add(len.buffer.asUint8List());
      out.add(t);
      out.add(data);
      final crcData = <int>[...t, ...data];
      final crc = ByteData(4)..setUint32(0, _crc32(crcData), Endian.big);
      out.add(crc.buffer.asUint8List());
    }

    final ihdr = ByteData(13)
      ..setUint32(0, width, Endian.big)
      ..setUint32(4, height, Endian.big)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6) // colour type RGBA
      ..setUint8(10, 0)
      ..setUint8(11, 0)
      ..setUint8(12, 0);
    chunk('IHDR', ihdr.buffer.asUint8List());
    chunk('IDAT', compressed);
    chunk('IEND', <int>[]);
    return out.takeBytes();
  }

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
