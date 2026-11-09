# Repository Guidelines

## Project Structure & Module Organization

- `packages/mmx_core/`: pure Dart geometry kernel. Implementations live in `lib/src/` by domain (mesh, repair, remesh, solid, IO, rendering); `lib/mmx_core.dart` exports the public API; `bin/mmx.dart` provides the CLI.
- `apps/mmx_studio/`: Flutter app, with state in `lib/state/`, widgets in `lib/ui/`, and bundled models in `assets/models/`.
- Each package has `test/` and `test/fixtures/`; kernel models live in `packages/mmx_core/test/fixtures/models/`.
- `docs/` contains architecture, algorithm evidence, and testing notes. `tools/` contains reverse-engineering helpers; `tool/verify.sh` runs CI checks.

## Build, Test, and Development Commands

Use Flutter 3.47+ and Dart 3.13+ for repository development.

- From the root, `./tool/verify.sh` installs dependencies, checks formatting, analyzes, and tests both packages.
- In `packages/mmx_core/`, run `dart pub get`, `dart analyze`, and `dart test` for kernel development.
- In that directory, `dart run bin/mmx.dart info test/fixtures/models/sphere.obj` exercises the CLI; `dart compile exe bin/mmx.dart -o mmx` builds an executable.
- In `apps/mmx_studio/`, run `flutter pub get`, `flutter analyze`, and `flutter test`; launch with `flutter run -d linux` or build with `flutter build linux --release`.

## Coding Style & Naming Conventions

Use two-space indentation, LF endings, and `dart format` on changed Dart files. Follow `lower_snake_case.dart` filenames, `UpperCamelCase` types, and `lowerCamelCase` members. Kernel linting uses `lints/recommended`; Studio uses `flutter_lints`.

Keep the kernel free of Flutter imports. Use typed arrays and allocation-bounded loops in hot geometry paths. Expose algorithm fallbacks explicitly.

## Testing Guidelines

Use `package:test` for kernel tests and `flutter_test` for Studio widget/state tests. Name files `*_test.dart`; run a focused suite with `dart test test/remesh_test.dart` from the kernel directory. Tests use vendored fixtures; no Meshmixer installation is required.

Target more than 80% line coverage for new kernel modules. Geometry changes require watertightness, manifoldness, and volume assertions. See `docs/TESTING.md` for coverage commands.

## Commit & Pull Request Guidelines

Use concise imperative subjects, matching history: `Fix adaptive remesh topology` or `Use vendored .mix fixture`. Keep changes focused. Follow `.github/PULL_REQUEST_TEMPLATE.md`: explain behavior, link relevant issues, provide evidence/reproducers, identify approximations, and record verification commands. Update tests/docs and ensure CI passes.

## Clean-Room Implementation

Read `CONTRIBUTING.md` and `docs/REVERSE-ENGINEERING.md`. Never copy Autodesk source code. Document algorithm sources and label claims **observed**, **inferred**, or **unknown**.
