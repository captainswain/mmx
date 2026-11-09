import 'dart:io';
import 'dart:typed_data';

/// Flush a sibling temporary file before replacing the destination. If rename
/// fails, the original remains intact and the temporary file is removed.
Future<void> writeFileAtomically(String path, Uint8List bytes) async {
  final target = File(path).absolute;
  final directory = await target.parent.createTemp('.mmx-write-');
  final temporary = File('${directory.path}/payload');
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
  } finally {
    await directory.delete(recursive: true);
  }
}
