#!/usr/bin/env python3
"""Isolated installer recovery tests; never access real /root or a Kindle."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.us = self.root / 'usb'
        self.ext = self.us / 'extensions/sshk'
        self.bin = self.ext / 'bin'
        self.bin.mkdir(parents=True)
        for name in ('install.sh', 'uninstall.sh', 'showkey.sh'):
            shutil.copy2(REPO / 'extensions/sshk/bin' / name, self.bin / name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.kterm = self.us / 'extensions/kterm/bin/kterm.sh'
        self.kterm.parent.mkdir(parents=True)
        self.kterm.write_text('#!/bin/sh\necho original\n')
        self.stub = self.root / 'stubs'
        self.stub.mkdir()
        self.script(self.stub / 'eips', 'exit 0\n')
        self.script(self.bin / 'dropbearkey', '''[ "$FAIL_KEY" != 1 ] || exit 7
if [ "$1" = -y ]; then
 echo 'ssh-ed25519 AAAA test'
 echo 'Fingerprint: SHA256:test'
else
 while [ "$1" != -f ]; do shift; done
 shift
 echo private > "$1"
fi
''')
        self.env = dict(os.environ, SSHK_US_ROOT=str(self.us), SSHK_ROOT_HOME=str(self.home), PATH=f'{self.stub}:' + os.environ['PATH'])

    def script(self, path, body):
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)

    def run_script(self, name='install.sh', *args, success=True):
        result = subprocess.run(['sh', str(self.bin / name), *args], env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('Installation complete!', result.stdout)
        return result

    def test_fresh_repeat_uninstall_preserves_data_and_kterm_edits(self):
        self.run_script()
        self.run_script()
        self.assertTrue((self.home / '.ssh').is_symlink())
        (self.home / '.ssh/known_hosts').write_text('known host\n')
        self.kterm.write_text(self.kterm.read_text() + 'echo user change\n')
        self.assertEqual(self.kterm.read_text().count('export PATH='), 1)
        self.run_script('uninstall.sh', '--force')
        self.assertFalse((self.home / '.ssh').is_symlink())
        self.assertEqual((self.home / '.ssh/known_hosts').read_text(), 'known host\n')
        self.assertIn('echo user change', self.kterm.read_text())
        self.assertNotIn('export PATH=', self.kterm.read_text())
        self.run_script('uninstall.sh', '--force')

    def test_existing_directory_and_staged_keys(self):
        ssh = self.home / '.ssh'
        ssh.mkdir()
        (ssh / 'authorized_keys').write_text('ssh-ed25519 old')
        (ssh / 'config').write_text('user config')
        (self.ext / '.ssh').mkdir()
        (self.ext / '.ssh/authorized_keys').write_text('ssh-ed25519 new\n')
        self.run_script()
        self.run_script()
        self.assertFalse(ssh.is_symlink())
        keys = (ssh / 'authorized_keys').read_text()
        self.assertIn('ssh-ed25519 old\n', keys)
        self.assertEqual(keys.count('ssh-ed25519 new'), 1)
        self.assertEqual((ssh / 'config').read_text(), 'user config')

    def test_foreign_symlink_preserved(self):
        foreign = self.root / 'foreign'
        foreign.mkdir()
        (foreign / 'config').write_text('foreign')
        (self.home / '.ssh').symlink_to(foreign)
        self.run_script()
        self.run_script('uninstall.sh', '--force')
        self.assertEqual((self.home / '.ssh').resolve(), foreign)
        self.assertEqual((foreign / 'config').read_text(), 'foreign')

    def test_key_failure_is_reported(self):
        self.env['FAIL_KEY'] = '1'
        self.run_script(success=False)

    def test_broken_foreign_symlink_is_not_replaced(self):
        (self.home / '.ssh').symlink_to(self.root / 'missing')
        self.run_script(success=False)
        self.assertTrue((self.home / '.ssh').is_symlink())

    def test_desktop_upgrade_preserves_local_files(self):
        release = self.root / 'release'
        source = release / 'extensions/sshk'
        (source / 'bin').mkdir(parents=True)
        shutil.copy2(REPO / 'install-to-kindle.sh', release)
        (source / 'hosts.conf').write_text('sample hosts')
        (source / 'bin/kindle_native_key').write_text('never deploy key')
        (source / 'bin/ssh').write_text('new code')
        (self.ext / 'hosts.conf').write_text('my hosts')
        (self.bin / 'kindle_native_key').write_text('my private key')
        (self.ext / '.ssh').mkdir()
        (self.ext / '.ssh/known_hosts').write_text('trusted hosts')
        (self.ext / 'state').mkdir()
        (self.ext / 'state/tailscaled.state').write_text('secret state')
        result = subprocess.run(['sh', str(release / 'install-to-kindle.sh')], env=dict(self.env, SSHK_KINDLE_PATH=str(self.us)), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.ext / 'hosts.conf').read_text(), 'my hosts')
        self.assertEqual((self.bin / 'kindle_native_key').read_text(), 'my private key')
        self.assertEqual((self.bin / 'ssh').read_text(), 'new code')
        self.assertEqual((self.ext / '.ssh/known_hosts').read_text(), 'trusted hosts')
        self.assertEqual((self.ext / 'state/tailscaled.state').read_text(), 'secret state')


if __name__ == '__main__':
    unittest.main()
