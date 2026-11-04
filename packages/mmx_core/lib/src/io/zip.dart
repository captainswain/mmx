import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal ZIP reader/writer for OPC packages (3MF).
///
/// Supports stored and raw-deflate entries, which covers every 3MF produced by
/// mainstream slicers and CAD tools. No dependency on package:archive.
class ZipEntry {
  final String name;
  final Uint8List data;
  ZipEntry(this.name, this.data);
}

class ZipArchive {
  static Uint8List write(List<ZipEntry> entries) {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;
    for (final e in entries) {
      final nameBytes = utf8.encode(e.name);
      final compressed = ZLibEncoder(raw: true, level: 6).convert(e.data);
      final crc = _crc32(e.data);
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0, Endian.little)
        ..setUint16(8, 8, Endian.little) // deflate
        ..setUint16(10, 0, Endian.little)
        ..setUint16(12, 0, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, compressed.length, Endian.little)
        ..setUint32(22, e.data.length, Endian.little)
        ..setUint16(26, nameBytes.length, Endian.little)
        ..setUint16(28, 0, Endian.little);
      out.add(local.buffer.asUint8List());
      out.add(nameBytes);
      out.add(compressed);

      final centralEntry = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0, Endian.little)
        ..setUint16(10, 8, Endian.little)
        ..setUint16(12, 0, Endian.little)
        ..setUint16(14, 0, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, compressed.length, Endian.little)
        ..setUint32(24, e.data.length, Endian.little)
        ..setUint16(28, nameBytes.length, Endian.little)
        ..setUint16(30, 0, Endian.little)
        ..setUint16(32, 0, Endian.little)
        ..setUint16(34, 0, Endian.little)
        ..setUint16(36, 0, Endian.little)
        ..setUint32(38, 0, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central.add(centralEntry.buffer.asUint8List());
      central.add(nameBytes);
      offset += 30 + nameBytes.length + compressed.length;
    }
    final centralBytes = central.takeBytes();
    out.add(centralBytes);
    final eocd = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, entries.length, Endian.little)
      ..setUint16(10, entries.length, Endian.little)
      ..setUint32(12, centralBytes.length, Endian.little)
      ..setUint32(16, offset, Endian.little)
      ..setUint16(20, 0, Endian.little);
    out.add(eocd.buffer.asUint8List());
    return out.takeBytes();
  }

  static List<ZipEntry> read(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    // Locate the end-of-central-directory record.
    var eocd = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 66000; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return <ZipEntry>[];
    final count = bd.getUint16(eocd + 10, Endian.little);
    var pos = bd.getUint32(eocd + 16, Endian.little);
    final entries = <ZipEntry>[];
    for (var i = 0; i < count; i++) {
      if (bd.getUint32(pos, Endian.little) != 0x02014b50) break;
      final method = bd.getUint16(pos + 10, Endian.little);
      final compSize = bd.getUint32(pos + 20, Endian.little);
      final nameLen = bd.getUint16(pos + 28, Endian.little);
      final extraLen = bd.getUint16(pos + 30, Endian.little);
      final commentLen = bd.getUint16(pos + 32, Endian.little);
      final localOffset = bd.getUint32(pos + 42, Endian.little);
      final name = utf8.decode(bytes.sublist(pos + 46, pos + 46 + nameLen));
      pos += 46 + nameLen + extraLen + commentLen;

      // Read the local header to find the payload start.
      final localNameLen = bd.getUint16(localOffset + 26, Endian.little);
      final localExtraLen = bd.getUint16(localOffset + 28, Endian.little);
      final dataStart = localOffset + 30 + localNameLen + localExtraLen;
      final raw = bytes.sublist(dataStart, dataStart + compSize);
      Uint8List data;
      if (method == 0) {
        data = raw;
      } else if (method == 8) {
        data = Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
      } else {
        continue;
      }
      entries.add(ZipEntry(name, data));
    }
    return entries;
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
