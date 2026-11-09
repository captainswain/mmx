# Geometry validation corpus

Run `dart run tool/validate_corpus.dart` from `packages/mmx_core`. It emits JSON
and exits 1 for a failing case, 2 for invalid input. The fixtures are independently
specified cubes with analytical volumes, not saved Meshmixer outputs. The 22
analytical cases check manifoldness, boundary loops, consistent winding, component count, and
explicit volume tolerances. Cases cover scales 0.001, 1 and 1000, reflection,
plane cut, exact disjoint/empty boolean behavior, overlapping grid and mesh-level
booleans (with fallback diagnostics), and solidification. The grid tolerance is
8% at resolution 48; exact operations use 0.001%. These are engineering acceptance
limits, not recovered Autodesk constants.

For a real external comparison, first acquire outputs independently and retain
reproduction commands, application version and input settings. No Meshmixer
binary or Oracle result is bundled or downloaded by this tool. Wine is installed
on the development host, but a usable Meshmixer installation was not found at the
previous `/data/re/meshmixer` location.

Acquire the application through [Autodesk's official listing](https://marketplace.autodesk.com/apps/2e40e347-0369-4603-b83f-ecab324aed0f).
The [official remote API](https://github.com/meshmixer/mm-api#what-is-mm-api)
controls a running Meshmixer application; the API headers alone do not provide
an independent geometry implementation or measured reference outputs.

Invoke `dart run tool/validate_corpus.dart --reference path/to/manifest.json`.
Paths resolve relative to the manifest. Example structure (replace the example
paths and provenance with actual measured fixtures):

```json
{
  "schema": 1,
  "source": "Actual application/version, reproduction command and fixture provenance",
  "cases": [{
    "name": "solid cube",
    "operation": "solid",
    "input": "input.obj",
    "reference": "measured-output.obj",
    "parameters": {"resolution": 48},
    "tolerances": {"volumeAbsolute": 0.64, "areaAbsolute": 1.0, "surfaceDistance": 0.15}
  }]
}
```

Supported operations are `solid`, `reduce` (`percentage`), `remesh` (`edgeLength`,
`iterations`), `hollow` (`thickness`, `resolution`, no holes), and `boolean`
(`operand` path plus `op` and `resolution`). Tolerances must be explicit finite
nonnegative values. Comparison reports actual and reference metrics and a
symmetric vertex-to-surface distance; this sampled-vertex metric is not the
continuous Hausdorff distance. Topology/component mismatches always fail.

Every comparison records the manifest and consumed input/reference/operand
SHA-256 hashes, operation and parameters. Keep that report with the actual
fixtures, application version and reproduction record: a filename alone cannot
identify external evidence. Hashes establish which bytes were compared; they do
not establish that an external application produced them. Synthetic runner tests
remain explicitly labelled as synthetic.
