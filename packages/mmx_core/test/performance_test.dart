import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/performance_support.dart';

Map<String, dynamic> report() => {
      'schema': 2,
      'host': {
        'id': 'test-host',
        'os': 'linux',
        'osVersion': 'test-os-version',
        'architecture': 'linux_x64',
        'cpuModel': 'test-cpu',
        'logicalProcessors': 8,
        'physicalMemoryBytes': 16000000000,
      },
      'runtime': {'mode': 'aot', 'dart': 'test-runtime'},
      'configuration': {
        'workloadVersion': 2,
        'warmups': 1,
        'samples': 3,
        'isolation': 'process-per-case',
      },
      'inputs': {
        for (final size in ['12k', '100k'])
          size: {
            'vertices': 6000,
            'faces': 12000,
            'sha256': List.filled(64, 'a').join(),
          },
      },
      'cases': {
        for (final name in performanceCases)
          name: {
            'samplesMicroseconds': [99, 100, 101],
            'medianMicroseconds': 100,
            'processPeakRssBytes': 1000000,
          },
      },
    };

void setMedian(Map<String, dynamic> value, int median) {
  value['cases']['12k/reduce']['medianMicroseconds'] = median;
  value['cases']['12k/reduce']
      ['samplesMicroseconds'] = [median - 1, median, median + 1];
}

void main() {
  test('identical reports and exactly 20% slower pass', () {
    expect(comparePerformance(report(), report())['passed'], isTrue);
    final candidate = report();
    setMedian(candidate, 120);
    expect(comparePerformance(report(), candidate)['passed'], isTrue);
    setMedian(candidate, 50);
    expect(comparePerformance(report(), candidate)['passed'], isTrue);
  });

  test('a slower median fails even when other cases improve', () {
    final candidate = report();
    setMedian(candidate, 121);
    final comparison = comparePerformance(report(), candidate);
    expect(comparison['passed'], isFalse);
    expect(comparison['regressions'], ['12k/reduce']);
    expect((comparison['medianChangePercent'] as Map)['12k/reduce'],
        closeTo(21, 1e-9));
  });

  test('host identity, hardware and runtime must match', () {
    for (final field in ['id', 'cpuModel', 'osVersion', 'architecture']) {
      final candidate = report();
      candidate['host'][field] = 'another-host';
      expect(
          () => comparePerformance(report(), candidate), throwsFormatException,
          reason: field);
    }
    final candidate = report();
    candidate['runtime']['dart'] = 'another-runtime';
    expect(
        () => comparePerformance(report(), candidate), throwsFormatException);
  });

  test('different prepared input or operator parameters are incompatible', () {
    final candidate = report();
    candidate['inputs']['100k']['sha256'] = List.filled(64, 'b').join();
    expect(
        () => comparePerformance(report(), candidate), throwsFormatException);
    final changedParameters = report();
    changedParameters['configuration']['solidResolution'] = 48;
    expect(() => comparePerformance(report(), changedParameters),
        throwsFormatException);
  });

  test('legacy provenance and JIT measurements are refused', () {
    final legacy = report()..['schema'] = 1;
    expect(() => comparePerformance(legacy, report()), throwsFormatException);
    final jit = report();
    jit['runtime']['mode'] = 'jit';
    expect(() => comparePerformance(report(), jit), throwsFormatException);
  });

  test('missing or extra cases cannot silently pass', () {
    final missing = report();
    (missing['cases'] as Map).remove('100k/remesh');
    expect(() => comparePerformance(report(), missing), throwsFormatException);
    final extra = report();
    extra['cases']['new-case'] = extra['cases']['12k/reduce'];
    expect(() => comparePerformance(report(), extra), throwsFormatException);
  });

  test('raw samples must be positive and agree with reported medians', () {
    for (final invalid in [0, -1, '100', null]) {
      final candidate = report();
      candidate['cases']['12k/reduce']
          ['samplesMicroseconds'] = [99, invalid, 101];
      expect(
          () => comparePerformance(report(), candidate), throwsFormatException,
          reason: '$invalid');
    }
    final candidate = report();
    candidate['cases']['12k/reduce']['medianMicroseconds'] = 99;
    expect(
        () => comparePerformance(report(), candidate), throwsFormatException);
  });

  test('missing memory and malformed report objects are refused', () {
    final candidate = report();
    (candidate['cases']['12k/reduce'] as Map).remove('processPeakRssBytes');
    expect(
        () => comparePerformance(report(), candidate), throwsFormatException);
    expect(() => decodePerformanceReport('[]'), throwsFormatException);
    expect(
        () => decodePerformanceReport('invalid JSON'), throwsFormatException);
    candidate['host'] = [];
    expect(() => validatePerformanceReport(candidate), throwsFormatException);
  });

  test('CLI returns 0, 1, 2 for pass, regression and incompatibility',
      () async {
    final temporary = Directory.systemTemp.createTempSync('mmx-gate-test-');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final baseline = File('${temporary.path}/baseline.json')
      ..writeAsStringSync(jsonEncode(report()));
    final candidate = File('${temporary.path}/candidate.json');
    Future<ProcessResult> compare(Map<String, dynamic> value) {
      candidate.writeAsStringSync(jsonEncode(value));
      return Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/performance.dart',
        '--baseline=${baseline.path}',
        '--compare=${candidate.path}',
      ]);
    }

    final passed = await compare(report());
    expect(passed.exitCode, 0, reason: '${passed.stderr}');
    expect(jsonDecode(passed.stdout)['passed'], isTrue);
    final regression = report();
    setMedian(regression, 121);
    final failed = await compare(regression);
    expect(failed.exitCode, 1, reason: '${failed.stderr}');
    expect(jsonDecode(failed.stdout)['regressions'], ['12k/reduce']);
    final incompatible = report();
    incompatible['host']['id'] = 'another-host';
    final rejected = await compare(incompatible);
    expect(rejected.exitCode, 2);
    expect(rejected.stderr, contains('Incompatible benchmark host'));
  });

  test('CLI rejects JIT timing captures', () async {
    final result = await Process.run(Platform.resolvedExecutable,
        ['run', 'tool/performance.dart', '--host-id=test-host']);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('Measurements require an AOT executable'));
  });
}
