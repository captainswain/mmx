import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmx_studio/state/recovery_store.dart';

Future<String> dartExecutable() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString());
  final flutter = (config['packages'] as List).singleWhere(
    (package) => package['name'] == 'flutter',
  );
  final package = Directory.fromUri(
    configFile.uri.resolve(flutter['rootUri'] as String),
  );
  final sdk = package.parent.parent;
  return File.fromUri(
    sdk.uri.resolve(
      'bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}',
    ),
  ).path;
}

void main() {
  late Directory directory;
  final stores = <RecoveryStore>[];
  Future<RecoveryStore> open() async {
    final store = await RecoveryStore.open(directory);
    stores.add(store);
    return store;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mmx-recovery-store-');
  });
  tearDown(() async {
    for (final store in stores.reversed) {
      await store.close();
    }
    stores.clear();
    await directory.delete(recursive: true);
  });

  test(
    'live sessions have distinct files and cannot claim or clear each other',
    () async {
      final first = await open(), second = await open();
      expect(first.path, isNot(second.path));
      await first.withPath((path) => File(path).writeAsString('first unsaved'));
      await second.withPath(
        (path) => File(path).writeAsString('second unsaved'),
      );
      expect(await first.claimNext(), isNull);
      expect(await second.claimNext(), isNull);
      await first.clear();
      expect(await File(first.path).exists(), isFalse);
      expect(await File(second.path).readAsString(), 'second unsaved');
      await first.close();
      expect(await File(second.path).readAsString(), 'second unsaved');
    },
  );

  test('released session data becomes recoverable without deletion', () async {
    final first = await open(), second = await open();
    await first.withPath((path) => File(path).writeAsString('recover me'));
    expect(await second.claimNext(), isNull);
    await first.close();
    final candidate = await second.claimNext();
    expect(candidate, isNotNull);
    expect(candidate!.path, first.path);
    expect(await File(candidate.path).readAsString(), 'recover me');
    await candidate.release();
    expect(await File(first.path).readAsString(), 'recover me');
    // Declining does not repeatedly prompt in the same session.
    expect(await second.claimNext(), isNull);
    final third = await open();
    expect((await third.claimNext())!.path, first.path);
  });

  test(
    'legacy data stays leased through read failure and survives decline',
    () async {
      final legacy = File.fromUri(directory.uri.resolve('recovery.mmx'));
      await legacy.writeAsString('unreadable legacy project');
      final first = await open(), second = await open();
      final candidate = await first.claimNext();
      // RecoveryStore canonicalizes directory aliases (Windows short names and
      // macOS /var -> /private/var). Identity matters, not the input spelling.
      expect(
        await FileSystemEntity.identical(candidate!.path, legacy.path),
        isTrue,
      );
      await expectLater(
        candidate.withPath<void>((_) async {
          throw const FormatException('cannot decode recovery');
        }),
        throwsFormatException,
      );
      expect(await second.claimNext(), isNull);
      await candidate.release();
      expect(await legacy.readAsString(), 'unreadable legacy project');
      final retry = await second.claimNext();
      expect(
        await FileSystemEntity.identical(retry!.path, legacy.path),
        isTrue,
      );
      // Only an explicit discard or successful persisted recovery removes data.
      await retry.clear();
      expect(await legacy.exists(), isFalse);
    },
  );

  test(
    'clear waits for a queued write and preserves another session',
    () async {
      final first = await open(), second = await open();
      await second.withPath(
        (path) => File(path).writeAsString('other session'),
      );
      final releaseWrite = Completer<void>();
      final writing = first.withPath((path) async {
        await releaseWrite.future;
        await File(path).writeAsString('pending autosave');
      });
      var cleared = false;
      final clearing = first.clear().then((_) => cleared = true);
      try {
        await Future<void>.delayed(Duration.zero);
        expect(cleared, isFalse);
      } finally {
        releaseWrite.complete();
      }
      await writing;
      await clearing;
      expect(await File(first.path).exists(), isFalse);
      expect(await File(second.path).readAsString(), 'other session');
    },
  );

  test('close holds ownership until queued writes finish', () async {
    final first = await open(), second = await open();
    await first.withPath(
      (path) => File(path).writeAsString('initial autosave'),
    );
    final releaseWrite = Completer<void>();
    final writing = first.withPath((path) async {
      await releaseWrite.future;
      await File(path).writeAsString('completed autosave');
    });
    var closed = false;
    final closing = first.close().then((_) => closed = true);
    try {
      expect(await second.claimNext(), isNull);
      expect(closed, isFalse);
      expect(() => first.clear(), throwsStateError);
    } finally {
      releaseWrite.complete();
    }
    await writing;
    await closing;
    final candidate = await second.claimNext();
    expect(candidate!.path, first.path);
    expect(await File(candidate.path).readAsString(), 'completed autosave');
  });

  test(
    'newest abandoned candidate is offered first and unrelated files ignored',
    () async {
      final old = File.fromUri(directory.uri.resolve('recovery.mmx'));
      final recent = File.fromUri(
        directory.uri.resolve('recovery-abandoned.mmx'),
      );
      final unrelated = File.fromUri(directory.uri.resolve('user-project.mmx'));
      await old.writeAsString('older');
      await old.setLastModified(DateTime.utc(2020));
      await recent.writeAsString('recent');
      await recent.setLastModified(DateTime.utc(2021));
      await unrelated.writeAsString('never recovery');
      final store = await open();
      expect(
        await FileSystemEntity.identical(
          (await store.claimNext())!.path,
          recent.path,
        ),
        isTrue,
      );
      expect(
        await FileSystemEntity.identical(
          (await store.claimNext())!.path,
          old.path,
        ),
        isTrue,
      );
      expect(await store.claimNext(), isNull);
      await store.close();
      expect(await unrelated.readAsString(), 'never recovery');
      expect(await old.readAsString(), 'older');
      expect(await recent.readAsString(), 'recent');
    },
  );

  test(
    'close joins pending candidate discovery before releasing handles',
    () async {
      await File.fromUri(directory.uri.resolve('recovery.mmx'))
          .writeAsString('abandoned');
      final store = await open();
      var discoveryFinished = false;
      final discovery = store.claimNext().then<void>(
        (_) => discoveryFinished = true,
        onError: (Object error) {
          expect(error, isA<StateError>());
          discoveryFinished = true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      await store.close();
      expect(discoveryFinished, isTrue);
      await discovery;
      final next = await open();
      expect(await next.claimNext(), isNotNull);
      await next.close();
    },
  );

  test(
    'OS lease excludes another process and automatically releases on crash',
    () async {
      final source = File('lib/state/recovery_store.dart').absolute.uri
          .toString();
      final script = File.fromUri(directory.uri.resolve('lease_child.dart'));
      await script.writeAsString('''
import 'dart:io';
import ${jsonEncode(source)};
Future<void> main(List<String> args) async {
  final store = await RecoveryStore.open(Directory(args.single));
  await store.withPath((path) => File(path).writeAsString('child unsaved'));
  stdout.writeln(store.path);
  await stdin.first;
  exit(23); // Deliberately omit close(): the OS must release the crash lease.
}
''');
      final process = await Process.start(await dartExecutable(), [
        script.path,
        directory.path,
      ]);
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
        final childPath = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 20));
        final observer = await open();
        expect(await observer.claimNext(), isNull);
        process.stdin.writeln('simulate crash');
        await process.stdin.flush();
        expect(
          await process.exitCode.timeout(const Duration(seconds: 20)),
          23,
          reason: await errors,
        );
        final recovered = await observer.claimNext();
        expect(recovered!.path, childPath);
        expect(await File(recovered.path).readAsString(), 'child unsaved');
      } finally {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 20));
        await process.stdin.close();
      }
    },
  );
}
