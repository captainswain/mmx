#!/usr/bin/env python3
"""Verify installed artifact content against its manifest without modifying it."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('manifest', type=Path)
parser.add_argument('--root', required=True, type=Path)
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
files = manifest['files']
if not files:
    raise SystemExit('Artifact manifest is empty')
for name, expected in files.items():
    relative = PurePosixPath(name)
    if relative.is_absolute() or '..' in relative.parts or '\\' in name:
        raise SystemExit(f'Invalid manifest path: {name}')
    path = args.root.joinpath(*relative.parts)
    if 'symlink' in expected:
        if not path.is_symlink() or os.readlink(path) != expected['symlink']:
            raise SystemExit(f'Symlink mismatch: {name}')
    else:
        with path.open('rb') as content:
            digest = hashlib.file_digest(content, 'sha256').hexdigest()
        if digest != expected['sha256'] or path.stat().st_size != expected['size']:
            raise SystemExit(f'Content mismatch: {name}')
print(f'Verified {len(files)} installed manifest entries')
