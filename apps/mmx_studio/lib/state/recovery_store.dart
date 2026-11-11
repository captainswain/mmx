import 'dart:async';
import 'dart:io';
import 'dart:math';

/// One session's recovery file and leases for previous crashed sessions.
///
/// Locks live in separate, stable sidecar files so atomic replacement of the
/// project does not change the locked inode. Sidecars are deliberately retained
/// after release: unlinking one can create two independently locked identities.
class RecoveryStore {
  RecoveryStore._(this._directory, this._own);

  final Directory _directory;
  final RecoveryLease _own;
  final Set<String> _seen = {};
  final Set<RecoveryLease> _claimed = {};
  bool _closing = false;
  Future<void>? _closeTask;
  Future<void> _claims = Future<void>.value();

  static Future<RecoveryStore> open(Directory directory) async {
    await directory.create(recursive: true);
    final canonical = Directory(await directory.resolveSymbolicLinks());
    final random = Random.secure();
    for (var attempt = 0; attempt < 10; attempt++) {
      final token =
          '${DateTime.now().microsecondsSinceEpoch}-$pid-'
          '${random.nextInt(0x7fffffff).toRadixString(16)}';
      final path = File.fromUri(canonical.uri.resolve('recovery-$token.mmx'))
          .path;
      final lease = await RecoveryLease._claim(path);
      if (lease == null) continue;
      if (await File(path).exists()) {
        await lease.release();
        continue;
      }
      return RecoveryStore._(canonical, lease);
    }
    throw FileSystemException(
      'Unable to acquire a recovery session lease',
      canonical.path,
    );
  }

  String get path => _own.path;

  /// Keep ownership until asynchronous encoding/writing has finished. Closing
  /// the store waits for these callbacks, even if its widget has been disposed.
  Future<T> withPath<T>(Future<T> Function(String path) action) {
    if (_closing) throw StateError('Recovery store is closed');
    return _own.withPath(action);
  }

  /// Delete only this session's recovery data, after its queued writes finish.
  Future<void> clear() {
    if (_closing) throw StateError('Recovery store is closed');
    return _own.clear();
  }

  /// Claim the newest available crashed-session or legacy recovery file.
  /// Live sessions are skipped without inspecting/deleting their contents.
  /// A candidate is offered at most once by this store, even when declined.
  Future<RecoveryLease?> claimNext() {
    if (_closing) throw StateError('Recovery store is closed');
    final task = _claims.then((_) => _claimNext());
    _claims = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<RecoveryLease?> _claimNext() async {
    if (_closing) throw StateError('Recovery store is closed');
    final candidates = <(DateTime, String)>[];
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name != 'recovery.mmx' &&
          !(name.startsWith('recovery-') && name.endsWith('.mmx'))) {
        continue;
      }
      if (RecoveryLease._key(entity.path) == RecoveryLease._key(path) ||
          _seen.contains(entity.path)) {
        continue;
      }
      try {
        candidates.add(((await entity.stat()).modified, entity.path));
      } on FileSystemException {
        // Another session may have cleared its recovery during enumeration.
      }
    }
    candidates.sort((a, b) {
      final newest = b.$1.compareTo(a.$1);
      return newest == 0 ? a.$2.compareTo(b.$2) : newest;
    });
    for (final candidate in candidates) {
      if (_closing) throw StateError('Recovery store is closed');
      final lease = await RecoveryLease._claim(candidate.$2);
      if (lease == null) continue;
      if (_closing) {
        await lease.release();
        throw StateError('Recovery store is closed');
      }
      if (await FileSystemEntity.type(candidate.$2, followLinks: false) !=
          FileSystemEntityType.file) {
        await lease.release();
        continue;
      }
      // Recheck after the asynchronous filesystem query: close() must not miss
      // a claim that was still being acquired when it took its lease snapshot.
      if (_closing) {
        await lease.release();
        throw StateError('Recovery store is closed');
      }
      _seen.add(candidate.$2);
      _claimed.add(lease);
      return lease;
    }
    return null;
  }

  /// Release ownership without removing recovery data. OS locks also release
  /// automatically if the process crashes before this method can run.
  Future<void> close() {
    _closing = true;
    return _closeTask ??= _finishClose();
  }

  Future<void> _finishClose() async {
    // A pending claim may already have opened a sidecar that was not yet added
    // to _claimed. Join it before declaring all handles closed (Windows needs
    // this before directory cleanup).
    await _claims;
    await Future.wait([
      _own.release(),
      for (final lease in _claimed) lease.release(),
    ]);
  }
}

/// An exclusive lease held through prompting, loading, writing and cleanup.
/// Call clear() only after explicit discard or successful recovery persistence.
class RecoveryLease {
  RecoveryLease._(this.path, this._handle);

  // OS file locks can be process-scoped. This registry additionally protects
  // separate screens/stores in the UI isolate from claiming the same file.
  static final Set<String> _held = {};
  final String path;
  final RandomAccessFile _handle;
  Future<void> _pending = Future<void>.value();
  Future<void>? _releaseTask;
  bool _closing = false;

  static String _key(String path) =>
      Platform.isWindows ? path.replaceAll('\\', '/').toLowerCase() : path;

  static Future<RecoveryLease?> _claim(String path) async {
    final key = _key(path);
    if (!_held.add(key)) return null;
    RandomAccessFile? handle;
    try {
      handle = await File('$path.lock').open(mode: FileMode.append);
      // Nonblocking exclusive lock: an active session is simply unavailable.
      await handle.lock(FileLock.exclusive);
      return RecoveryLease._(path, handle);
    } on FileSystemException {
      try {
        await handle?.close();
      } finally {
        _held.remove(key);
      }
      return null;
    } catch (_) {
      try {
        await handle?.close();
      } finally {
        _held.remove(key);
      }
      rethrow;
    }
  }

  Future<T> withPath<T>(Future<T> Function(String path) action) {
    if (_closing) throw StateError('Recovery lease is released');
    final task = _pending.then((_) => action(path));
    // Failure of one write must not prevent subsequent cleanup or unlock.
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> clear() => withPath((path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  });

  Future<void> release() {
    _closing = true;
    return _releaseTask ??= _finishRelease();
  }

  Future<void> _finishRelease() async {
    await _pending;
    try {
      await _handle.unlock();
    } finally {
      try {
        await _handle.close();
      } finally {
        _held.remove(_key(path));
      }
    }
  }
}
