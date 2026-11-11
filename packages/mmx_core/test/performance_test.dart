import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';
import 'package:test/test.dart';

import '../tool/corpus/analytic_meshes.dart';
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
        'validation': 'closed-oriented-edge-manifold',
      },
      'inputs': {
        for (final size in ['12k', '100k'])
          size: {
            'vertices': 6000,
            'faces': 12000,
            'sha256': List.filled(64, 'a').join(),
            'topology': {
              'boundaryEdges': 0,
              'nonManifoldEdges': 0,
              'inconsistentWindingEdges': 0,
            },
          },
      },
      'cases': {
        for (final name in performanceCases)
          name: {
            'samplesMicroseconds': [99, 100, 101],
            'medianMicroseconds': 100,
            'processPeakRssBytes': 1000000,
            'topology': {
              'boundaryEdges': 0,
              'nonManifoldEdges': 0,
              'inconsistentWindingEdges': 0,
            },
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

  test('a single slower median fails', () {
    final candidate = report();
    setMedian(candidate, 121);
    final comparison = comparePerformance(report(), candidate);
    expect(comparison['passed'], isFalse);
    expect(comparison['regressions'], ['12k/reduce']);
    expect((comparison['medianChangePercent'] as Map)['12k/reduce'],
        closeTo(21, 1e-9));
  });

  test('large integer samples cannot overflow the threshold comparison', () {
    final baseline = report();
    final candidate = report();
    setMedian(baseline, 100000000000000000);
    setMedian(candidate, 121000000000000000);
    expect(comparePerformance(baseline, candidate)['passed'], isFalse);
  });

  test('independent topology checks detect holes, duplicates and winding', () {
    final cube = analyticCube();
    expect(benchmarkTopology(cube).values, everyElement(0));
    final open =
        TriMesh(cube.positions, Uint32List.fromList(cube.indices.sublist(3)));
    expect(benchmarkTopology(open)['boundaryEdges'], 3);
    final duplicate = TriMesh(
        cube.positions,
        Uint32List.fromList([
          ...cube.indices,
          ...cube.indices.take(3),
        ]));
    expect(benchmarkTopology(duplicate)['nonManifoldEdges'], 3);
    final reversed = cube.clone();
    final a = reversed.indices[0];
    reversed.indices[0] = reversed.indices[1];
    reversed.indices[1] = a;
    expect(benchmarkTopology(reversed)['inconsistentWindingEdges'], 3);
  });

  test('invalid topology cannot pass a performance gate', () {
    for (final metric in [
      'boundaryEdges',
      'nonManifoldEdges',
      'inconsistentWindingEdges',
    ]) {
      final candidate = report();
      candidate['cases']['100k/reduce']['topology'][metric] = 3;
      expect(
          () => comparePerformance(report(), candidate), throwsFormatException,
          reason: metric);
      final input = report();
      input['inputs']['100k']['topology'][metric] = 3;
      expect(() => comparePerformance(report(), input), throwsFormatException,
          reason: 'input $metric');
    }
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
