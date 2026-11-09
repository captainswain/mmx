import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:mmx_core/mmx_core.dart';

import 'performance_support.dart';

const _usage = '''Run from packages/mmx_core after:
  dart compile exe tool/performance.dart -o /tmp/mmx-performance

Capture: /tmp/mmx-performance --host-id=my-fixed-host > baseline.json
Compare: /tmp/mmx-performance --host-id=my-fixed-host --baseline=baseline.json
Recheck saved reports: dart run tool/performance.dart \\
  --baseline=baseline.json --compare=candidate.json

Exit codes: 0 pass/capture, 1 median regression >20%, 2 invalid/incompatible.
Reports contain raw operator latencies and process-lifetime peak RSS. RSS
includes launch, input loading, warmup, measured runs and result checks.
On Linux it can include inherited launcher/preparation residency across exec;
this is an upper bound, not an isolated operator allocation measurement.
Use a quiet, fixed host; these timings do not measure Studio responsiveness.
''';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('host-id')
    ..addOption('baseline')
    ..addOption('compare')
    ..addOption('worker', hide: true)
    ..addOption('input', hide: true);
  try {
    final options = parser.parse(args);
    if (options.flag('help')) {
      stdout.write(_usage);
      return;
    }
    if (options.rest.isNotEmpty) {
      throw const FormatException('Use --baseline=FILE for a comparison');
    }
    final baselinePath = options.option('baseline');
    final baseline = baselinePath == null
        ? null
        : decodePerformanceReport(File(baselinePath).readAsStringSync());
    if (baseline != null) validatePerformanceReport(baseline);
    final comparisonPath = options.option('compare');
    if (comparisonPath != null) {
      if (baseline == null) {
        throw const FormatException('--compare requires --baseline');
      }
      final candidate =
          decodePerformanceReport(File(comparisonPath).readAsStringSync());
      final comparison = comparePerformance(baseline, candidate);
      _writeJson(comparison);
      if (comparison['passed'] == false) exitCode = 1;
      return;
    }
    if (!const bool.fromEnvironment('dart.vm.product')) {
      throw const FormatException('Measurements require an AOT executable; '
          'compile with dart compile exe first');
    }
    final worker = options.option('worker');
    if (worker != null) {
      if (!performanceCases.contains(worker) ||
          options.option('input') == null) {
        throw const FormatException('Invalid benchmark worker arguments');
      }
      _writeJson(_runCase(worker, File(options.option('input')!)));
      return;
    }
    final hostId = options.option('host-id');
    if (hostId == null ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$').hasMatch(hostId)) {
      throw const FormatException('Provide --host-id with a stable, '
          'non-sensitive machine label (letters, digits, dots, dashes)');
    }
    final host = _host(hostId);
    final runtime = {'mode': 'aot', 'dart': Platform.version};
    final configuration = {
      'workloadVersion': 2,
      'warmups': 1,
      'samples': 3,
      'isolation': 'process-per-case',
      'validation': 'closed-oriented-edge-manifold',
      'reducePercentage': 0.5,
      'remeshDiagonalDivisor': 60,
      'remeshIterations': 2,
      'solidResolution': 96,
    };
    final fixture = File('test/fixtures/models/sphere.obj');
    final fixtureBytes = fixture.readAsBytesSync();
    final mesh = MeshIO.readBytes('sphere.obj', fixtureBytes);
    stderr
        .writeln('Preparing benchmark inputs (excluded from operator timing)');
    final large = Decimator.reduce(
        IsotropicRemesher.linearSubdivide(
            IsotropicRemesher.linearSubdivide(mesh)),
        targetFaceCount: 100000);
    final temporary = Directory.systemTemp.createTempSync('mmx-performance-');
    try {
      final inputs = <String, Object?>{};
      for (final entry in {'12k': mesh, '100k': large}.entries) {
        final bytes = _encodeMesh(entry.value);
        File('${temporary.path}/${entry.key}.mesh').writeAsBytesSync(bytes);
        inputs[entry.key] = {
          'sha256': sha256.convert(bytes).toString(),
          'vertices': entry.value.vertexCount,
          'faces': entry.value.faceCount,
          'topology': _validateMesh(entry.value, 'input ${entry.key}'),
        };
      }
      final report = <String, dynamic>{
        'schema': performanceSchema,
        'recordedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'host': host,
        'runtime': runtime,
        'configuration': configuration,
        'inputs': inputs,
        'provenance': {
          'gitRevision': _command('git', ['rev-parse', 'HEAD']),
          'gitStatus': _command('git', ['status', '--porcelain']),
          'executableSha256':
              await _fileHash(File(Platform.resolvedExecutable)),
          'fixtureSha256': sha256.convert(fixtureBytes).toString(),
          'kernelWorkingTreeSha256': await _directoryHash(Directory('lib')),
          'benchmarkWorkingTreeSha256': await _directoryHash(Directory('tool'),
              names: ['performance.dart', 'performance_support.dart']),
        },
        'cases': <String, Object?>{},
      };
      // Check compatibility before spending minutes running the operators.
      if (baseline != null) {
        comparePerformance(baseline, {...report, 'cases': baseline['cases']});
      }
      final cases = report['cases'] as Map<String, Object?>;
      for (final name in performanceCases) {
        stderr.writeln('Measuring $name');
        final started = Stopwatch()..start();
        final process = await Process.run(Platform.resolvedExecutable, [
          '--worker=$name',
          '--input=${temporary.path}/${name.split('/').first}.mesh',
        ]);
        started.stop();
        if (process.exitCode != 0) {
          throw StateError('Benchmark $name failed: ${process.stderr}');
        }
        cases[name] = {
          ...decodePerformanceReport(process.stdout as String),
          'workerWallMicroseconds': started.elapsedMicroseconds,
        };
      }
      validatePerformanceReport(report);
      if (baseline != null) {
        final comparison = comparePerformance(baseline, report);
        report['comparison'] = comparison;
        if (comparison['passed'] == false) exitCode = 1;
      }
      _writeJson(report);
    } finally {
      temporary.deleteSync(recursive: true);
    }
  } on Object catch (error) {
    stderr.writeln('Benchmark failed: $error');
    exitCode = 2;
  }
}

Map<String, Object?> _runCase(String name, File input) {
  final bytes = input.readAsBytesSync();
  final mesh = _decodeMesh(bytes);
  TriMesh run() => switch (name.split('/').last) {
        'reduce' => Decimator.reduce(mesh, percentage: .5),
        'remesh' => IsotropicRemesher.remesh(mesh,
            targetEdgeLength: mesh.bounds().diagonal / 60, iterations: 2),
        'solid' => Solidifier.makeSolid(mesh, resolution: 96).mesh,
        _ => throw ArgumentError.value(name),
      };
  final inputRss = ProcessInfo.currentRss;
  var topology = _validateMesh(run(), name);
  final samples = <int>[];
  final rss = <int>[];
  final outputFaces = <int>[];
  for (var i = 0; i < 3; i++) {
    final watch = Stopwatch()..start();
    final result = run();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
    rss.add(ProcessInfo.currentRss);
    outputFaces.add(result.faceCount);
    topology = _validateMesh(result, name);
  }
  if (sha256.convert(_encodeMesh(mesh)) != sha256.convert(bytes)) {
    throw StateError('Operator mutated benchmark input: $name');
  }
  final sorted = samples.toList()..sort();
  return {
    'samplesMicroseconds': samples,
    'medianMicroseconds': sorted[1],
    'minMicroseconds': sorted.first,
    'maxMicroseconds': sorted.last,
    // Process-lifetime upper bound, including fork/exec launcher residency on
    // Linux. It must not be interpreted as isolated operator or Dart heap peak.
    'processPeakRssBytes': ProcessInfo.maxRss,
    'rssAfterInputBytes': inputRss,
    'rssAfterOperationBytes': rss,
    'outputFaces': outputFaces,
    'topology': topology,
  };
}

Map<String, int> _validateMesh(TriMesh mesh, String context) {
  if (mesh.faceCount == 0 ||
      mesh.validate().isNotEmpty ||
      !mesh.signedVolume().isFinite ||
      mesh.signedVolume() <= 0) {
    throw StateError('Invalid $context mesh');
  }
  final topology = benchmarkTopology(mesh);
  if (topology.values.any((count) => count != 0)) {
    throw StateError('Invalid closed $context mesh: $topology');
  }
  return topology;
}

// Private temporary interchange, deliberately independent of public IO formats.
// Typed arrays use the native byte order; parent and workers use one executable.
Uint8List _encodeMesh(TriMesh mesh) {
  final header = ByteData(16)
    ..setUint32(0, mesh.positions.length)
    ..setUint32(4, mesh.indices.length)
    ..setUint32(8, mesh.faceGroups?.length ?? 0)
    ..setUint32(12, mesh.vertexColors?.length ?? 0);
  final data = BytesBuilder(copy: false)..add(header.buffer.asUint8List());
  for (final values in [
    mesh.positions,
    mesh.indices,
    mesh.faceGroups,
    mesh.vertexColors
  ]) {
    if (values != null) {
      data.add(values.buffer
          .asUint8List(values.offsetInBytes, values.lengthInBytes));
    }
  }
  return data.takeBytes();
}

TriMesh _decodeMesh(Uint8List bytes) {
  final header = ByteData.sublistView(bytes, 0, 16);
  var offset = 16;
  Uint8List take(int length) {
    final data = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return data;
  }

  final positions = take(header.getUint32(0) * 4).buffer.asFloat32List();
  final indices = take(header.getUint32(4) * 4).buffer.asUint32List();
  final groups = take(header.getUint32(8) * 2).buffer.asUint16List();
  final colors = take(header.getUint32(12) * 4).buffer.asFloat32List();
  if (offset != bytes.length) {
    throw const FormatException('Invalid input length');
  }
  return TriMesh(positions, indices,
      faceGroups: groups.isEmpty ? null : groups,
      vertexColors: colors.isEmpty ? null : colors);
}

Map<String, Object?> _host(String id) {
  String? model;
  int? memory;
  final details = <String, String>{};
  if (Platform.isLinux) {
    final cpu = File('/proc/cpuinfo').readAsStringSync();
    model = RegExp(r'^(?:model name|Hardware)\s*:\s*(.+)$', multiLine: true)
        .firstMatch(cpu)
        ?.group(1)
        ?.trim();
    final mem = RegExp(r'^MemTotal:\s*(\d+)', multiLine: true)
        .firstMatch(File('/proc/meminfo').readAsStringSync())
        ?.group(1);
    if (mem != null) memory = int.parse(mem) * 1024;
    for (final entry in {
      'cpuGovernor': '/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor',
      'cgroupMemoryMax': '/sys/fs/cgroup/memory.max',
      'cgroupCpuMax': '/sys/fs/cgroup/cpu.max',
    }.entries) {
      final file = File(entry.value);
      if (file.existsSync()) {
        details[entry.key] = file.readAsStringSync().trim();
      }
    }
    final affinity = RegExp(r'^Cpus_allowed_list:\s*(.+)$', multiLine: true)
        .firstMatch(File('/proc/self/status').readAsStringSync())
        ?.group(1);
    if (affinity != null) details['cpuAffinity'] = affinity.trim();
  } else if (Platform.isMacOS) {
    model = _command('sysctl', ['-n', 'machdep.cpu.brand_string']) ??
        _command('sysctl', ['-n', 'hw.model']);
    memory = int.tryParse(_command('sysctl', ['-n', 'hw.memsize']) ?? '');
  } else if (Platform.isWindows) {
    model = _command('powershell', [
      '-NoProfile',
      '-Command',
      '(Get-CimInstance Win32_Processor | Select-Object -First 1).Name'
    ]);
    memory = int.tryParse(_command('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory'
        ]) ??
        '');
  }
  if (model == null || memory == null) {
    throw StateError('Cannot identify CPU model and physical RAM on this host');
  }
  return {
    'id': id,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'architecture': Platform.version.split(' on ').last.replaceAll('"', ''),
    'cpuModel': model,
    'logicalProcessors': Platform.numberOfProcessors,
    'physicalMemoryBytes': memory,
    'executionEnvironment': details,
  };
}

String? _command(String executable, List<String> arguments) {
  try {
    final result = Process.runSync(executable, arguments);
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  } on ProcessException {
    return null;
  }
}

Future<String> _fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<String> _directoryHash(Directory directory,
    {List<String>? names}) async {
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => names == null || names.contains(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final entries = <String>[];
  for (final file in files) {
    entries.add(
        '${file.path.replaceAll('\\', '/')}\u0000${await _fileHash(file)}');
  }
  return sha256.convert(utf8.encode(entries.join('\n'))).toString();
}

void _writeJson(Object value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
