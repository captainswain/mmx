# Release acceptance record

Target: the Linux x64, Windows x64 and macOS arm64 desktop release, including
the optional features in [PR #5](https://github.com/palindsay/mmx/pull/5).
The next package version is 0.2.0. GitHub Releases in `palindsay/mmx` is the
publication destination. The `v0.2.0` tag and signed release remain unpublished
while acceptance is incomplete.

## Evidence and outstanding inputs

| Area | Evidence | Remaining requirement |
|---|---|---|
| Automated correctness and installation | [PR #5 checks](https://github.com/palindsay/mmx/pull/5/checks); [PR #4](https://github.com/palindsay/mmx/pull/4/checks) is the historical core checkpoint | All checks must pass for the final reviewed commit. |
| Linux native interaction | [Linux acceptance](LINUX-ACCEPTANCE.md) | Human acceptance on a clean supported desktop, including assistive technology. |
| Windows/macOS native interaction | Native integration and installer CI | Interactive clean-account checks below on both operating systems. |
| Performance | [Performance procedure](../PERFORMANCE.md) and hosted measurement artifacts | Designated machines, representative workloads and an agreed latency/frame/memory budget. |
| Signing | [Release review](RELEASE-REVIEW.md) and [signing procedure](../RELEASE.md#signing-and-notarization) | Configured publisher identities; real signature, timestamp, notarization and staple verification. |
| External reference comparison | [Reference harness](../../packages/mmx_core/tool/corpus/README.md) | Independently acquired outputs with application version, settings and provenance. No external results have been supplied. |

The development environment currently has Linux, Wine and hosted CI access.
Workspace inspection found no configured signing environment variables or
repository signing secrets, release environments, variables or self-hosted
runners, and located no usable Meshmixer installation.
The user explicitly deferred Windows/macOS signing hosts, identities and licensed
reference outputs on 2026-11-09. These inputs are future release work; their
deferral does not establish signature, fidelity or human-acceptance evidence.

## Native acceptance checklist

Record the operator, date, source commit, OS/build, architecture and exact
installer SHA-256. For each check, retain the observed result and any reproducer:

1. Install and launch from a clean ordinary user account.
2. Use native open/save dialogs with spaces and Unicode names; cancel each.
3. Save, reopen and export; confirm object metadata and physical units.
4. Decline and accept overwrite prompts; exercise an unwritable destination.
5. Edit, undo and redo; cancel expensive work and confirm the prior scene.
6. Test dirty exit with Save, Discard and Cancel.
7. Force termination after autosave; recover, defer and discard deliberately.
8. Open two app instances and confirm their recovery files remain independent.
9. Navigate actions and dialogs by keyboard and a screen reader; check names,
   focus, scaling and contrast at the display settings intended for release.
10. Uninstall; verify projects and recovery data remain intact.

Automated native interaction records are evidence for those exact executions.
They do not substitute for human accessibility acceptance, prove unrelated OS
behavior, or establish acceptable performance on different hardware.

## Publication

Review and merge the implementation after its final checks pass. Before publishing
signed packages, complete the applicable acceptance records, select the release
version metadata, rebuild from the release commit, verify signatures and regenerate
checksums. Retain the source/build receipts, dependency inventory, test reports
and previous release for rollback. Unsigned CI artifacts remain review artifacts.
