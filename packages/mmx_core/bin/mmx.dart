import 'dart:io';
import 'dart:typed_data';

import 'package:mmx_core/mmx_core.dart';

const String _usage = '''
mmx — cross-platform mesh kernel CLI (Meshmixer-class operators)

  mmx info <file>
  mmx repair <in> <out> [--weld 1e-5]
  mmx remesh <in> <out> --edge <len> [--iters 6] [--adaptive 0-1]
  mmx reduce <in> <out> --percent <0-1> | --faces <n> [--uniform] [--max-dev <d>]
  mmx solid <in> <out> [--mode fast|accurate|blocky] [--res 128] [--offset 0] [--smooth 0]
  mmx boolean <a> <b> <out> --op union|intersection|difference [--precise] [--edge <len>]
  mmx hollow <in> <out> --thickness <t> [--holes 3] [--hole-radius <r>]
  mmx offset <in> <out> --distance <d>
  mmx supports <in> <out> [--angle 45] [--density 0.5] [--bed 0]
  mmx pack <out> <in...> [--bed 200] [--quality 1]
  mmx slice <in> [--layer 0.2]
  mmx analyze <in> [--thickness 1.0] [--overhang 45]
  mmx mirror <in> <out> [--plane <x>] [--keep] [--weld <tol>]
  mmx flip <in> <out>
  mmx smooth <in> <out> [--iters 8]
  mmx drop <in> <out> [--bed 0]
  mmx center <in> <out> [--bed 0]
  mmx duplicate <in> <out> [--dx 0] [--dy 0] [--dz 0]
  mmx combine <out> <in...>
  mmx pattern <in> <out> [--nx 3] [--nz 2] [--gap 2]
  mmx primitive <in> <out> [--kind box|cylinder|sphere]
  mmx measure <in>
  mmx clearance <a> <b>
  mmx convert <in> <out> [.mix supported]
  mmx render <in> <out.png> [--width 960] [--height 640] [--yaw 0.6] [--pitch 0.35] [--wire]
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    stdout.writeln(_usage);
    return;
  }
  final cmd = args.first;
  final rest = args.sublist(1);
  final positional = <String>[];
  final flags = <String, String>{};
  for (var i = 0; i < rest.length; i++) {
    final a = rest[i];
    if (a.startsWith('--')) {
      final key = a.substring(2);
      if (i + 1 < rest.length && !rest[i + 1].startsWith('--')) {
        flags[key] = rest[++i];
      } else {
        flags[key] = 'true';
      }
    } else {
      positional.add(a);
    }
  }

  TriMesh load(String path) {
    final f = File(path);
    if (!f.existsSync()) {
      stderr.writeln('missing file: $path');
      exit(2);
    }
    return MeshIO.readBytes(path, f.readAsBytesSync());
  }

  void save(String path, TriMesh mesh) {
    File(path).writeAsBytesSync(MeshIO.writeBytes(path, mesh));
    stdout.writeln('wrote $path (${mesh.vertexCount} verts, ${mesh.faceCount} faces)');
  }

  double flag(String name, double fallback) =>
      double.tryParse(flags[name] ?? '') ?? fallback;

  switch (cmd) {
    case 'info':
      {
        final mesh = load(positional[0]);
        final topo = MeshTopology(mesh);
        final b = mesh.bounds();
        stdout.writeln('file: ${positional[0]}');
        stdout.writeln('verts: ${mesh.vertexCount}  faces: ${mesh.faceCount}');
        stdout.writeln('bounds: ${b.minX.toStringAsFixed(2)},${b.minY.toStringAsFixed(2)},'
            '${b.minZ.toStringAsFixed(2)} .. ${b.maxX.toStringAsFixed(2)},'
            '${b.maxY.toStringAsFixed(2)},${b.maxZ.toStringAsFixed(2)}');
        stdout.writeln('area: ${mesh.surfaceArea().toStringAsFixed(3)}  '
            'volume: ${mesh.signedVolume().toStringAsFixed(3)}');
        final comps = topo.components().$2;
        stdout.writeln('components: $comps  '
            'boundaryLoops: ${topo.boundaryLoops().length}  '
            'nonManifoldEdges: ${topo.nonManifoldEdges().length}');
        stdout.writeln('avgValence: ${topo.averageValence().toStringAsFixed(2)}');
        final defects = MeshInspector.scan(mesh);
        final counts = <String, int>{};
        for (final d in defects) {
          counts[d.kind.name] = (counts[d.kind.name] ?? 0) + 1;
        }
        stdout.writeln('defects: $counts');
      }
    case 'repair':
      {
        var mesh = load(positional[0]);
        mesh = Weld.weldVertices(mesh, tolerance: flag('weld', 1e-5));
        mesh = Weld.weldCracks(mesh, tolerance: flag('weld', 1e-5));
        Weld.removeDuplicateFaces(mesh);
        mesh = MeshInspector.splitNonManifold(mesh);
        mesh = HoleFiller.fill(mesh, mode: HoleFillMode.smooth);
        save(positional[1], mesh);
      }
    case 'remesh':
      {
        final mesh = load(positional[0]);
        final edge = flag('edge', mesh.bounds().diagonal / 100);
        final out = IsotropicRemesher.remesh(mesh,
            targetEdgeLength: edge,
            iterations: flag('iters', 6).toInt(),
            adaptiveDensity: flag('adaptive', 0));
        save(positional[1], out);
      }
    case 'reduce':
      {
        final mesh = load(positional[0]);
        final faces = flags.containsKey('faces') ? int.parse(flags['faces']!) : null;
        final pct = flags.containsKey('percent') ? flag('percent', 0.5) : null;
        final maxDev = flags.containsKey('max-dev') ? flag('max-dev', 0.0) : null;
        final out = Decimator.reduce(mesh,
            targetFaceCount: faces,
            percentage: pct,
            uniform: flags.containsKey('uniform'),
            maxDeviation: maxDev == null || maxDev <= 0 ? null : maxDev);
        save(positional[1], out);
      }
    case 'solid':
      {
        final mesh = load(positional[0]);
        final mode = switch (flags['mode'] ?? 'accurate') {
          'fast' => SolidMode.fast,
          'blocky' => SolidMode.blocky,
          _ => SolidMode.accurate,
        };
        final r = Solidifier.makeSolid(mesh,
            mode: mode,
            resolution: flag('res', 128).toInt(),
            offset: flag('offset', 0),
            smoothing: flag('smooth', 0).toInt());
        stdout.writeln('grid ${r.gridResolution} cell ${r.cellSize.toStringAsFixed(4)} '
            '${r.elapsedMs}ms');
        save(positional[1], r.mesh);
      }
    case 'boolean':
      {
        final a = load(positional[0]);
        final b = load(positional[1]);
        final op = switch (flags['op'] ?? 'union') {
          'difference' => BooleanOp.difference,
          'intersection' => BooleanOp.intersection,
          _ => BooleanOp.union,
        };
        final r = flags.containsKey('precise')
            ? PreciseBoolean.compute(a, b, op,
                edgeLength: flags['edge'] == null
                    ? null
                    : double.parse(flags['edge']!),
                resolution: flag('res', 160).toInt())
            : Solidifier.boolean(a, b, op, resolution: flag('res', 160).toInt())
                .mesh;
        save(positional[2], r);
      }
    case 'hollow':
      {
        final mesh = load(positional[0]);
        final r = Solidifier.hollow(mesh,
            thickness: flag('thickness', mesh.bounds().diagonal * 0.03),
            holes: flag('holes', 3).toInt(),
            holeRadius: flag('hole-radius', mesh.bounds().diagonal * 0.02),
            resolution: flag('res', 128).toInt());
        save(positional[1], r.mesh);
      }
    case 'offset':
      {
        final mesh = load(positional[0]);
        final r = Solidifier.offsetSolid(mesh, flag('distance', 1),
            resolution: flag('res', 128).toInt());
        save(positional[1], r.mesh);
      }
    case 'supports':
      {
        final mesh = load(positional[0]);
        final settings = SupportSettings(
          overhangAngleDegrees: flag('angle', 45),
          density: flag('density', 0.5),
          postDiameter: flag('post', 2),
          baseDiameter: flag('base', 6),
        );
        final r = SupportGenerator.generate(mesh, settings: settings, bedY: flag('bed', 0));
        stdout.writeln('posts ${r.postCount} struts ${r.strutCount}');
        save(positional[1], r.supports);
      }
    case 'pack':
      {
        final out = positional[0];
        final meshes = positional.sublist(1).map(load).toList();
        final r = Packer.pack(meshes,
            bedWidth: flag('bed', 200), bedDepth: flag('bed', 200),
            quality: flag('quality', 1).toInt());
        stdout.writeln('placed ${r.placed.length}/${meshes.length} '
            'utilisation ${(r.bedUtilization * 100).toStringAsFixed(1)}%');
        final merged = <TriMesh>[];
        for (final p in r.placed) {
          final m = meshes[p.index].clone();
          m.transform(Float64List.fromList(p.transform));
          merged.add(m);
        }
        var total = 0;
        for (final m in merged) {
          total += m.vertexCount;
        }
        final pos = Float32List(total * 3);
        var pi = 0;
        final idx = <int>[];
        var offset = 0;
        for (final m in merged) {
          pos.setRange(pi, pi + m.positions.length, m.positions);
          pi += m.positions.length;
          for (var i = 0; i < m.indices.length; i++) {
            idx.add(m.indices[i] + offset);
          }
          offset += m.vertexCount;
        }
        save(out, TriMesh(pos, Uint32List.fromList(idx)));
      }
    case 'slice':
      {
        final mesh = load(positional[0]);
        final r = Slicer.slice(mesh, layerHeight: flag('layer', 0.2));
        stdout.writeln('layers ${r.layers.length}');
        for (final l in r.layers.take(3)) {
          stdout.writeln('  y=${l.y.toStringAsFixed(2)} loops=${l.loops.length} '
              'closed=${l.loops.where((x) => x.closed).length}');
        }
      }
    case 'analyze':
      {
        final mesh = load(positional[0]);
        final t = ThicknessAnalysis.run(mesh, threshold: flag('thickness', 1.0));
        final o = OverhangAnalysis.run(mesh, angleDegrees: flag('overhang', 45));
        final s = StabilityAnalysis.run(mesh);
        final mp = MassProperties.compute(mesh);
        stdout.writeln('mass: volume=${mp.volume.toStringAsFixed(2)} '
            'area=${mp.surfaceArea.toStringAsFixed(2)} '
            'com=${mp.centerOfMass.map((v) => v.toStringAsFixed(2)).toList()}');
        stdout.writeln('thickness: min=${t.minThickness.toStringAsFixed(3)} '
            'mean=${t.meanThickness.toStringAsFixed(3)} '
            'belowThreshold=${t.belowThresholdCount}');
        stdout.writeln('overhang: faces=${o.faceCount} '
            'area=${o.overhangArea.toStringAsFixed(2)} '
            '(${(100 * o.overhangArea / (o.totalArea == 0 ? 1 : o.totalArea)).toStringAsFixed(1)}%)');
        stdout.writeln('stability: insideBase=${s.centerInsideSupport} '
            'tipAngle=${s.minTipAngleDegrees.toStringAsFixed(1)}deg '
            'contactArea=${s.bedContactArea.toStringAsFixed(2)}');
      }
    case 'mirror':
      {
        final mesh = load(positional[0]);
        final b = mesh.bounds();
        final out = Mirror.mirror(mesh,
            point: <double>[flag('plane', b.maxX), 0, 0],
            normal: <double>[1, 0, 0],
            keepOriginal: flags['keep'] == 'true',
            weldTolerance: flag('weld', b.diagonal * 1e-4));
        save(positional[1], out);
      }
    case 'separate':
      {
        final mesh = load(positional[0]);
        final shells = ShellSeparator.separate(mesh);
        stdout.writeln('${shells.length} shells');
        final base = positional[1];
        final stem = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
        final ext = base.contains('.') ? base.substring(base.lastIndexOf('.')) : '.obj';
        for (var i = 0; i < shells.length; i++) {
          save('${stem}_${i + 1}$ext', shells[i]);
        }
      }
    case 'merge':
      {
        final meshes = positional.sublist(1).map(load).toList();
        var totalV = 0;
        var totalF = 0;
        for (final m in meshes) {
          totalV += m.vertexCount;
          totalF += m.faceCount;
        }
        final pos = Float32List(totalV * 3);
        final idx = Uint32List(totalF * 3);
        var pi = 0, ii = 0, off = 0;
        for (final m in meshes) {
          pos.setRange(pi, pi + m.positions.length, m.positions);
          pi += m.positions.length;
          for (var i = 0; i < m.indices.length; i++) {
            idx[ii++] = m.indices[i] + off;
          }
          off += m.vertexCount;
        }
        save(positional[0], TriMesh(pos, idx));
      }
    case 'combine':
      {
        final meshes = positional.sublist(1).map(load).toList();
        save(positional[0], Modify.combine(meshes));
      }
    case 'flip':
      save(positional[1], Modify.flipNormals(load(positional[0])));
    case 'smooth':
      save(
          positional[1],
          Modify.smooth(load(positional[0]),
              iterations: flag('iters', 8).toInt()));
    case 'drop':
      save(positional[1],
          Modify.dropToBed(load(positional[0]), bedY: flag('bed', 0)));
    case 'center':
      save(positional[1],
          Modify.centerOnBed(load(positional[0]), bedY: flag('bed', 0)));
    case 'duplicate':
      save(
          positional[1],
          Modify.duplicate(load(positional[0]), offset: <double>[
            flag('dx', 0),
            flag('dy', 0),
            flag('dz', 0),
          ]));
    case 'pattern':
      save(
          positional[1],
          Modify.makePattern(load(positional[0]),
              countX: flag('nx', 3).toInt(),
              countZ: flag('nz', 2).toInt(),
              gap: flag('gap', 2)));
    case 'primitive':
      {
        final kind = switch (flags['kind'] ?? 'box') {
          'sphere' => PrimitiveKind.sphere,
          'cylinder' => PrimitiveKind.cylinder,
          _ => PrimitiveKind.box,
        };
        save(positional[1], Modify.fitPrimitive(load(positional[0]), kind));
      }
    case 'measure':
      {
        final r = Modify.measure(load(positional[0]));
        stdout.writeln('dimensions: ${r.dimensions.map((v) => v.toStringAsFixed(3)).join(' x ')}');
        stdout.writeln('area: ${r.surfaceArea.toStringAsFixed(3)}  '
            'volume: ${r.volume.toStringAsFixed(3)}');
        stdout.writeln('centroid: ${r.centroid.map((v) => v.toStringAsFixed(3)).join(', ')}');
        stdout.writeln('shells: ${r.shellCount}  boundaryEdges: ${r.boundaryEdgeCount}  '
            'watertight: ${r.watertight}');
      }
    case 'clearance':
      {
        final gap = Modify.clearance(load(positional[0]), load(positional[1]));
        stdout.writeln('clearance: ${gap.toStringAsFixed(3)}');
      }
    case 'convert':
      save(positional[1], load(positional[0]));
    case 'render':
      {
        final mesh = load(positional[0]);
        final b = mesh.bounds();
        final cam = Camera(
          yaw: flag('yaw', 0.6),
          pitch: flag('pitch', 0.35),
          distance: 1,
        );
        cam.frame(b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ);
        final opts = RenderOptions(
          width: flag('width', 960).toInt(),
          height: flag('height', 640).toInt(),
          wireframe: flags['wire'] == 'true',
          bedSize: flag('bed', 200),
        );
        final sw = Stopwatch()..start();
        final rgba = Rasterizer.render(<RenderObject>[
          RenderObject(mesh, transform: identity4(), color: <double>[0.78, 0.72, 0.62]),
        ], cam, opts);
        sw.stop();
        final png = PngEncoder.encodeRGBA(rgba, opts.width, opts.height);
        File(positional[1]).writeAsBytesSync(png);
        stdout.writeln('rendered ${opts.width}x${opts.height} in ${sw.elapsedMilliseconds}ms '
            '-> ${positional[1]}');
      }
    default:
      stderr.writeln('unknown command: $cmd\n$_usage');
      exit(1);
  }
}
