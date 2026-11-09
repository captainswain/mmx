# Linux native acceptance evidence

**[observed] 2026-11-09:** The Linux release app was exercised through real GTK
file selectors, AT-SPI actions, keyboard events, and ICCCM window-close requests.
These are automated native observations, not a human accessibility review or
acceptance of the Windows/macOS releases.

## Builds and environment

The baseline was the extracted portable release from commit
`d605fc875a0eddf034b3bef4656d45f47867f6fa` (0.1.0). Two defects were reproduced:
icon/tool controls exposed empty AT-SPI names despite visual tooltips, and
**Save project as…** silently replaced an existing file. Studio now supplies
explicit accessible labels and asks **Replace / Cancel** when a newly chosen
save/export destination exists. Ordinary Save to an established project path
keeps its existing behavior. Focused widget regressions cover semantic actions,
selected tools, sliders, and both overwrite paths.

The corrected run used `flutter build linux --release` for 0.2.0+1, from the
working tree containing those changes. The launcher remains unchanged; Dart UI
code is in `lib/libapp.so`, so both hashes identify the tested build:

| Component | SHA-256 |
| --- | --- |
| Baseline portable archive | `a830ccea2ea2dc8b647641cf5c85fcca5ba770f504fc70877b2d97138029e949` |
| Baseline and corrected `mmx_studio` launcher | `2cda5b2e6a62e9c6b75b8053a964d9cff65a477821154d2ab97129374c89c70f` |
| Baseline `lib/libapp.so` | `e7db2b62503b269700b09faac765d15f77eb9039910396157b56dcd69215163f` |
| Corrected `lib/libapp.so` | `1786dc2cd05d2785d2ab00f2aba8ac5d7f56721c21392936be8a145e92881c89` |

Host: Ubuntu 26.04.1 x86_64, kernel `7.0.0-42-generic`, ordinary UID 1000;
Flutter 3.47.9/Dart 3.13.7; GTK 3.24.52; AT-SPI typelib 2.60.4;
Python 3.14.4/PyGObject 3.56.2; Xvfb 21.1.22; xdotool
`1:3.20160805.1-5.1build1`. Each run uses its own D-Bus session, 1280×800 Xvfb
display, and temporary XDG data/config/cache/runtime directories. Accessibility
is enabled only on that private session. GTK uses local GIO with portals
disabled. No system account was created, package installed, active desktop
controlled, or personal document opened/modified. xdotool was extracted from
Ubuntu packages into the temporary test directory without installing it.

## Observed acceptance

**All 14 automated checks passed.** The [machine-readable run](evidence/linux-native-2026-11-09.json) records exact
UTC times, harness/binary hashes, assertions and saved-file hashes. Compare the
[baseline AT-SPI tree](evidence/linux-atspi-baseline-d605fc8.json) with the
[corrected tree](evidence/linux-atspi-0.2.0.json).

| Scenario | Result |
| --- | --- |
| Accessibility | Named toolbar/rail controls exposed through AT-SPI; semantic Sculpt activation opens a named Size slider. The gizmo mode includes its current value. |
| Native Import / Cancel | Ctrl+O opens GTK; Escape leaves the clean starter scene unchanged. |
| Unicode and units | GTK opens `模型-1in.obj`; focus plus Return chooses Inches. Saved coordinates contain a 25.3999996 mm edge, within float32 precision of 25.4 mm. |
| Native Save / Cancel | Ctrl+S opens GTK; cancel preserves dirty state and creates no file. Saving `项目.mmx` produces a valid two-object project. |
| Keyboard editing | Ctrl+Z removes the import; Ctrl+Shift+Z restores it. |
| Overwrite | Save As Cancel preserves the original SHA-256 and dirty state. Replace writes the changed, valid one-object project. |
| Export | Native GTK exports a valid 960-triangle binary STL (48,084 bytes); the overwrite prompt can be canceled. |
| Permission failure | Saving into a temporary mode-0555 directory reports failure, creates no destination, and preserves the dirty scene. |
| Dirty exit | Real `WM_DELETE_WINDOW` requests exercise Cancel, Save with native-dialog cancellation, successful Save-and-exit, and Discard-and-exit. |
| Crash recovery | Wait for actual periodic autosave, SIGKILL the app, restart: Keep for later preserves recovery bytes. A further restart/Recover restores both objects as unsaved work. Saving requires a chosen path; subsequent native Open restores the saved scene. |

## Reproduce

Install the host tools separately: Xvfb, `dbus-run-session`, xdotool, Python GI
with the Atspi 2.0 typelib, and ImageMagick's `import`. Then, from the repository:

```sh
python3 tool/release/linux_native_acceptance.py \
  --bundle apps/mmx_studio/build/linux/x64/release/bundle \
  --label '0.2.0+1 release, <source commit>'
```

For an extracted release use its `studio/` directory as `--bundle`.
`--xdotool /absolute/path` supports an extracted tool; configure its library
search path if needed. The harness prints its new temporary evidence directory,
leaves JSON/screenshots and test files there, and terminates only its own app,
D-Bus session and Xvfb. A failed assertion exits nonzero and retains evidence.
Run as an ordinary user: root would invalidate the permission test. The harness
uses native selectors rather than app-state path injection, and sends
`WM_DELETE_WINDOW`; `xdotool windowclose` destroys the window and would bypass
the dirty-exit flow.

## Remaining acceptance limits

**[unknown / not certified]** Human screen-reader usability, complete keyboard
navigation of geometry editing, focus order, physical HiDPI/multi-monitor
behavior, accelerated hardware rendering, GNOME/Wayland portal dialogs, and
clean Ubuntu 24.04 installation/uninstallation remain separate checks. This
host's newer libraries do not prove the minimum supported OS. The `.deb` was
not installed. Re-run the harness against the final packaged payload and bind
its hashes to release provenance. Windows/macOS native dialogs, installer
permissions, signing/notarization and real-user platform acceptance require
those hosts and credentials; this Linux run makes no claim about them.
