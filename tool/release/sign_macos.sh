#!/usr/bin/env bash
# Run only on a signing host with imported Developer ID identities/profile.
set -euo pipefail
: "${MMX_APP_IDENTITY:?Set the Developer ID Application signing identity}"
: "${MMX_INSTALLER_IDENTITY:?Set the Developer ID Installer signing identity}"
: "${MMX_NOTARY_PROFILE:?Set a notarytool keychain profile}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d)"
stage="$scratch/root"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$stage/Applications" "$stage/usr/local/bin" "$root/bin/releases"
app_source="$root/apps/mmx_studio/build/macos/Build/Products/Release/mmx_studio.app"
ditto "$app_source" "$stage/Applications/mmx Studio.app"
cp "$root/packages/mmx_core/mmx-macos.exe" "$stage/usr/local/bin/mmx"
app="$stage/Applications/mmx Studio.app"
# Sign nested code first; never use --deep to paper over incorrect signing order.
while IFS= read -r -d '' binary; do
  codesign --force --timestamp --options runtime --sign "$MMX_APP_IDENTITY" "$binary"
done < <(find "$app/Contents" -type f -name '*.dylib' -print0)
while IFS= read -r -d '' framework; do
  codesign --force --timestamp --options runtime --sign "$MMX_APP_IDENTITY" "$framework"
done < <(find "$app/Contents" -depth -type d -name '*.framework' -print0)
codesign --force --timestamp --options runtime --entitlements "$root/apps/mmx_studio/macos/Runner/Release.entitlements" --sign "$MMX_APP_IDENTITY" "$app"
codesign --force --timestamp --options runtime --sign "$MMX_APP_IDENTITY" "$stage/usr/local/bin/mmx"
codesign --verify --deep --strict "$app"
python3 "$root/tool/collect_licenses.py"
metadata="$stage/usr/local/share/mmx"
mkdir -p "$metadata"
cp "$root/LICENSE" "$root/NOTICE" "$root/THIRD_PARTY_LICENSES.txt" "$metadata/"
flutter --version > "$metadata/toolchain.txt"
(cd "$root/apps/mmx_studio" && flutter pub deps --json) > "$metadata/dependencies.json"
# Recompute file hashes after signing; unsigned provenance is no longer valid.
python3 -B - "$root" "$stage" <<'PYPROVENANCE'
import importlib.util, json, pathlib, subprocess, sys
root, stage = map(pathlib.Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('package_release', root / 'tool/package_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
provenance = {
    'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
    'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root)),
    'platform': 'macos', 'codeSigned': True,
    'notarization': 'Verified separately by stapled installer ticket',
    'files': module.tree_manifest(stage),
}
(stage / 'usr/local/share/mmx/provenance.json').write_text(json.dumps(provenance, indent=2, sort_keys=True) + '\n')
module.macos_components(stage, stage.parent / 'components.plist')
PYPROVENANCE
version="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' "$root/apps/mmx_studio/pubspec.yaml")"
pkg="$root/bin/releases/mmx-$version-macos-signed.pkg"
pkgbuild --root "$stage" --component-plist "$scratch/components.plist" --identifier com.mmx.studio --version "$version" --install-location / --sign "$MMX_INSTALLER_IDENTITY" "$pkg"
xcrun notarytool submit "$pkg" --keychain-profile "$MMX_NOTARY_PROFILE" --wait
xcrun stapler staple "$pkg"
pkgutil --check-signature "$pkg"
shasum -a 256 "$pkg" > "$pkg.sha256"
