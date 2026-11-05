# Contributing to mmx

Thanks for taking the time to improve mmx. This project is a clean-room
reimplementation of Meshmixer's useful geometry workflows, and contributions
are welcome in the kernel, the Studio app, the documentation, and the test
corpus.

## Before you start

- Read [`docs/REVERSE-ENGINEERING.md`](docs/REVERSE-ENGINEERING.md) and
  [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The project deliberately
  separates **[observed]** behaviour from **[inferred]** behaviour and from
  **[unknown]** constants.
- Check the issue tracker and open an issue before a large change. Small fixes
  and documentation corrections can go straight to a pull request.
- Do not copy Autodesk source code. The implementation is clean-room; the
  shipped binary, its RTTI, strings and public API headers are the evidence.

## Development setup

Requirements:

- Flutter 3.47 or newer and Dart 3.13 or newer.
- Linux, macOS or Windows for the desktop app.
- No Meshmixer installation is required to run the tests: the sample models
  are vendored under `packages/mmx_core/test/fixtures/models`.

Run the full verification:

```sh
./tool/verify.sh
```

Or individually:

```sh
cd packages/mmx_core
dart pub get
dart analyze
dart test

cd ../../apps/mmx_studio
flutter pub get
flutter analyze
flutter test
```

## Code standards

- Keep the kernel free of Flutter imports; `mmx_core` must remain a pure Dart
  package.
- Use typed arrays and allocation-bounded loops in hot geometry paths.
- Add tests for new logic. The project target is more than 80% line coverage
  for new kernel modules; destructive topology operations need watertightness,
  manifoldness and volume assertions, not just "it returned a mesh".
- Run `dart format` on changed Dart files. The project uses the standard Dart
  formatter and the analyzer configuration in the repository.
- Document algorithms with their source: published paper, recovered Meshmixer
  symbol, or explicit approximation. Label claims as observed, inferred or
  unknown.
- Do not silently fall back to a different algorithm. Return a result flag or
  document the fallback, as `RemeshResult.usedUniformFallback` and
  `BooleanResult.usedFallback` do.

## Pull requests

1. Fork the repository and create a topic branch.
2. Keep the change focused; avoid unrelated formatting churn.
3. Add or update tests and documentation in the same pull request.
4. Describe the behaviour change, the evidence, and the verification commands
   you ran.
5. Make sure CI and `./tool/verify.sh` pass.

By submitting a contribution you agree that it is licensed under the Apache
License 2.0, the same license as the rest of the project.

## Reporting bugs

Include:

- the mmx version or commit;
- the platform and Flutter/Dart version;
- the input format and, if possible, a minimal model;
- the command or UI action;
- expected and actual output, including boundary-loop/non-manifold counts.

Use the GitHub issue templates when available. For security issues, follow
[`SECURITY.md`](SECURITY.md) instead of opening a public issue.
