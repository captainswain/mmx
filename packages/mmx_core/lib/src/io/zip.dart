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
    if (entries.length > 4096 ||
        entries.map((e) => e.name).toSet().length != entries.length ||
        entries.fold<int>(0, (n, e) => n + e.data.length) > 256 * 1024 * 1024) {
      throw const FormatException('Invalid or oversized ZIP entries');
    }
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;
    for (final e in entries) {
      final nameBytes = utf8.encode(e.name);
      if (nameBytes.isEmpty || nameBytes.length > 65535) {
        throw const FormatException('Invalid ZIP filename');
      }
      final compressed = ZLibEncoder(raw: true, level: 6).convert(e.data);
      final crc = _crc32(e.data);
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0x800, Endian.little)
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
        ..setUint16(8, 0x800, Endian.little)
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

  static List<ZipEntry> read(Uint8List bytes,
      {int maxExpandedBytes = 256 * 1024 * 1024, int maxEntries = 4096}) {
    if (bytes.length > maxExpandedBytes) {
      throw const FormatException('Archive exceeds size limit');
    }
    final bd = ByteData.sublistView(bytes);
    void bounds(int offset, int length) {
      if (offset < 0 || length < 0 || offset > bytes.length - length) {
        throw const FormatException('Truncated archive');
      }
    }

    var eocd = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50 &&
          i + 22 + bd.getUint16(i + 20, Endian.little) == bytes.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw const FormatException('Missing ZIP directory');
    final count = bd.getUint16(eocd + 10, Endian.little);
    if (count > maxEntries ||
        bd.getUint16(eocd + 4, Endian.little) != 0 ||
        bd.getUint16(eocd + 6, Endian.little) != 0 ||
        bd.getUint16(eocd + 8, Endian.little) != count) {
      throw const FormatException('Unsupported ZIP directory');
    }
    var pos = bd.getUint32(eocd + 16, Endian.little);
    final directoryStart = pos;
    if (pos + bd.getUint32(eocd + 12, Endian.little) != eocd) {
      throw const FormatException('Invalid ZIP directory');
    }
    final entries = <ZipEntry>[];
    final names = <String>{};
    var total = 0;
    for (var i = 0; i < count; i++) {
      bounds(pos, 46);
      if (bd.getUint32(pos, Endian.little) != 0x02014b50) {
        throw const FormatException('Invalid ZIP entry');
      }
      final flags = bd.getUint16(pos + 8, Endian.little);
      final method = bd.getUint16(pos + 10, Endian.little);
      final crc = bd.getUint32(pos + 16, Endian.little);
      final compSize = bd.getUint32(pos + 20, Endian.little);
      final size = bd.getUint32(pos + 24, Endian.little);
      final nameLen = bd.getUint16(pos + 28, Endian.little);
      final extraLen = bd.getUint16(pos + 30, Endian.little);
      final commentLen = bd.getUint16(pos + 32, Endian.little);
      final local = bd.getUint32(pos + 42, Endian.little);
      if (bd.getUint16(pos + 34, Endian.little) != 0 ||
          compSize == 0xffffffff ||
          size == 0xffffffff ||
          local == 0xffffffff) {
        throw const FormatException(
            'ZIP64 and multidisk archives are unsupported');
      }
      if ((flags & ~0x80e) != 0 ||
          (method != 0 && method != 8) ||
          size > maxExpandedBytes - total) {
        throw const FormatException('Unsupported or oversized ZIP entry');
      }
      bounds(pos + 46, nameLen + extraLen + commentLen);
      final name = utf8.decode(bytes.sublist(pos + 46, pos + 46 + nameLen));
      if (!names.add(name)) throw const FormatException('Duplicate ZIP entry');
      pos += 46 + nameLen + extraLen + commentLen;
      if (local + 30 > directoryStart) {
        throw const FormatException('Local ZIP header overlaps directory');
      }
      bounds(local, 30);
      if (bd.getUint32(local, Endian.little) != 0x04034b50 ||
          bd.getUint16(local + 6, Endian.little) != flags ||
          bd.getUint16(local + 8, Endian.little) != method) {
        throw const FormatException('Invalid local ZIP header');
      }
      if ((flags & 8) == 0 &&
          (bd.getUint32(local + 14, Endian.little) != crc ||
              bd.getUint32(local + 18, Endian.little) != compSize ||
              bd.getUint32(local + 22, Endian.little) != size)) {
        throw const FormatException(
            'Local ZIP sizes or CRC differ from directory');
      }
      final localNameLen = bd.getUint16(local + 26, Endian.little);
      final start =
          local + 30 + localNameLen + bd.getUint16(local + 28, Endian.little);
      bounds(local + 30, localNameLen);
      if (utf8.decode(bytes.sublist(local + 30, local + 30 + localNameLen)) !=
              name ||
          start + compSize > directoryStart) {
        throw const FormatException('Invalid ZIP payload');
      }
      bounds(start, compSize);
      final raw = Uint8List.sublistView(bytes, start, start + compSize);
      final sink = _LimitedSink(size);
      if (method == 0) {
        sink.add(raw);
      } else {
        final decoder = ZLibDecoder(raw: true).startChunkedConversion(sink);
        for (var j = 0; j < raw.length; j += 16384) {
          decoder.add(Uint8List.sublistView(
              raw, j, j + 16384 < raw.length ? j + 16384 : raw.length));
        }
        decoder.close();
      }
      final data = sink.bytes.takeBytes();
      if (data.length != size || _crc32(data) != crc) {
        throw const FormatException('ZIP integrity check failed');
      }
      total += size;
      entries.add(ZipEntry(name, data));
    }
    if (pos != eocd) throw const FormatException('ZIP directory size mismatch');
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

class _LimitedSink implements Sink<List<int>> {
  final int limit;
  int count = 0;
  final bytes = BytesBuilder(copy: false);
  _LimitedSink(this.limit);
  @override
  void add(List<int> data) {
    count += data.length;
    if (count > limit) {
      throw const FormatException('Expanded ZIP entry exceeds limit');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
