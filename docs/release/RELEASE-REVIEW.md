# Release tooling review

Reviewed baseline: `d605fc875a0eddf034b3bef4656d45f47867f6fa` (PR #4).
Scope: portable/native packaging, build provenance, and macOS/Windows signing
orchestration. This is a focused source review, not a certification of signed
binaries. The baseline passed Linux, Windows, and macOS CI; the changes below
require their own CI result.

## Findings and disposition

| Finding | Result | Resolution |
| --- | --- | --- |
| Windows signed only the completed installer, leaving Inno uninstallers and temporary installer copies unsigned. | Fixed in tooling; real certificate validation pending. | `package_release.py windows --native --sign-windows` signs staged application/CLI executables before hashing and configures Inno `SignTool` plus `SignedUninstaller=yes`. Vendor CRT signatures remain intact. |
| The Windows signing helper printed a new hash but left an existing `.sha256` file stale. | Fixed. | Successful signature/timestamp verification precedes checksum replacement. Compiler-internal signing suppresses sidecars; packaging hashes the completed signed installer. |
| The macOS signing path bypassed the repository-only asset rejection and omitted source digest, version, architecture, and installed manifest root. | Fixed. | Signing uses shared build validation and complete provenance; installed hashes describe the signed payload, with `manifestRoot: /`. |
| Packaging attributed existing binaries to the current checkout without checking their recorded build association. | Fixed for recorded builds; trusted build execution remains required. | A receipt binds source commit/digest/version/platform/architecture to exact CLI and bundle hashes. Packaging rejects missing/stale receipts or modified binaries. Signing additionally rejects dirty source/receipts. |
| macOS wrote a final-named package into the release directory before notarization completed. Failed notarization could leave that package beside an older checksum. | Fixed. | The package remains temporary until Accepted status, stapled-ticket validation, installer signature verification, and Gatekeeper assessment succeed. The final checksum covers stapled bytes; submission/log evidence accompanies it. |

Inno explicitly documents the risk of unsigned temporary copies when signing
only after compilation; see [SignTool](https://jrsoftware.org/ishelp/topic_setup_signtool.htm)
and [SignedUninstaller](https://jrsoftware.org/ishelp/topic_setup_signeduninstaller.htm).
Timestamp verification uses Microsoft's documented
[SignTool options](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).
The macOS flow records the Accepted response and submission log described in
[Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Build association and trust boundary

Immediately after building both the CLI and desktop bundle on the verified
source revision, run:

```sh
python tool/package_release.py PLATFORM --record-build
python tool/package_release.py PLATFORM --native
```

The receipt lives at `bin/build-receipts/PLATFORM.json` and is included in each
artifact as `build-receipt.json`; provenance also records its SHA-256. Generated
ignored inventories and build outputs do not enter the source digest. CI records
the receipt immediately after its build commands. Transfer the matching source,
build outputs, and receipt together if using a separate signing host.

On a configured Windows signing host, replace the second command with
`python tool/package_release.py windows --native --sign-windows`. On a configured
macOS host, run `tool/release/sign_macos.sh` after recording the macOS receipt.

A receipt detects changes after recording; it cannot prove that an untrusted
operator compiled those bytes from the stated source. Do not create a receipt
to relabel old binaries. Use the verified build job or perform a fresh build.
Checksums and JSON fields establish content correspondence, not publisher trust;
native signature/notarization verification provides that separate gate.

## Validation performed

`python3 -B -m unittest discover -s tool -p 'test_package_release.py' -v` runs
12 tests: 11 passed locally; one PowerShell test requires Windows/PowerShell CI.
The tests cover changed source/binary rejection, dirty signing rejection,
repository-only assets, signed payload hashes, Inno signing invocation,
deterministic containers, and installed manifest validation. A local command
harness executes the real macOS shell orchestration with fake platform tools:
accepted notarization produces post-sign manifests and post-staple checksums;
rejection, invalid tickets, and stale builds produce no release installer.

`shellcheck tool/release/sign_macos.sh`, `bash -n tool/release/sign_macos.sh`, and
`git diff --check` pass. The harness uses dummy identities and performs no
cryptographic signing, Apple submission, timestamp request, or publication.

## Remaining distribution gates

- Supply Developer ID Application/Installer identities, a notary profile, and a
  trusted macOS host. Run the actual flow and retain its accepted submission,
  stapler/Gatekeeper results, installed manifest verification, and final checksum.
- Supply the Windows certificate, timestamp service, SignTool, and trusted host.
  Verify the resulting installer, installed app/CLI, and `unins000.exe` with
  `signtool verify /pa /all /tw`; run install/uninstall on a clean account.
- Re-run all-platform CI for these changes. Exercise native dialogs, recovery,
  overwrite/permission errors, and accessibility on the exact final signed bytes.
- Retain final checksums/signature evidence for the planned GitHub Release.
  Linux `.deb` review artifacts remain unsigned; an optional signed APT
  repository would require its own repository-signing credentials.

No signed/notarized release or clean-account acceptance is claimed here. External
Meshmixer comparison remains a separate fidelity gate, outside this review.
