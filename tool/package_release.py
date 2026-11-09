#!/usr/bin/env python3
"""Build deterministic portable archives and optional native installers.

No artifacts are published. Native installers are unsigned unless a separate
signing job signs them; provenance never infers trust from a local signature.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform as host_platform
import plistlib
import re
import shutil
import subprocess
import tarfile
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parent.parent
BUNDLES = {
    'linux': 'apps/mmx_studio/build/linux/x64/release/bundle',
    'windows': 'apps/mmx_studio/build/windows/x64/runner/Release',
    'macos': 'apps/mmx_studio/build/macos/Build/Products/Release',
}


def digest_file(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def checksum(path):
    path.with_name(path.name + '.sha256').write_text(
        f'{digest_file(path)}  {path.name}\n', encoding='utf-8')


def tree_manifest(directory):
    result = {}
    for path in sorted(directory.rglob('*')):
        name = path.relative_to(directory).as_posix()
        if path.is_symlink():
            result[name] = {'symlink': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': digest_file(path), 'size': path.stat().st_size}
    return result


def portable(stage, destination, system, epoch):
    """Normalize archive metadata; identical staged content yields identical bytes."""
    if system == 'windows':
        destination = destination.with_suffix('.zip')
        date = time.gmtime(max(epoch, 315532800))[:6]
        with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in sorted(stage.rglob('*')):
                if path.is_file():
                    item = zipfile.ZipInfo(path.relative_to(stage.parent).as_posix(), date)
                    item.compress_type = zipfile.ZIP_DEFLATED
                    item.external_attr = (0o100755 if os.access(path, os.X_OK) else 0o100644) << 16
                    archive.writestr(item, path.read_bytes())
    else:
        destination = destination.with_suffix('.tar.gz')
        def normalize(item):
            item.uid = item.gid = 0
            item.uname = item.gname = ''
            item.mtime = epoch
            if item.isdir():
                item.mode = 0o755
            elif item.isfile():
                item.mode = 0o755 if item.mode & 0o111 else 0o644
            return item
        with destination.open('wb') as raw:
            with gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=epoch) as compressed:
                with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                    archive.add(stage, arcname=stage.name, filter=normalize)
    checksum(destination)
    return destination


def macos_components(root, destination):
    """Install app bundles at their declared paths, never an existing build copy."""
    subprocess.run(['pkgbuild', '--analyze', '--root', str(root), str(destination)], check=True)
    components = plistlib.loads(destination.read_bytes())
    def fixed_location(component):
        component['BundleIsRelocatable'] = False
        for child in component.get('ChildBundles', []):
            fixed_location(child)
    for component in components:
        fixed_location(component)
    destination.write_bytes(plistlib.dumps(components))


def native_installer(stage, output, system, version, epoch):
    if system == 'linux':
        with tempfile.TemporaryDirectory(prefix='mmx-deb-') as scratch:
            root = Path(scratch)
            shutil.copytree(stage, root / 'opt/mmx', symlinks=True)
            (root / 'usr/bin').mkdir(parents=True)
            (root / 'usr/bin/mmx').symlink_to('/opt/mmx/mmx')
            (root / 'usr/bin/mmx-studio').symlink_to('/opt/mmx/studio/mmx_studio')
            desktop = root / 'usr/share/applications/mmx-studio.desktop'
            desktop.parent.mkdir(parents=True)
            desktop.write_text('[Desktop Entry]\nType=Application\nName=mmx Studio\nExec=/opt/mmx/studio/mmx_studio\nTerminal=false\nCategories=Graphics;3DGraphics;\n')
            (root / 'DEBIAN').mkdir()
            arch = subprocess.check_output(['dpkg', '--print-architecture'], text=True).strip()
            (root / 'DEBIAN/control').write_text(
                f'Package: mmx\nVersion: {version}\nArchitecture: {arch}\n'
                'Maintainer: mmx contributors\nSection: graphics\nPriority: optional\n'
                'Depends: libgtk-3-0, libstdc++6, libc6\n'
                'Description: Mesh editing studio and geometry CLI\n')
            destination = output / f'mmx-{version}-{arch}-unsigned.deb'
            subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(root), str(destination)],
                           env={**os.environ, 'SOURCE_DATE_EPOCH': str(epoch)}, check=True)
    elif system == 'macos':
        with tempfile.TemporaryDirectory(prefix='mmx-pkg-') as scratch:
            root = Path(scratch) / 'root'
            root.mkdir()
            apps = list((stage / 'studio').glob('*.app'))
            if len(apps) != 1:
                raise RuntimeError('Expected exactly one macOS application bundle')
            (root / 'Applications').mkdir()
            shutil.copytree(apps[0], root / 'Applications/mmx Studio.app', symlinks=True)
            (root / 'usr/local/bin').mkdir(parents=True)
            shutil.copy2(stage / 'mmx', root / 'usr/local/bin/mmx')
            (root / 'usr/local/share/mmx').mkdir(parents=True)
            for item in ('LICENSE', 'NOTICE', 'THIRD_PARTY_LICENSES.txt', 'toolchain.txt', 'dependencies.json'):
                if (stage / item).exists():
                    shutil.copy2(stage / item, root / 'usr/local/share/mmx' / item)
            provenance = json.loads((stage / 'provenance.json').read_text(encoding='utf-8'))
            provenance['manifestRoot'] = '/'
            provenance['files'] = tree_manifest(root)
            (root / 'usr/local/share/mmx/provenance.json').write_text(
                json.dumps(provenance, indent=2, sort_keys=True) + '\n', encoding='utf-8')
            destination = output / f'mmx-{version}-macos-unsigned.pkg'
            components = Path(scratch) / 'components.plist'
            macos_components(root, components)
            subprocess.run(['pkgbuild', '--root', str(root), '--identifier', 'com.mmx.studio',
                            '--component-plist', str(components), '--version', version,
                            '--install-location', '/', str(destination)], check=True)
    else:
        compiler = os.environ.get('ISCC_PATH') or shutil.which('ISCC')
        if not compiler:
            raise RuntimeError('Set ISCC_PATH to the installed Inno Setup compiler')
        destination = output / f'mmx-{version}-windows-unsigned.exe'
        subprocess.run([compiler, f'/DStage={stage}', f'/DOutput={output}', f'/DVersion={version}',
                        str(ROOT / 'tool/release/windows.iss')], check=True)
    checksum(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=BUNDLES)
    parser.add_argument('--native', action='store_true', help='Also compile a native installer')
    args = parser.parse_args()
    bundle = ROOT / BUNDLES[args.platform]
    cli = ROOT / f'packages/mmx_core/mmx-{args.platform}.exe'
    if not bundle.is_dir() or not cli.is_file():
        raise SystemExit('Build the desktop bundle and CLI before packaging')
    if any(bundle.glob('**/flutter_assets/assets/models/*')):
        raise SystemExit('Repository-only model assets found in release bundle; clean and rebuild without demo assets')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    epoch = int(os.environ.get('SOURCE_DATE_EPOCH') or subprocess.check_output(
        ['git', 'show', '-s', '--format=%ct', 'HEAD'], cwd=ROOT, text=True).strip())
    version = re.search(r'^version:\s*(\d+\.\d+\.\d+)',
                        (ROOT / 'apps/mmx_studio/pubspec.yaml').read_text(), re.M).group(1)
    output = ROOT / 'bin/releases'
    output.mkdir(parents=True, exist_ok=True)
    name = f'mmx-{args.platform}-{host_platform.machine()}-{commit[:12]}-unsigned'
    with tempfile.TemporaryDirectory(prefix='mmx-package-') as scratch:
        stage = Path(scratch) / name
        stage.mkdir()
        if args.platform == 'macos':
            apps = list(bundle.glob('*.app'))
            if len(apps) != 1:
                raise RuntimeError('Expected exactly one macOS application bundle')
            # Xcode's Products/Release also contains standalone frameworks,
            # debug symbols and intermediates already embedded inside the app.
            (stage / 'studio').mkdir()
            shutil.copytree(apps[0], stage / 'studio' / apps[0].name, symlinks=True)
        else:
            shutil.copytree(bundle, stage / 'studio', symlinks=True)
        shutil.copy2(cli, stage / ('mmx.exe' if args.platform == 'windows' else 'mmx'))
        if args.platform == 'windows':
            runtime = Path(os.environ.get('MMX_WINDOWS_CRT_DIR', ''))
            if not all((runtime / name).is_file() for name in ('msvcp140.dll', 'vcruntime140.dll')):
                raise RuntimeError('Run tool/release/find_windows_runtime.ps1 and set MMX_WINDOWS_CRT_DIR')
            # Both the CLI and Studio must work without a system-wide VC runtime.
            for library in sorted(runtime.glob('*.dll')):
                shutil.copy2(library, stage / library.name)
                shutil.copy2(library, stage / 'studio' / library.name)
            (stage / 'MICROSOFT_RUNTIME_NOTICE.txt').write_text(
                'Microsoft Visual C++ release runtime, deployed app-local from the build host Visual Studio redistributable directory.\n'
                'Copyright Microsoft Corporation. Redistribution is subject to Microsoft Software License Terms.\n'
                'https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution\n'
                'https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files\n', encoding='utf-8')
        for item in ('LICENSE', 'NOTICE'):
            shutil.copy2(ROOT / item, stage / item)
        for item in ('toolchain.txt', 'dependencies.json', 'THIRD_PARTY_LICENSES.txt'):
            if (ROOT / item).is_file():
                shutil.copy2(ROOT / item, stage / item)
        source_files = subprocess.check_output(['git', 'ls-files', '-co', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
        source_hash = hashlib.sha256()
        for name in sorted(set(source_files) - {'', 'toolchain.txt', 'dependencies.json', 'THIRD_PARTY_LICENSES.txt'}):
            path = ROOT / name
            if path.is_file():
                source_hash.update(name.encode() + b'\0' + digest_file(path).encode())
        manifest = tree_manifest(stage)
        (stage / 'provenance.json').write_text(json.dumps({
            'commit': commit, 'sourceDigest': source_hash.hexdigest(), 'version': version,
            'platform': args.platform, 'architecture': host_platform.machine(), 'signed': False,
            'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT)),
            'files': manifest,
        }, indent=2, sort_keys=True) + '\n', encoding='utf-8')
        archive = portable(stage, output / stage.name, args.platform, epoch)
        print(archive)
        if args.native:
            print(native_installer(stage, output, args.platform, version, epoch))


if __name__ == '__main__':
    main()
