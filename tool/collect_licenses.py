#!/usr/bin/env python3
"""Collect resolved package license texts for shipped artifact review."""
import argparse
import json
from pathlib import Path
from urllib.parse import unquote, urljoin, urlparse

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=root / 'THIRD_PARTY_LICENSES.txt')
args = parser.parse_args()
config_path = root / 'apps/mmx_studio/.dart_tool/package_config.json'
config = json.loads(config_path.read_text())
sections = []
missing = []
for package in sorted(config['packages'], key=lambda p: p['name']):
    if package['name'] in ('mmx_core', 'mmx_studio'):
        continue
    uri = urlparse(urljoin(config_path.as_uri(), package['rootUri']))
    package_root = Path(unquote(uri.path))
    if package_root.as_posix().startswith('/') and len(package_root.as_posix()) > 2 and package_root.as_posix()[2] == ':':
        package_root = Path(package_root.as_posix()[1:])
    licenses = sorted(p for p in package_root.iterdir() if p.is_file() and p.name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')))
    # Flutter SDK package directories share the SDK's root license.
    if not licenses and package_root.parent.name == 'packages' and (package_root.parent.parent / 'LICENSE').exists():
        licenses = [package_root.parent.parent / 'LICENSE']
    if not licenses:
        missing.append(package['name'])
    sections.append(f"{'=' * 72}\nPACKAGE: {package['name']}\n" + '\n'.join(
        f'FILE: {p.name}\n{p.read_text(encoding="utf-8", errors="replace")}' for p in licenses))
args.output.write_text('Resolved Dart/Flutter dependency licenses (includes development dependencies).\n'
                       'Flutter engine bundled notices remain in the application bundle.\n\n' + '\n\n'.join(sections), encoding='utf-8')
if missing:
    raise SystemExit('Missing license texts: ' + ', '.join(missing))
print(args.output)
