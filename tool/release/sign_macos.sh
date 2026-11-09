#!/usr/bin/env bash
# Run only on a signing host with imported Developer ID identities/profile.
set -euo pipefail
: "${MMX_APP_IDENTITY:?Set the Developer ID Application signing identity}"
: "${MMX_INSTALLER_IDENTITY:?Set the Developer ID Installer signing identity}"
: "${MMX_NOTARY_PROFILE:?Set a notarytool keychain profile}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
version="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' "$root/apps/mmx_studio/pubspec.yaml")"
# The receipt is recorded immediately after the verified build. Do not infer
# binary provenance from whichever source checkout happens to be on the signer.
python3 -B - "$root" "$version" <<'PYRECEIPT'
import importlib.util, pathlib, sys
root, version = pathlib.Path(sys.argv[1]), sys.argv[2]
spec = importlib.util.spec_from_file_location('package_release', root / 'tool/package_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.validate_build_receipt('macos', version, require_clean=True)
PYRECEIPT
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
codesign --verify --strict "$stage/usr/local/bin/mmx"
python3 "$root/tool/collect_licenses.py"
metadata="$stage/usr/local/share/mmx"
mkdir -p "$metadata"
cp "$root/LICENSE" "$root/NOTICE" "$root/THIRD_PARTY_LICENSES.txt" "$metadata/"
cp "$root/bin/build-receipts/macos.json" "$metadata/build-receipt.json"
flutter --version > "$metadata/toolchain.txt"
(cd "$root/apps/mmx_studio" && flutter pub deps --json) > "$metadata/dependencies.json"
# Recompute file hashes after signing; unsigned provenance is no longer valid.
python3 -B - "$root" "$stage" "$version" <<'PYPROVENANCE'
import importlib.util, json, pathlib, sys
root, stage = map(pathlib.Path, sys.argv[1:3])
version = sys.argv[3]
spec = importlib.util.spec_from_file_location('package_release', root / 'tool/package_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
provenance = module.source_provenance('macos', version, code_signed=True)
provenance['buildReceiptSha256'] = module.digest_file(module.build_receipt_path('macos'))
provenance['manifestRoot'] = '/'
provenance['notarization'] = 'Verify separately using the stapled installer ticket'
provenance['files'] = module.tree_manifest(stage)
(stage / 'usr/local/share/mmx/provenance.json').write_text(json.dumps(provenance, indent=2, sort_keys=True) + '\n')
module.macos_components(stage, stage.parent / 'components.plist')
PYPROVENANCE
name="mmx-$version-macos-signed.pkg"
pkg="$scratch/$name"
pkgbuild --root "$stage" --component-plist "$scratch/components.plist" --identifier com.mmx.studio --version "$version" --install-location / --sign "$MMX_INSTALLER_IDENTITY" "$pkg"
xcrun notarytool submit "$pkg" --keychain-profile "$MMX_NOTARY_PROFILE" --wait --output-format json > "$scratch/notary.json"
submission="$(python3 -B - "$root" "$scratch/notary.json" <<'PYNOTARY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('package_release', pathlib.Path(sys.argv[1]) / 'tool/package_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.accepted_notary_id(sys.argv[2]))
PYNOTARY
)"
xcrun notarytool log "$submission" --keychain-profile "$MMX_NOTARY_PROFILE" "$scratch/notary-log.json"
xcrun stapler staple "$pkg"
xcrun stapler validate "$pkg"
pkgutil --check-signature "$pkg"
spctl --assess --type install --verbose=2 "$pkg"
# Only verified, accepted output is moved into the release directory. Checksums
# cover the final stapled bytes and use a portable filename, not a host path.
mv "$pkg" "$root/bin/releases/$name"
cp "$scratch/notary.json" "$root/bin/releases/$name.notary.json"
cp "$scratch/notary-log.json" "$root/bin/releases/$name.notary-log.json"
(cd "$root/bin/releases" && shasum -a 256 "$name" > "$name.sha256")
