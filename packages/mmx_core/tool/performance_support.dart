import 'dart:convert';

const performanceSchema = 2;
const performanceCases = [
  '12k/reduce',
  '12k/remesh',
  '12k/solid',
  '100k/reduce',
  '100k/remesh',
  '100k/solid',
];

/// The timing gate applies only to compatible, complete measurements. Memory
/// is reported without a budget until a representative limit is established.
Map<String, Object?> comparePerformance(
    Map<String, dynamic> baseline, Map<String, dynamic> candidate) {
  validatePerformanceReport(baseline);
  validatePerformanceReport(candidate);
  for (final key in ['host', 'runtime', 'configuration', 'inputs']) {
    if (!_equal(baseline[key], candidate[key])) {
      throw FormatException('Incompatible benchmark $key; no comparison made');
    }
  }
  final previous = baseline['cases'] as Map<String, dynamic>;
  final current = candidate['cases'] as Map<String, dynamic>;
  final regressions = <String>[];
  final changes = <String, double>{};
  for (final name in performanceCases) {
    final before = previous[name]['medianMicroseconds'] as int;
    final after = current[name]['medianMicroseconds'] as int;
    changes[name] = (after / before - 1) * 100;
    // Integer arithmetic keeps the exact 20% boundary inclusive.
    if (after * 100 > before * 120) regressions.add(name);
  }
  return {
    'maxRegressionPercent': 20,
    'medianChangePercent': changes,
    'regressions': regressions,
    'passed': regressions.isEmpty,
  };
}

void validatePerformanceReport(Map<String, dynamic> report) {
  if (report['schema'] != performanceSchema) {
    throw const FormatException('Expected benchmark schema 2; legacy reports '
        'lack sufficient provenance for a regression gate');
  }
  final host = _map(report, 'host');
  for (final field in ['id', 'os', 'osVersion', 'architecture', 'cpuModel']) {
    if (host[field] is! String || (host[field] as String).trim().isEmpty) {
      throw FormatException('Missing host.$field');
    }
  }
  for (final field in ['logicalProcessors', 'physicalMemoryBytes']) {
    if (host[field] is! int || host[field] <= 0) {
      throw FormatException('Invalid host.$field');
    }
  }
  final runtime = _map(report, 'runtime');
  if (runtime['mode'] != 'aot' ||
      runtime['dart'] is! String ||
      (runtime['dart'] as String).isEmpty) {
    throw const FormatException('Expected an identified AOT Dart runtime');
  }
  final config = _map(report, 'configuration');
  if (config['workloadVersion'] != 2 ||
      config['warmups'] != 1 ||
      config['samples'] != 3 ||
      config['isolation'] != 'process-per-case') {
    throw const FormatException('Unsupported benchmark configuration');
  }
  final inputs = _map(report, 'inputs');
  if (!_sameKeys(inputs, const ['12k', '100k'])) {
    throw const FormatException('Expected both benchmark input meshes');
  }
  for (final size in inputs.keys) {
    final input = _map(inputs, size);
    for (final field in ['vertices', 'faces']) {
      if (input[field] is! int || input[field] <= 0) {
        throw FormatException('Invalid input $size $field');
      }
    }
    if (input['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(input['sha256'] as String)) {
      throw FormatException('Invalid input $size sha256');
    }
  }
  final cases = _map(report, 'cases');
  if (!_sameKeys(cases, performanceCases)) {
    throw const FormatException('Expected exactly six benchmark cases');
  }
  for (final name in performanceCases) {
    final result = _map(cases, name);
    final samples = result['samplesMicroseconds'];
    if (samples is! List ||
        samples.length != 3 ||
        samples.any((n) => n is! int || n <= 0)) {
      throw FormatException('Expected three positive latency samples: $name');
    }
    final sorted = samples.cast<int>().toList()..sort();
    if (result['medianMicroseconds'] != sorted[1]) {
      throw FormatException('Median does not match raw samples: $name');
    }
    if (result['processPeakRssBytes'] is! int ||
        result['processPeakRssBytes'] <= 0) {
      throw FormatException('Missing process peak RSS: $name');
    }
  }
}

Map<String, dynamic> decodePerformanceReport(String contents) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Benchmark report must be a JSON object');
  }
  return decoded;
}

Map<String, dynamic> _map(Map<String, dynamic> parent, String key) {
  final result = parent[key];
  if (result is! Map<String, dynamic>) {
    throw FormatException('Expected object: $key');
  }
  return result;
}

bool _sameKeys(Map<String, dynamic> value, List<String> expected) =>
    value.length == expected.length && expected.every(value.containsKey);

bool _equal(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _equal(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _equal(a[i], b[i]));
  }
  return a == b;
}
