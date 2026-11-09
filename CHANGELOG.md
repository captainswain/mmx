# Changelog

All notable changes to mmx are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
semantic versioning once it reaches 1.0.

## [Unreleased]

### Added

- Native `.mmx` projects, recovery saves, unsaved-change prompts and native file dialogs.
- Viewport manipulation, grouped sculpt undo, unit selection and cancelable workers.
- Desktop integration tests, parser/geometry regression suites and analytical corpus.
- Native installer jobs, deterministic portable archives, checksums and source provenance.
- Exact-input AOT performance comparisons with latency samples and peak memory.
- Tool matrix and finish plan for closing the reverse-engineering project.
- Studio actions for Extract, Make Part and Pivot.
- `BooleanResult` and `RemeshResult` fallback reporting.
- Property tests for remesh and collapse invariants.
- Vendored test models so the kernel suite runs without a Meshmixer install.
- Apache-2.0 licensing, contribution, security and community documentation.

### Changed

- Studio starts with procedural geometry; repository-only model assets are excluded from releases.
- Unsupported 3MF materials and positive Make Solid minimum-wall requests now fail explicitly.
- Extract in Studio now delegates to `ComplexTools.extract`.
- Pivot state is preserved by document undo/redo snapshots.
- CI runs on GitHub-hosted runners using the vendored fixtures.

### Fixed

- QEM candidate invalidation, remesh winding, surface-net lattice degeneracies and tiny-scale ray tolerances.
- Concave import triangulation, PLY schemas/byte order, strict STL parsing and `.mix` metadata rewrites.
- Recovery write ordering, failed-import metadata rollback and keyboard shortcut focus.
- Plane Cut honours `keepPositive` on both sides and supports a negative-side
  slice group.
- Smooth hole filling relaxes only the filled patch.
- Hollow uses the requested minimum thickness as an inner SDF offset, subject to voxel discretization error.
- Make Polygon uses ear clipping for concave loops.
- Adaptive remesh fallback is explicit instead of silent.

## [0.1.0] - 2026-11-05

### Added

- Pure-Dart geometry kernel: topology, BVH, repair, remesh, decimation, SDF
  solidification, booleans with fallback, analysis, supports, packing, slicing.
- Native `.mix` reader/writer for VFMesh 1.2 and 1.3, including face groups and
  lossless rewrite of unknown records.
- Flutter Studio app with selection, sculpting, repair, remesh, reduce, solid,
  hollow, plane cut, mirror, extrude, supports, analysis and print workflows.
- CLI covering the kernel operators.
- Reverse-engineering report with observed/inferred/unknown evidence labels,
  RTTI and method-name recovery.
