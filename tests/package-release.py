#!/usr/bin/env python3
"""Build and verify a clean distribution, excluding device state and keys."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DOCS = ['QUICKSTART.md', 'README.md', 'CHANGELOG.md', 'SUPPORTED-DEVICES.md',
        'LICENSE', 'DROPBEAR-LICENSE', 'RELEASE-CHECKLIST.md']
DESKTOP = ['install-to-kindle.sh', 'install-to-kindle.bat', 'install-to-kindle.ps1',
           'authorize-server.sh', 'authorize-kindle.sh']
CONFIG = ['VERSION', 'DROPBEAR_VERSION', 'config.xml', 'menu.json', 'hosts.conf']
BINARIES = {'dbclient', 'dropbear', 'dropbearkey', 'dropbearmulti', 'ssh', 'sshk',
            'ssh-menu', 'ssh-tailscale', 'scp', 'scp-tailscale', 'eips-refresh'}


def package(destination):
    ext = ROOT / 'extensions/sshk'
    version = (ext / 'VERSION').read_text().strip()
    assert ET.parse(ext / 'config.xml').findtext('./information/version') == version
    tag = os.environ.get('GITHUB_REF', '')
    if tag.startswith('refs/tags/'):
        assert tag == 'refs/tags/v' + version, 'Tag does not match payload version'
    files = [ROOT / f for f in DOCS + DESKTOP]
    files += [ext / f for f in CONFIG]
    files += [p for p in (ext / 'bin').iterdir() if p.name in BINARIES or p.suffix == '.sh']
    paths = {p.relative_to(ROOT).as_posix() for p in files}

    def check_menu(items):
        for i, item in enumerate(items):
            assert item['priority'] == i
            assert len(item['name']) <= 48
            if 'menu' in item:
                assert item['menu']['items']
                check_menu(item['menu']['items'])
            else:
                action = 'extensions/sshk/' + item['action']
                assert action in paths, action
                assert os.access(ROOT / action, os.X_OK), action
    check_menu(json.loads((ext / 'menu.json').read_text())['items'])
    destination.mkdir(parents=True, exist_ok=True)
    archive = destination / 'sshk.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(files):
            assert path.is_file() and not path.is_symlink(), path
            name = path.relative_to(ROOT).as_posix()
            data = path.read_bytes()
            assert (data.startswith(b'\x7fELF') or b'PRIVATE KEY-----' not in data), f'Private key in {name}'
            info = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
            info.create_system = 3
            executable = name.startswith('extensions/sshk/bin/') or name.endswith('.sh')
            info.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        assert len(z.namelist()) == len(paths)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / 'SHA256SUMS').write_text(digest + '  sshk.zip\n')
    print(f'Verified {archive}: {len(paths)} files, version {version}, sha256 {digest}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'out/release')
    package(parser.parse_args().output.resolve())
