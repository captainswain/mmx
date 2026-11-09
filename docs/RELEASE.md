# Desktop release procedure

Release targets are Linux x64 (Ubuntu 24.04 CI), Windows x64 (Windows Server 2022
CI), and macOS arm64 (macOS 15 CI). Additional OS/architecture combinations are
not certified by these jobs. No release is automatically published.

macOS targets direct Developer ID distribution, with hardened runtime during
signing and without App Sandbox. The app uses the user's ordinary filesystem
permissions for atomic sibling-file replacement. This gives broader access than
a sandboxed app; App Store distribution would require sandbox-aware document
coordination, security-scoped bookmarks and separate acceptance testing first.
Apple makes sandboxing optional for notarized direct distribution; see
[distribution requirements](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).

## Verification and packaging

The `CI` workflow runs formatting, analyzers, kernel/widget tests, a real desktop
integration workflow, and native installer install/uninstall checks on each OS.
Linux additionally enforces critical IO coverage. Test failures block packaging.
Installer checks run on disposable CI runners, never on a contributor workstation.

From a matching build host:

```sh
./tool/verify.sh
# From apps/mmx_studio; use -d windows or -d macos on those hosts:
xvfb-run -a flutter test integration_test -d linux
flutter build linux --release
# From packages/mmx_core:
dart compile exe bin/mmx.dart -o mmx-linux.exe
# From repository root:
python3 tool/collect_licenses.py
python3 tool/package_release.py linux --native
```

Windows packaging requires the Inno Setup compiler in `ISCC_PATH`. macOS uses
`pkgbuild`; Linux uses `dpkg-deb`. Each platform also gets a portable archive.
Outputs and SHA-256 files live in `bin/releases/`. Inspect the workflow artifacts
for native `.deb`, `.pkg`, or Windows installer `.exe` files.

macOS packages include only the application bundle and explicitly disable bundle
relocation, so an existing build-tree copy cannot redirect installation away
from `/Applications/mmx Studio.app`.

On Windows, run `tool/release/find_windows_runtime.ps1` in the packaging
PowerShell session first. It sets `MMX_WINDOWS_CRT_DIR` to the Visual Studio
x64 release redistributables. Packaging places those DLLs beside both executables
so clean machines do not need a separately installed Visual C++ runtime. They
remain subject to [Microsoft's redistribution terms](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution);
their hashes and attribution are included in the artifact. Rebuild artifacts
when runtime security updates are released because app-local DLLs are serviced
with the app. Never redistribute DebugCRT binaries.

`provenance.json` records the source commit, working-tree source digest,
architecture, package version, dirty status and binary file hashes. Portable
archive metadata uses the source commit timestamp (override with
`SOURCE_DATE_EPOCH`); identical staged binaries produce identical archives.
This proves container reproducibility, not cross-host compiler reproducibility.
Dependency inventories and collected license texts accompany CI artifacts.
The install checks verify every declared file hash and symlink against the
installed payload. macOS regenerates its manifest for installed filesystem paths
and includes the same inventories as the portable package.

The app starts with our procedural geometry. Packaging rejects accidentally
bundled repository-only Autodesk model assets. Source fixtures and research
references retain their attribution in `NOTICE`; they are not binary assets.

## Signing and notarization

Unsigned artifacts are for review. Distribution requires these external inputs:

- macOS: Developer ID Application and Installer identities imported into a
  signing host's keychain, plus a configured `notarytool` keychain profile.
- Windows: an appropriate code-signing certificate accessible to SignTool and
  the certificate provider's RFC 3161 timestamp URL.

`tool/release/sign_macos.sh` requires `MMX_APP_IDENTITY`,
`MMX_INSTALLER_IDENTITY`, and `MMX_NOTARY_PROFILE`. It signs nested code and the
app/CLI, builds a signed installer, submits it for notarization and staples the
ticket. Run on a trusted macOS signing host after verification. This command
contacts Apple's notarization service; never run it with unreviewed binaries.

`tool/release/sign_windows.ps1 -Paths ...` requires `MMX_CERT_THUMBPRINT` and
`MMX_TIMESTAMP_URL`. Sign application executables and the CLI before packaging,
then sign the completed installer. Verify with `signtool verify /pa`; recompute
checksums after signing. Never store certificates/passwords in this repository.

Reference: [Apple signing guidance](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html),
[Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Inno Setup compiler](https://jrsoftware.org/ishelp/topic_compilercmdline.htm) and
[silent installer options](https://jrsoftware.org/ishelp/topic_setupcmdline.htm).

## Acceptance and rollback

Before publishing, manually exercise the native open/save dialogs, overwrite and
permission failures, exit prompts, recovery after forced termination, keyboard
navigation and scale/units on clean user accounts. Automated integration uses
injected paths so it cannot certify OS dialog interaction or accessibility.
Record the exact artifact checksums, OS versions and observed outcomes.

Archive the previous signed release. Projects declare their schema version;
unsupported versions must fail without replacing the document. Keep a project
backup before trying a newer release. To roll back, uninstall the newer binary,
install the previous signed package and open the backup. Recovery files and user
projects are deliberately not deleted by uninstallers. Do not promise older
versions can read a schema they never supported.

The analytical corpus is an mmx correctness gate; it is not evidence of exact
Meshmixer fidelity. A licensed external reference corpus with recorded settings
is required for that claim. Signing, native manual acceptance, and oracle results
must be recorded as pending until the necessary external resources exist.
