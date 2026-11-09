#!/usr/bin/env bash
# Collect into a fresh directory so old source line maps cannot pollute results.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mmx_coverage_raw="$(mktemp -d "${TMPDIR:-/tmp}/mmx-coverage.XXXXXX")"
cd "$root/packages/mmx_core"
dart test --coverage="$mmx_coverage_raw"
mkdir -p coverage
dart run coverage:format_coverage --lcov --in="$mmx_coverage_raw" \
  --out=coverage/lcov.info --packages=.dart_tool/package_config.json --report-on=lib
cd "$root"
dart run tool/check_coverage.dart
