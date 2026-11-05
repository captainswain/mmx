# Security policy

## Supported versions

mmx is pre-1.0. Security fixes are applied to the latest `main` branch and the
most recent tagged release. If you depend on a fork or a pinned commit, rebase
onto `main` before reporting an issue.

| Version | Supported |
|---|---|
| 0.1.x / main | Yes |
| older commits | Best effort |

## Reporting a vulnerability

Please do **not** open a public issue for a security problem. Use GitHub's
private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Include the affected version or commit, platform, input file if relevant,
   and a minimal reproduction.

If private reporting is unavailable, contact the maintainer through GitHub and
mark the report clearly as security-related.

You can expect an acknowledgement within a few days. Please allow time for a
fix and a coordinated disclosure before publishing details.

## Scope

mmx is a local desktop/CLI tool. Its attack surface is primarily:

- parsing untrusted mesh files (OBJ, PLY, STL, OFF, 3MF and `.mix`);
- decompressing 3MF OPC zip archives;
- reading `.mix` binary records with length and offset fields.

The kernel validates array bounds and rejects malformed files where possible,
but a malformed file that triggers excessive memory use or a crash is still a
security-relevant bug. Reports with a minimal reproducer are especially useful.

mmx does not make network requests at runtime and does not execute code from
input files.

## Dependencies

Dependency advisories are monitored through GitHub Dependabot. The project
keeps runtime dependencies minimal; the kernel depends only on `package:meta`.
