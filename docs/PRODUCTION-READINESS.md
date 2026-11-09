# Production readiness

Target: reliable Linux, Windows and macOS core mesh workflows and CLI.
**Status: core hardening and optional desktop features are implemented. Automated
acceptance for the reviewed implementation is tracked in
[PR #5 checks](https://github.com/palindsay/mmx/pull/5/checks); production
distribution still requires the external acceptance below.** See the
[feature completion record](FEATURE-COMPLETION.md). This supersedes the historical
finish/remediation plans; full Meshmixer parity is a separate target.

## Implemented plan

### Desktop interaction and persistence

- Geometry workers are owned isolates: cancel terminates synchronous CPU work,
  stale results cannot replace a newer document, and failed edits restore scene,
  camera, project path and original-source metadata. Status reports operation
  phases rather than an invented completion percentage.
- Rendering coalesces requests; spatial data caches key on document/object/mesh
  and transform state. World/local translation and rotation, per-axis/uniform
  scale, snapping, numeric entry and pivot editing commit one undo entry. Sculpt drags group stamps into one entry
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
- Framing an empty Boolean result preserves the prior camera, so valid empty
  results remain saveable and reloadable.
- Chosen existing Save As/export destinations require Replace confirmation;
  cancellation preserves the original bytes. Toolbar/tool actions and adjustable
  controls expose names through native accessibility APIs.
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
  Reports retain consumed fixture/manifest hashes and operation settings.
- Critical IO coverage has a >80% per-module gate. Desktop tests exercise
  cancellation, manipulation, recovery, metadata rollback and shortcuts; native
  integration covers Unicode import/edit/undo/save/reopen/export workflows.
- CI pins Flutter 3.47.9 and targets Ubuntu 24.04 x64, Windows Server 2022 x64 and
  macOS 15 arm64. It builds CLIs/apps, runs native integration, creates unsigned
  native installers and checks installation/removal on disposable runners.
- Portable archives normalize metadata; artifacts include checksums, source and
  content provenance, dependency inventories and license texts. Signing scripts,
  manual acceptance and rollback steps are in [RELEASE.md](RELEASE.md).
  Source/binary build receipts reject stale packaging inputs. Signing paths
  verify their results before exposing final packages and hashes; real publisher
  signatures still require the external identities below.
- The AOT benchmark identifies exact inputs, host and toolchain, records raw
  latency samples and isolated-process peak RSS, and rejects incompatible
  baselines. See [PERFORMANCE.md](PERFORMANCE.md) for measured results and limits.

## Validation record

The optional-feature local run passes 214 kernel and 84 Studio tests with clean
analyzers and formatting; the separate strict native renderer suite passes all
six tests. The implementation adds material/texture round trips, immutable
history, advanced manipulators, native depth/texture checks, parser mutations and
continuous wall verification. Independent reviews cover data persistence,
transaction rollback, growth bounds and reconstruction topology. Both new wall
modules have 100% line coverage; all 19 required coverage modules pass. The native
matrix builds and tests Vulkan, Direct3D 12 and Metal, records actual adapter
capability, and packages unsigned installers. Use the exact commit and artifact
checksums in [PR #5](https://github.com/palindsay/mmx/pull/5) for current evidence.
Hosted profile measurements retain raw samples and software-adapter status;
they do not establish release-host performance budgets.

### Historical core checkpoint

The merged core checkpoint passed with 169 kernel tests, 57 Studio tests, both analyzers
clean and no formatting changes. Native Linux integration passes. The 22-case
analytical corpus and fixed-host performance comparison pass. The optional
native [profile UI probe](performance/UI-RESPONSIVENESS.md) verifies progress and
cancellation on a 100k-face scene, while retaining observed frame stalls and
memory limits. A fresh Linux CLI and release build pass startup smoke testing;
critical coverage passes at 96.4–100% per required module. Packaging regression
tests and license collection pass.

The prior 0.2.0 candidate additionally passed 14 [native Linux acceptance checks](release/LINUX-ACCEPTANCE.md)
using actual GTK dialogs, AT-SPI actions, overwrite hash checks, permission
failures and forced termination/recovery. The release/evidence tooling has 21
regression tests; the local run passes with the PowerShell test skipped for the
native platform job. The [performance workflow](https://github.com/palindsay/mmx/actions/workflows/performance.yml)
collects AOT and native profile observations on all three platforms; these are
not approved budgets on designated release machines.

The three-platform build/integration/install/remove results for that checkpoint
are attached to [PR #4 checks](https://github.com/palindsay/mmx/pull/4/checks).
These results do not certify subsequent optional-feature changes.
See [TESTING.md](TESTING.md) for reproduction. CI integration injects paths;
the separate Linux acceptance run exercises real dialogs but does not establish
human accessibility acceptance or clean-account behavior on the other systems.
The [acceptance record](release/ACCEPTANCE.md) tracks the remaining external inputs.

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

- Incremental undo shares immutable geometry blocks and counts unique payloads;
  transient checkpoints, live restoration buffers and VM overhead are separate.
  [Local measurements](performance/INCREMENTAL-UNDO.md) document the limits.
- Manipulators support local/world axes, per-axis scale, snapping and numeric
  entry. Arbitrary face deformation remains separate from object manipulation.
- Optional [minimum-wall verification](WALL-THICKNESS.md) checks continuous
  inward-normal opposing-surface clearance on the final mesh with bounded
  reconstruction attempts. It assumes embedded shells and is not a medial-axis,
  self-intersection or manufacturing certificate. Unverified SDF thickness still
  has voxel error; Fast mode and open-shell minimum requests fail explicitly.
- Grid reconstruction does not promise original material-region correspondence.
  Native source attachments preserve unknown `.mix` bytes without interpreting
  their semantics. [Materials](MATERIALS.md) support diffuse RGBA and PNG/JPEG
  textures with seam-safe UVs; unsupported 3MF layers/extensions fail explicitly.
- Parser mutation tests use deterministic bounded cases and metamorphic round
  trips. They are not exhaustive or a long-running fuzzing campaign.
- Native wgpu rendering supports Vulkan, Direct3D 12 and Metal with explicit CPU
  fallback. Alpha cutout is supported; sorted translucency, PBR and zero-copy
  Flutter textures remain outside the renderer contract.
- Full Meshmixer parity, mobile, advanced UV seam painting and image stamps
  remain separate work. See [TOOL-MATRIX.md](TOOL-MATRIX.md).

Signing hosts/identities and licensed reference outputs were explicitly deferred
by the user on 2026-11-09. Their deferral does not waive production release gates.
