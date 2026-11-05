#!/usr/bin/env bash
# Local/CI verification. Expects the Meshmixer installer models on this host
# at the path baked into the kernel tests.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/packages/mmx_core"
dart pub get
dart format --output=none --set-exit-if-changed lib test bin
dart analyze
dart test
cd "$root/apps/mmx_studio"
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
