"""Integration checks with isolated host files, Kindle root and SSH endpoint."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Workflows(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.us = self.root / 'Kindle'
        self.ext = self.us / 'extensions/sshk'
        self.bin = self.ext / 'bin'
        shutil.copytree(ROOT / 'extensions/sshk/bin', self.bin)
        self.conf = self.ext / 'hosts.conf'
        self.conf.write_text('# Saved hosts\nalpha user@old work # retain this\nbeta user@other\n')
        self.mocks = self.root / 'mocks'
        self.mocks.mkdir()
        self.env = dict(os.environ, SSHK_US_ROOT=str(self.us),
                        PATH=str(self.mocks) + ':' + os.environ['PATH'],
                        SSHK_ROOT_HOME=str(self.root / 'root'),
                        SSHK_SERVER_PROC_ROOT=str(self.root / 'proc'))
        self.env['SSHK_EIPS_LOG'] = str(self.root / 'eips.log')
        self.stub('eips', "printf '%s\\n' \"$*\" >> \"$SSHK_EIPS_LOG\"")
        self.stub('sleep', 'exit 0')
        self.stub('clear', 'exit 0')
        self.stub('pgrep', 'exit 1')

    def stub(self, name, body):
        p = self.mocks / name
        p.write_text('#!/bin/sh\n' + body + '\n')
        p.chmod(0o755)

    def run_cmd(self, command, input='', ok=True):
        result = subprocess.run([str(x) for x in command], input=input, text=True,
                                capture_output=True, env=self.env, cwd=self.root,
                                timeout=10)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result.stdout + result.stderr

    def manage(self, *args, **kwargs):
        return self.run_cmd([self.bin / 'hosts-manage.sh', *args], **kwargs)

    def test_edit_remove_preserve_other_lines(self):
        self.manage('edit', 'alpha', 'new@host:2200', '')
        self.assertEqual(self.conf.read_text(), '# Saved hosts\nalpha new@host:2200 # retain this\nbeta user@other\n')
        self.manage('remove', 'alpha')
        self.assertEqual(self.conf.read_text(), '# Saved hosts\nbeta user@other\n')

    def test_rejected_edits_leave_file_intact(self):
        before = self.conf.read_bytes()
        for args in [('add', 'alpha', 'x@y'), ('edit', 'missing', 'x@y'),
                     ('add', 'new', '-option'), ('edit', 'alpha', 'x y'),
                     ('edit', 'alpha', 'x@y', 'bad key'), ('remove', 'a;exit')]:
            self.manage(*args, ok=False)
            self.assertEqual(self.conf.read_bytes(), before)
        self.assertFalse(list(self.ext.glob('hosts.conf.*')))

    def test_duplicate_and_locked_file(self):
        self.conf.write_text('alpha a@b\nalpha c@d\n')
        before = self.conf.read_bytes()
        self.manage('remove', 'alpha', ok=False)
        self.assertEqual(self.conf.read_bytes(), before)
        (self.ext / 'hosts.conf.lock').mkdir()
        self.manage('add', 'new', 'x@y', ok=False)
        self.assertEqual(self.conf.read_bytes(), before)

    def test_menu_edit_and_confirm_remove(self):
        self.run_cmd([self.bin / 'ssh-menu'], 'e\nalpha\nnew@host\n-\ndirect\nq\n')
        self.assertIn('alpha new@host # retain this', self.conf.read_text())
        before = self.conf.read_bytes()
        self.run_cmd([self.bin / 'ssh-menu'], 'd\nalpha\nno\nq\n')
        self.assertEqual(self.conf.read_bytes(), before)
        self.run_cmd([self.bin / 'ssh-menu'], 'd\nalpha\nYES\nq\n')
        self.assertNotIn('alpha', self.conf.read_text())

    def test_status_missing_and_ready(self):
        out = self.run_cmd([self.bin / 'setup-status.sh'])
        self.assertIn('Terminal: missing', out)
        self.assertIn('Kindle client key: missing', out)
        self.assertIn('Computer access keys: missing', out)
        self.assertIn('SSH server: stopped', out)
        kterm = self.us / 'extensions/kterm/bin/kterm'
        kterm.parent.mkdir(parents=True)
        kterm.write_text('#!/bin/sh\n')
        kterm.chmod(0o755)
        (self.bin / 'kindle_native_key').write_text('key')
        (self.us / 'kindle_ssh_key.pub').write_text('public')
        (self.ext / '.ssh').mkdir()
        (self.ext / '.ssh/authorized_keys').write_text('computer key')
        proc = self.root / 'proc/1234'
        proc.mkdir(parents=True)
        runtime = self.root / 'runtime'
        self.env['SSHK_SERVER_RUNTIME'] = str(runtime)
        args = [str(self.bin / 'dropbearmulti'), 'dropbear', '-p', '2222',
                '-r', str(self.bin / 'kindle_host_ed25519_key'),
                '-P', str(runtime / 'server.pid'), '-F', '-s']
        (proc / 'cmdline').write_bytes(b'\0'.join(x.encode() for x in args) + b'\0')
        out = self.run_cmd([self.bin / 'setup-status.sh'])
        for text in ['Terminal: installed', 'Kindle client key: present',
                     'Exported public key: present', 'Computer access keys: staged',
                     'SSH server: running']:
            self.assertIn(text, out)

    def test_kual_guidance_stays_within_eink_bounds(self):
        for script in ['setup-status.sh', 'key-help.sh', 'tailscale-status.sh', 'tailscale-help.sh']:
            self.run_cmd([self.bin / script])
            lines = (self.root / 'eips.log').read_text().splitlines()
            for line in lines:
                fields = line.split(maxsplit=2)
                if len(fields) == 3 and fields[0] == '0' and fields[1].isdigit():
                    self.assertLessEqual(int(fields[1]), 22, f'{script}: row {line}')
                    self.assertLessEqual(len(fields[2]), 48, f'{script}: width {line}')
            (self.root / 'eips.log').write_text('')

    def test_inbound_idempotent_and_reject_private(self):
        key = self.root / 'computer.pub'
        key.write_text('ssh-ed25519 AAAATEST computer\n')
        script = ROOT / 'authorize-kindle.sh'
        self.run_cmd([script, self.us, key])
        dest = self.ext / '.ssh/authorized_keys'
        before = dest.read_bytes()
        key.write_text('ssh-ed25519 AAAATEST renamed\n')
        self.run_cmd([script, self.us, key])
        self.assertEqual(dest.read_bytes(), before)
        key.write_text('-----BEGIN OPENSSH PRIVATE KEY-----\n')
        self.run_cmd([script, self.us, key], ok=False)
        self.assertEqual(dest.read_bytes(), before)

    def test_outbound_key_is_stdin_not_shell_code(self):
        remote = self.root / 'remote'
        remote.mkdir()
        self.env['SSHK_TEST_REMOTE'] = str(remote)
        self.stub('ssh', 'shift 3\nHOME="$SSHK_TEST_REMOTE" /bin/sh -c "$1"')
        # Comments may contain shell syntax; it must stay literal data.
        key = "ssh-ed25519 AAAATEST $(touch SHOULD_NOT_EXIST); 'quoted'\n"
        (self.root / 'kindle_ssh_key.pub').write_text(key)
        script = ROOT / 'authorize-server.sh'
        self.run_cmd([script, 'user@server'])
        dest = remote / '.ssh/authorized_keys'
        self.assertEqual(dest.read_text().strip(), key.strip())
        before = dest.read_bytes()
        self.run_cmd([script, 'user@server'])
        self.assertEqual(dest.read_bytes(), before)
        self.assertFalse((self.root / 'SHOULD_NOT_EXIST').exists())
        self.assertFalse((self.ext / '.ssh').exists())
        self.run_cmd([script, 'user@server', '-p'], ok=False)

    def test_outbound_failures_do_not_claim_success(self):
        self.stub('ssh', 'exit 23')
        (self.root / 'kindle_ssh_key.pub').write_text('ssh-ed25519 AAAATEST test\n')
        out = self.run_cmd([ROOT / 'authorize-server.sh', 'user@host'], ok=False)
        self.assertNotIn('Success!', out)
        (self.root / 'kindle_ssh_key.pub').write_text('-----BEGIN OPENSSH PRIVATE KEY-----\n')
        out = self.run_cmd([ROOT / 'authorize-server.sh', 'user@host'], ok=False)
        self.assertIn('Expected one OpenSSH public key', out)

    def test_add_literal_target_and_cancelled_edit(self):
        self.manage('add', 'literal', r'user@host\name', 'work')
        self.assertIn(r'literal user@host\name work', self.conf.read_text())
        before = self.conf.read_bytes()
        self.run_cmd([self.bin / 'ssh-menu'], 'e\nalpha\n')
        self.assertEqual(self.conf.read_bytes(), before)

    def test_menu_actions_exist(self):
        def check(items):
            for index, item in enumerate(items):
                self.assertEqual(item['priority'], index)
                if 'menu' in item:
                    check(item['menu']['items'])
                else:
                    self.assertTrue(os.access(ROOT / 'extensions/sshk' / item['action'], os.X_OK))
        check(json.loads((ROOT / 'extensions/sshk/menu.json').read_text())['items'])

    def test_kterm_landscape_dpi_and_layout(self):
        kterm_dir = self.us / 'extensions/kterm'
        kterm_bin = kterm_dir / 'bin/kterm'
        kterm_bin.parent.mkdir(parents=True, exist_ok=True)
        layouts = kterm_dir / 'layouts'
        layouts.mkdir(parents=True, exist_ok=True)
        (layouts / 'keyboard-300dpi.xml').write_text('<layout/>')
        log = self.root / 'var/log'
        log.mkdir(parents=True, exist_ok=True)
        (log / 'Xorg.0.log').write_text('(300, 300) DPI\n')

        args_log = self.root / 'kterm_args.log'
        stub = f'#!/bin/sh\nprintf "%s\\n" "$@" > "{args_log}"\n'
        kterm_bin.write_text(stub)
        kterm_bin.chmod(0o755)

        script = self.bin / 'kterm-landscape.sh'
        self.run_cmd([script])
        args = args_log.read_text().splitlines()
        self.assertIn('-o', args)
        self.assertIn('R', args)
        self.assertIn('-s', args)
        self.assertIn('8', args)
        self.assertIn('-e', args)
        self.assertTrue(any('ssh-menu' in a for a in args))


if __name__ == '__main__':
    unittest.main()
