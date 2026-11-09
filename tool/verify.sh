#!/usr/bin/env bash
# Local/CI verification uses only vendored fixtures.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/packages/mmx_core"
dart pub get
dart format --output=none --set-exit-if-changed lib test bin
dart analyze
dart test
cd "$root/apps/mmx_studio"
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
