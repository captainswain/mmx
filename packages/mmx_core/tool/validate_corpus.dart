import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:mmx_core/mmx_core.dart';
import 'corpus/analytic_meshes.dart';

/// Reproducible analytical checks and optional externally acquired reference
/// fixtures. This never claims a Meshmixer oracle ran when no reference exists.
void main(List<String> args) {
  try {
    final records = args.isEmpty
        ? validateAnalyticalCorpus()
        : args.length == 2 && args.first == '--reference'
            ? validateReferenceCorpus(File(args[1]))
            : throw const FormatException(
                'Usage: validate_corpus.dart [--reference manifest.json]');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'kind': args.isEmpty ? 'analytical' : 'external-reference',
      'cases': records,
      'passed': records.every((r) => r['passed'] == true),
    }));
    if (records.any((r) => r['passed'] != true)) exitCode = 1;
  } catch (e) {
    stderr.writeln('Corpus validation failed: $e');
    exitCode = 2;
  }
}

Map<String, Object> metrics(TriMesh mesh) => {
      'vertices': mesh.vertexCount,
      'faces': mesh.faceCount,
      'volume': mesh.signedVolume().abs(),
      'area': mesh.surfaceArea(),
      'components': MeshTopology(mesh).components().$2,
      'boundaryLoops': MeshTopology(mesh).boundaryLoops().length,
      'nonManifoldEdges': MeshTopology(mesh).nonManifoldEdges().length,
      'consistentWinding': consistentWinding(mesh),
      'valid': mesh.validate().isEmpty,
    };

List<Map<String, Object>> validateAnalyticalCorpus() {
  final rows = <Map<String, Object>>[];
  void check(String name, TriMesh mesh, double volume, int components,
      double relativeTolerance) {
    final m = metrics(mesh);
    final relativeError = volume == 0
        ? (m['volume'] as double).abs()
        : ((m['volume'] as double) - volume).abs() / volume;
    rows.add({
      'name': name,
      'evidence': 'analytical',
      'metrics': m,
      'expectedVolume': volume,
      'expectedComponents': components,
      'relativeVolumeTolerance': relativeTolerance,
      'relativeVolumeError': relativeError,
      'passed': m['valid'] == true &&
          m['boundaryLoops'] == 0 &&
          m['nonManifoldEdges'] == 0 &&
          m['consistentWinding'] == true &&
          m['components'] == components &&
          relativeError <= relativeTolerance
    });
  }

  for (final scale in [.001, 1.0, 1000.0]) {
    final cube = analyticCube(scale: scale),
        volume = 8 * math.pow(scale, 3).toDouble();
    check('cube/$scale', cube, volume, 1, 1e-5);
    final reflected = cube.clone()..transform(scale4(-2));
    check('reflection/$scale', reflected, volume * 8, 1, 1e-5);
    final half = PlaneCut.cut(cube, point: [0, 0, 0], normal: [0, 1, 0]);
    check('plane-cut/$scale', half, volume / 2, 1, 1e-5);
    final distant = cube.clone()..transform(translation4(scale * 4, 0, 0));
    check(
        'boolean-disjoint-union/$scale',
        PreciseBoolean.compute(cube, distant, BooleanOp.union),
        volume * 2,
        2,
        1e-5);
    check('boolean-empty-intersection/$scale',
        PreciseBoolean.compute(cube, distant, BooleanOp.intersection), 0, 0, 0);
  }
  final cube = analyticCube();
  final overlap = analyticCube()..transform(translation4(1, 0, 0));
  for (final entry in {
    BooleanOp.union: 12.0,
    BooleanOp.intersection: 4.0,
    BooleanOp.difference: 4.0
  }.entries) {
    check(
        'grid-${entry.key.name}',
        Solidifier.boolean(cube, overlap, entry.key, resolution: 48).mesh,
        entry.value,
        1,
        .08);
    final precise = PreciseBoolean.computeDetailed(cube, overlap, entry.key,
        resolution: 48);
    check('precise-${entry.key.name}', precise.mesh, entry.value, 1, .08);
    rows.last['usedFallback'] = precise.usedFallback;
    if (precise.fallbackReason != null) {
      rows.last['fallbackReason'] = precise.fallbackReason!;
    }
  }
  check(
      'solid-cube', Solidifier.makeSolid(cube, resolution: 48).mesh, 8, 1, .08);
  return rows;
}

/// Manifest schema is documented in tool/corpus/README.md. Every tolerance is
/// supplied explicitly by the fixture owner; no accepted differences are hidden.
List<Map<String, Object>> validateReferenceCorpus(File manifest) {
  final root = manifest.absolute.parent;
  final manifestBytes = manifest.readAsBytesSync();
  final manifestHash = sha256.convert(manifestBytes).toString();
  final document =
      jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  if (document['schema'] != 1 ||
      document['source'] is! String ||
      (document['source'] as String).trim().isEmpty) {
    throw const FormatException('Reference source provenance is required');
  }
  final rows = <Map<String, Object>>[];
  final fileHashes = <String, String>{};
  TriMesh load(String name) {
    final file = File.fromUri(root.uri.resolve(name));
    if (file.lengthSync() > MeshIO.maxFileBytes) {
      throw FormatException('Reference fixture exceeds 256 MiB: $name');
    }
    final bytes = file.readAsBytesSync();
    fileHashes[name] = sha256.convert(bytes).toString();
    return MeshIO.readBytes(name, bytes);
  }

  for (final c in document['cases'] as List) {
    final input = load(c['input'] as String);
    final reference = load(c['reference'] as String);
    final p = (c['parameters'] ?? <String, dynamic>{}) as Map<String, dynamic>;
    final result = switch (c['operation']) {
      'solid' => Solidifier.makeSolid(input,
              resolution: (p['resolution'] as num).toInt())
          .mesh,
      'reduce' => Decimator.reduce(input,
          percentage: (p['percentage'] as num).toDouble()),
      'remesh' => IsotropicRemesher.remesh(input,
          targetEdgeLength: (p['edgeLength'] as num).toDouble(),
          iterations: (p['iterations'] as num).toInt()),
      'hollow' => Solidifier.hollow(input,
              thickness: (p['thickness'] as num).toDouble(),
              holes: 0,
              resolution: (p['resolution'] as num).toInt())
          .mesh,
      'boolean' => PreciseBoolean.compute(input, load(c['operand'] as String),
          BooleanOp.values.byName(p['op'] as String),
          resolution: (p['resolution'] as num).toInt()),
      _ => throw FormatException(
          'Unsupported reference operation: ${c['operation']}'),
    };
    final expected = metrics(reference), actual = metrics(result);
    final tolerances = c['tolerances'] as Map<String, dynamic>;
    double tolerance(String name) {
      final value = (tolerances[name] as num).toDouble();
      if (!value.isFinite || value < 0) {
        throw FormatException('Invalid $name tolerance');
      }
      return value;
    }

    final volumeTolerance = tolerance('volumeAbsolute');
    final areaTolerance = tolerance('areaAbsolute');
    final distanceTolerance = tolerance('surfaceDistance');

    final volumeError =
        ((actual['volume'] as double) - (expected['volume'] as double)).abs();
    final areaError =
        ((actual['area'] as double) - (expected['area'] as double)).abs();
    final distance = result.vertexCount == 0 && reference.vertexCount == 0
        ? 0.0
        : result.vertexCount == 0 || reference.vertexCount == 0
            ? double.infinity
            : math.max(
                DeviationAnalysis.run(result, reference,
                        maxSamples: result.vertexCount)
                    .maxDistance,
                DeviationAnalysis.run(reference, result,
                        maxSamples: reference.vertexCount)
                    .maxDistance);
    final pass = actual['valid'] == true &&
        expected['valid'] == true &&
        actual['boundaryLoops'] == expected['boundaryLoops'] &&
        actual['nonManifoldEdges'] == expected['nonManifoldEdges'] &&
        actual['components'] == expected['components'] &&
        actual['consistentWinding'] == expected['consistentWinding'] &&
        volumeError <= volumeTolerance &&
        areaError <= areaTolerance &&
        distance <= distanceTolerance;
    rows.add({
      'name': c['name'] as String,
      'source': document['source'] as String,
      'manifestSha256': manifestHash,
      'operation': c['operation'] as String,
      'parameters': Map<String, dynamic>.of(p),
      'input': c['input'] as String,
      'inputSha256': fileHashes[c['input']]!,
      'reference': c['reference'] as String,
      'referenceSha256': fileHashes[c['reference']]!,
      if (c['operation'] == 'boolean') ...{
        'operand': c['operand'] as String,
        'operandSha256': fileHashes[c['operand']]!,
      },
      'metrics': actual,
      'referenceMetrics': expected,
      'volumeError': volumeError,
      'areaError': areaError,
      'symmetricVertexSurfaceDistance':
          distance.isFinite ? distance : 'infinite',
      'tolerances': tolerances,
      'passed': pass
    });
  }
  if (rows.isEmpty) {
    throw const FormatException('Reference corpus cannot be empty');
  }
  return rows;
}
