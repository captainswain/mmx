# Production readiness

Target: reliable Linux, Windows and macOS core mesh workflows and CLI.
**Status: hardening and local automated validation complete; production
distribution still requires the external acceptance below.** This supersedes the historical
finish/remediation plans; full Meshmixer parity is a separate target.

## Implemented plan

### Desktop interaction and persistence

- Geometry workers are owned isolates: cancel terminates synchronous CPU work,
  stale results cannot replace a newer document, and failed edits restore scene,
  camera, project path and original-source metadata. Status reports operation
  phases rather than an invented completion percentage.
- Rendering coalesces requests; spatial data caches key on document/object/mesh
  and transform state. Viewport translation, rotation, uniform scale and local
  pivot editing commit one undo entry. Sculpt drags group stamps into one entry
  and cancel rolls back the whole stroke.
- Native `.mmx` projects preserve objects, IDs, transforms, colors/groups, pivots,
  visibility, targets, camera, selection and original imported `.mix` bytes.
  Save/Save As is separate from mesh export. Writes flush a temporary sibling
  before replacement; failed reads keep the current scene.
- Native dialogs, dirty prompts, unit selection, Ctrl/Command shortcuts and
  recovery autosaves are implemented. Recovery waits for pending writes before
  cleanup and preserves unreadable recovery data instead of overwriting it.
  Per-session files and exclusive leases prevent other app instances from
  overwriting, recovering or deleting a live session's autosave. Legacy recovery
  files remain recoverable; closing a lease preserves its unsaved data.
- Open/save/import remain locked through final previews. Completion listeners
  cannot have newer edits marked clean; invalid incoming cameras/previews roll
  back the prior scene. A preview failure after a successful disk save leaves
  that save successful and releases the operation lock.
- Procedural startup geometry replaces redistributed demo assets. Release
  packaging rejects accidental Autodesk fixture assets in the app bundle.

### File and kernel correctness

- OBJ/OFF/PLY use bounded concave triangulation. PLY decodes ASCII and either
  binary byte order by property schema, including reordered fields, lists,
  colors/groups and unknown elements. STL validates grammar and binary sizes.
- ZIP bounds expanded content to 256 MiB and 4096 entries, checks CRC/size/method
  consistency and rejects unsafe names. 3MF resolves relationships, units,
  transforms, repeated instances and component graphs; unsupported material or
  extension semantics fail explicitly. `.mix` rewrite consumes records in order
  and fails rather than silently replacing metadata with a minimal mesh.
- Plane clipping preserves winding and attributes; reflected transforms reverse
  faces; invalid transforms fail atomically. Welding avoids packed-key
  collisions. Remesh/reduce and other edits preserve/interpolate supported
  colors/groups where correspondence exists.
- QEM heap entries are versioned and compare valid endpoint/midpoint choices;
  remeshing validates orientation. Surface-net lattice degeneracies and tiny-scale
  ray tolerances are corrected. Exact empty/disjoint booleans stay exact;
  invalid precise outputs take an explicitly reported grid fallback.
- Voxel allocations and generated pattern/subdivision/remesh output are bounded
  before allocation. CLI arguments reject nonfinite/unknown/invalid values, use
  exit 2 for usage errors, and write outputs atomically.

### Validation and release tooling

- Seeded geometry acceptance and an analytical corpus check topology, winding,
  components and explicit volume tolerances. An external-reference manifest
  harness compares independently acquired outputs without inventing oracle data.
- Critical IO coverage has a >80% per-module gate. Desktop tests exercise
  cancellation, manipulation, recovery, metadata rollback and shortcuts; native
  integration covers Unicode import/edit/undo/save/reopen/export workflows.
- CI pins Flutter 3.47.9 and targets Ubuntu 24.04 x64, Windows Server 2022 x64 and
  macOS 15 arm64. It builds CLIs/apps, runs native integration, creates unsigned
  native installers and checks installation/removal on disposable runners.
- Portable archives normalize metadata; artifacts include checksums, source and
  content provenance, dependency inventories and license texts. Signing scripts,
  manual acceptance and rollback steps are in [RELEASE.md](RELEASE.md).
- The AOT benchmark identifies exact inputs, host and toolchain, records raw
  latency samples and isolated-process peak RSS, and rejects incompatible
  baselines. See [PERFORMANCE.md](PERFORMANCE.md) for measured results and limits.

## Validation record

`./tool/verify.sh` passes with 169 kernel tests, 53 Studio tests, both analyzers
clean and no formatting changes. Native Linux integration passes. The 22-case
analytical corpus and fixed-host performance comparison pass. The optional
native [profile UI probe](performance/UI-RESPONSIVENESS.md) verifies progress and
cancellation on a 100k-face scene, while retaining observed frame stalls and
memory limits. A fresh Linux CLI and release build pass startup smoke testing;
critical coverage passes at 96.4–100% per required module. Packaging regression
tests and license collection pass.

The authoritative three-platform build/integration/install/remove results are
attached to the reviewed commit in [PR #4 checks](https://github.com/palindsay/mmx/pull/4/checks).
See [TESTING.md](TESTING.md) for reproduction. Native integration injects paths,
so it does not establish file-dialog accessibility or clean-account permissions.

## Release acceptance criteria

| Gate | Required evidence | Dependency |
|---|---|---|
| Automated OS matrix | Successful build, integration and install/remove jobs for the reviewed commit, linked above | GitHub-hosted native runners |
| Signing | Verified Windows signature and macOS signed/notarized/stapled installer | Publisher identities, signing host and credentials |
| Native manual acceptance | Clean-account dialogs, permissions, overwrite/exit prompts, forced-exit recovery, keyboard/accessibility and units | Human operator on each supported OS |
| Reference fidelity | Real Meshmixer outputs, recorded settings/provenance and passing agreed tolerances | Licensed usable installation and independently acquired corpus |
| Sustained performance | Repeat the measured fixed-host baseline and native profile probe; accept interactive frame/memory budgets on each supported platform | Designated release hosts and interactive workloads |

Do not label unsigned review artifacts production-ready or claim oracle fidelity
from analytical tests. No release is published by this work.

## Documented limits and future improvements

- Whole-scene undo snapshots count mesh buffers and respect a byte budget but
  are not incremental history. Large scenes can have transient snapshot memory.
- Manipulators use world axes and uniform scale; snapping, nonuniform handles,
  face deformation and local-axis modes are future interaction work.
- Hollow thickness is an SDF approximation with voxel error. Make Solid rejects
  positive `minThickness`; a guaranteed global wall-thickness solver is absent.
- Grid reconstruction does not promise original material-region correspondence.
  Native source attachments preserve unknown `.mix` bytes without interpreting
  their semantics. Unsupported 3MF materials/extensions are explicit errors.
- Parser regression suites are bounded/adversarial examples, not exhaustive
  fuzzing. Expand them when new real-world formats and failures are reported.
- Full Meshmixer parity, mobile, UV/texture authoring, image stamps and GPU
  rendering remain outside the desktop core release target. See [TOOL-MATRIX.md](TOOL-MATRIX.md).
