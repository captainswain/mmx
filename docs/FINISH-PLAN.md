# Finish plan: Meshmixer reverse engineering and mmx parity

> Historical plan. See [production readiness](PRODUCTION-READINESS.md) for
> implemented hardening work, current validation, and outstanding release gates.


This is the closing plan for the project. It separates three different
questions that were previously mixed together:

1. **What is still unknown about the binary?** (evidence closure)
2. **What behaviour is still missing from mmx?** (feature parity)
3. **How do we prove the reimplementation is faithful?** (oracle validation)

The reverse-engineering report is already strong enough to stop treating every
remaining question as a blocker. The remaining work is finite, and most of it
is parity and validation rather than more disassembly.

## Definition of done

The project is finished when all of the following are true:

- Every named Meshmixer tool and action-bar handler has an explicit status:
  implemented, partial with a documented gap, or deliberately out of scope.
- The core workflows (import/export, repair, remesh, reduce, solid, boolean,
  plane cut, hollow, sculpt/select, supports, analysis, print) have no known
  correctness defect on the golden corpus.
- `.mix` round-trips are lossless for every record observed in real Meshmixer
  output; records that are not decoded are preserved byte-for-byte.
- Fidelity tolerances are met on the Wine-oracle corpus, with failures listed
  rather than hidden.
- The final report labels every claim **[observed]**, **[inferred]** or
  **[unknown]**, and lists the unknowns that are unknowable without source.
- `tool/verify.sh` passes from a clean checkout, the CLI and desktop app build,
  and the release artifacts are reproducible.

"Finished" does **not** mean bit-identical output. Meshmixer's exact numeric
constants are not in the binary as readable values, and the source is closed.
It means every difference is either documented, bounded, or explicitly accepted.

## Current baseline

- 106 kernel tests, 11 Studio tests, both analyzers clean.
- `.mix` VFMesh 1.2/1.3, face groups and lossless rewrite for unknown records.
- 198 `Class::Method` strings recovered; 173 functions renamed in Ghidra.
- RTTI/vtable attribution for 913 classes.
- No PDB; the string set is the complete set of names embedded in the binary.
- Core geometry, repair, remesh, reduce, solid, boolean fallback, plane cut,
  hollow, sculpt, supports, analysis and fabrication operators exist.
- Studio has tool panels for the main workflows; several newer kernel tools are
  still kernel-only.

## Work packages

### WP1 - Close the evidence ledger (priority: highest, effort: 2-3 days)

Build `docs/TOOL-MATRIX.md`: one row per named tool and action handler from
`docs/REVERSE-ENGINEERING.md`, with columns for evidence source, mmx
implementation, UI exposure, tests and status.

Tasks:

- Enumerate all 44 named tools and the recovered `userActionBar` /
  `userEditAction` handlers.
- Map each to a kernel symbol, app action or explicit "out of scope" decision.
- Flag tools that exist only as RTTI/string evidence and have no behavioural
  sample.
- Record which claims are **[observed]** versus **[inferred]**.

Acceptance: no named tool is unclassified; every gap has an owner and a test or
a documented exclusion.

### WP2 - Resolve the remaining binary unknowns (effort: 5-8 days)

This is the last disassembly pass worth doing. It is targeted, not a full
auto-analysis.

Tasks:

- **Constants:** decompile the named reducer, boolean, remesh, support and
  solid entry points; extract constants that appear in comparisons and
  multipliers. Where the constant is not readable, calibrate it with the Wine
  oracle (see WP4) and record the fitted value and error.
- **Boolean:** recover the density multipliers, merge iteration counts and
  robustness thresholds around `MeshBoolean::Validate`; compare
  FastApproximate/Precise/ExtraPrecise outputs.
- **Adaptive remesh:** fit transition widths and density falloff against
  Meshmixer outputs at several settings; keep the angle-defect heuristic only
  where it matches within tolerance.
- **Support optimisation:** recover the objective weights if the decompiled
  `SupportForestGenerator` exposes them; otherwise document the proxy objective.
- **RTTI/method names:** finish vtable-slot attribution for classes whose
  methods are still `FUN_`; accept that unnamed functions stay unnamed.
- **`.mix` extras:** generate scenes in Wine containing pivots, decals, stamps,
  textures and shaders; diff the XML and binary blocks; add typed parsers only
  for records that actually occur.

Acceptance: every remaining **[unknown]** in `docs/REVERSE-ENGINEERING.md` is
either resolved with evidence or explicitly marked unknowable, with the
reimplementation choice documented.

### WP3 - Close feature-parity gaps (effort: 10-15 days)

The kernel is ahead of the app. Prioritise workflows a user can reach.

Tasks:

- Add UI and state actions for the kernel-only tools: Make Polygon, Add Tube,
  Unwrap, Soft Move/Bend, Complex Generate/Filter, and the remaining boolean
  modes.
- Add a transform/pivot manipulator and Units tool; wire `Pivot` into the
  viewport instead of only storing it on `SceneObject`.
- Implement image stamps (height-field import), stamp/shaders semantics, and
  the remaining `FaceTransform` / `FaceVariationalMove` / `Handle` / `Strength`
  / `SmoothBoundary` tools where they affect a core workflow.
- Decide UV scope: either add an optional UV channel to `TriMesh` and export
  it, or keep `Unwrap` as a preview and say so in the UI.
- Add widget tests for every new action; replace any remaining duplicated
  panel logic with kernel calls.

Acceptance: every core workflow is reachable from the app; kernel-only tools
are labelled as such; new actions have tests.

### WP4 - Build the Wine oracle and fidelity corpus (effort: 5-7 days)

This is the part that turns "looks similar" into a defensible finish.

Tasks:

- Script Meshmixer under Wine to run a fixed corpus of models through each
  core tool and setting, saving outputs and screenshots.
- Define metrics per tool: watertightness, component count, volume/area error,
  face/vertex counts, edge-length distribution, symmetry error, support count,
  thickness/overhang distributions.
- Set tolerances per tool; record failures and accepted differences.
- Add a regression runner that compares mmx output against the corpus and
  writes a report.

Acceptance: a repeatable report showing pass/fail per tool and setting, with
documented tolerances and no hidden exceptions.

### WP5 - Harden and release (effort: 5-7 days)

Tasks:

- Extend property/fuzz tests to all destructive operators, not just remesh and
  collapse.
- Add a numeric coverage gate and a performance budget (12k and 100k faces).
- Verify Windows and macOS builds, not only Linux; fix platform-specific I/O
  and path issues.
- Package the CLI and desktop app; document installation and supported formats.
- Write the final report: executive summary, evidence ledger, unknowns,
  reproduction steps and license note.

Acceptance: clean-checkout verification passes, release artifacts exist, and
the final report is self-contained.

## Sequence

1. WP1 (tool matrix) - one day; it defines the real scope.
2. WP2 (targeted evidence) - do only the unknowns that block WP3/WP4.
3. WP3 (parity) - in parallel with WP4 harness work where possible.
4. WP4 (oracle validation) - after the tools under test are reachable.
5. WP5 (hardening/release) - last.

## Explicitly out of scope unless a user needs it

- Bit-identical numeric output to Meshmixer.
- Reimplementing every Qt widget or shader.
- Decoding `.mix` records that never appear in real saved scenes.
- A GPU renderer; the software rasterizer is sufficient for this project.
- Recovering a PDB; the embedded string set is the practical limit.

## Immediate next actions

1. Use `docs/TOOL-MATRIX.md` as the scope checklist; close the kernel-only and
   partial entries in priority order.
2. Create Wine samples for pivot, decal, stamp, texture and shader scenes;
   inspect the XML and block records before writing parsers.
3. Run the reducer/boolean/remesh named functions through Ghidra one more time
   and extract every constant used in comparisons.
4. Build the oracle harness for the core tools while parity work proceeds.
