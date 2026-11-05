# CLI reference

The CLI is a thin wrapper over `mmx_core`; it is useful for batch processing,
regression tests and CI. Run it from `packages/mmx_core`:

```sh
dart run bin/mmx.dart --help
```

For a release build:

```sh
dart compile exe bin/mmx.dart -o mmx
```

## Commands

| Command | Purpose |
|---|---|
| `info <file>` | Print counts, bounds, area, volume, components, boundary loops, non-manifold edges and defects. |
| `repair <in> <out>` | Weld, close cracks, remove duplicate faces, split non-manifold surfaces and fill holes. |
| `remesh <in> <out> --edge <len>` | Isotropic remesh; `--iters`, `--adaptive 0-1`, `--preserve-sharp`, `--debug-topology`. |
| `reduce <in> <out>` | Decimate with `--percent`, `--faces`, `--uniform` or `--max-dev`. |
| `solid <in> <out>` | Make Solid with `--mode fast|accurate|blocky`, `--res`, `--offset`, `--smooth`. |
| `boolean <a> <b> <out> --op ...` | Union/intersection/difference; `--precise` uses the mesh-level path with grid fallback. |
| `hollow <in> <out>` | Hollow with `--thickness`, `--holes`, `--hole-radius`. |
| `offset <in> <out> --distance <d>` | Surface offset. |
| `supports <in> <out>` | Support forest; `--angle`, `--density`, `--bed`. |
| `pack <out> <in...>` | 2D bed packing; `--bed`, `--quality`. |
| `slice <in>` | Layer slicing; `--layer`. |
| `analyze <in>` | Thickness/overhang analysis; `--thickness`, `--overhang`. |
| `mirror <in> <out>` | Mirror; `--plane`, `--keep`, `--weld`. |
| `flip <in> <out>` | Flip normals. |
| `smooth <in> <out>` | Taubin smoothing; `--iters`. |
| `drop` / `center` | Place on the bed. |
| `duplicate <in> <out>` | Translate a copy. |
| `combine <out> <in...>` | Join meshes. |
| `pattern <in> <out>` | Grid array; `--nx`, `--nz`, `--gap`. |
| `primitive <in> <out>` | Fit box/cylinder/sphere; `--kind`. |
| `measure <in>` | Dimensions, area, volume, shells. |
| `clearance <a> <b>` | Minimum inter-object distance. |
| `convert <in> <out>` | Convert formats, including `.mix`. |
| `render <in> <out.png>` | Software render; `--width`, `--height`, `--yaw`, `--pitch`, `--wire`. |

## Examples

```sh
# Repair and decimate a scan
dart run bin/mmx.dart repair scan.obj clean.obj
dart run bin/mmx.dart reduce clean.obj low.stl --percent 0.25

# Prepare for printing
dart run bin/mmx.dart hollow clean.obj shell.stl --thickness 2 --holes 4
dart run bin/mmx.dart supports shell.stl supported.stl --angle 45
dart run bin/mmx.dart analyze supported.stl

# Convert a Meshmixer scene
dart run bin/mmx.dart convert scene.mix scene.obj
```

The CLI exits non-zero on a missing input file or an unsupported command.
Geometry operations are deterministic for the same input and parameters.
