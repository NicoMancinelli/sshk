#!/usr/bin/env python3
"""Exercise userspace transport without touching device state or a real tailnet."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'extensions/sshk/bin'


class TailscaleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="sshk tail's ")
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ('ssh-tailscale', 'scp-tailscale', 'sshk-common.sh',
                     'tailscale-common.sh', 'hosts-manage.sh', 'ssh-menu', 'ssh', 'scp', 'scp-common.sh'):
            shutil.copy2(SOURCE / name, self.bin / name)
        self.env = dict(os.environ, SSHK_TEST_FORCE_AUTO_ACCEPT='1',
                        SSHK_ROOT_HOME=str(self.root), SSHK_US_ROOT=str(self.root),
                        LOG=str(self.root / 'argv.json'),
                        TSLOG=str(self.root / 'ts.json'),
                        SSHK_TAILSCALE_SOCKET=str(self.root / "socket's path"))
        self.script('dbclient', '''import json,os,sys,subprocess
json.dump(sys.argv[1:],open(os.environ['LOG'],'w'))
if os.environ.get('RUN_PROXY'):
 subprocess.run(sys.argv[sys.argv.index('-J')+1],shell=True,check=True)
''')
        self.script('dropbearmulti', "import json,os,sys\njson.dump(sys.argv[1:],open(os.environ['LOG'],'w'))\n")
        self.ts = self.script('tailscale', '''import json,os,sys
if 'status' in sys.argv:
 print(json.dumps({'BackendState':os.environ.get('TS_STATE','Running')}))
 sys.exit(int(os.environ.get('TS_EXIT','0')))
json.dump(sys.argv[1:],open(os.environ['TSLOG'],'w'))
''')
        self.env['SSHK_TAILSCALE_BIN'] = str(self.ts)
        (self.bin / 'kindle_native_key').touch()
        (self.root / 'hosts.conf').write_text('legacy user@old:2222 work\nmesh user@node:2200 - tailscale\n')

    def tearDown(self):
        self.tmp.cleanup()

    def script(self, name, body):
        import sys
        path = self.bin / name
        path.write_text('#!' + sys.executable + '\n' + body)
        path.chmod(0o755)
        return path

    def run_script(self, name, *args, stdin=None, **env):
        return subprocess.run([str(self.bin / name), *args], env=dict(self.env, **env),
                              input=stdin, text=True, capture_output=True, timeout=10)

    def argv(self):
        return json.loads((self.root / 'argv.json').read_text())

    def test_proxy_preserves_quoted_paths_and_port(self):
        p = self.run_script('ssh-tailscale', 'user@node:2201', 'echo', 'hello world', RUN_PROXY='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads((self.root/'ts.json').read_text()),
                         ['--socket='+self.env['SSHK_TAILSCALE_SOCKET'], 'nc', 'node', '2201'])
        self.assertEqual(self.argv()[-3:], ['user@node', 'echo', 'hello world'])

    def test_explicit_port_overrides_alias(self):
        p = self.run_script('ssh-tailscale', '-p2223', 'mesh')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.argv()[:2], ['-p', '2223'])

    def test_injection_and_invalid_ports(self):
        for target in ('user@node;touch${IFS}oops', 'user@node:22;id', 'user@node:0', 'user@node:65536', 'user@node:'):
            p = self.run_script('ssh-tailscale', target)
            self.assertNotEqual(p.returncode, 0, target)
        self.assertFalse((self.root/'argv.json').exists())

    def test_daemon_and_login_failures(self):
        for state, code in [('NeedsLogin', '0'), ('Stopped', '0'), ('Running', '1')]:
            p = self.run_script('ssh-tailscale', 'mesh', TS_STATE=state, TS_EXIT=code)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn('sshk:', p.stderr)
        self.assertFalse((self.root/'argv.json').exists())

    def test_missing_binary(self):
        p = self.run_script('ssh-tailscale', 'mesh', SSHK_TAILSCALE_BIN='/missing/tailscale')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('executable missing', p.stderr)

    def test_root_discovery_and_socket_file(self):
        target = self.root/'extensions/tailscale/bin/tailscale'
        target.parent.mkdir(parents=True)
        shutil.copy2(self.ts, target)
        (self.root/'tailscale.socket').write_text('/custom/socket\n')
        p = self.run_script('ssh-tailscale', 'mesh', SSHK_TAILSCALE_BIN='', SSHK_TAILSCALE_SOCKET='', RUN_PROXY='1')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads((self.root/'ts.json').read_text())[0], '--socket=/custom/socket')

    def test_scp_argv_spaces_alias_source_and_target(self):
        p = self.run_script('scp-tailscale', 'local file *', 'mesh:/remote path')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.argv()[-2:], ['local file *', 'user@node:/remote path'])
        self.assertIn('2200', self.argv())
        p = self.run_script('scp-tailscale', 'mesh:/remote file', 'local file')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.argv()[-2:], ['user@node:/remote file', 'local file'])

    def test_transport_save_and_tui_selection(self):
        p = self.run_script('hosts-manage.sh', 'add', 'new', 'user@node', '', 'tailscale')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('new user@node - tailscale', (self.root/'hosts.conf').read_text())
        p = self.run_script('ssh-menu', stdin='new\n')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('[Tailscale]', p.stdout)
        self.assertIn('-J', self.argv())
        self.script('ssh', "import sys\nprint('DIRECT',sys.argv[1])\n")
        p = self.run_script('ssh-menu', stdin='legacy\n')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('DIRECT legacy', p.stdout)

    def test_ssh_dispatch_preserves_options_and_command(self):
        p = self.run_script('ssh', '-p', '2228', '-i', '/custom/key', 'mesh', 'printf', 'a b')
        self.assertEqual(p.returncode, 0, p.stderr)
        args = self.argv()
        self.assertEqual(args[:2], ['-p', '2228'])
        self.assertEqual(args[-5:], ['-i', '/custom/key', 'user@node', 'printf', 'a b'])

    def test_scp_dispatch(self):
        for alias, transport in [('mesh', 'ssh-tailscale'), ('legacy', 'ssh')]:
            p = self.run_script('scp', '-P', '2228', 'a b', alias+':/path')
            self.assertEqual(p.returncode, 0, p.stderr)
            args = self.argv()
            self.assertEqual(args[args.index('-S')+1], str(self.bin/transport))
            self.assertEqual(args[args.index('-P')+1], '2228')

    def test_duplicate_alias_rejected(self):
        with (self.root/'hosts.conf').open('a') as f:
            f.write('mesh other@host - direct\n')
        for script, args in [('ssh', ['mesh']), ('ssh-tailscale', ['mesh']),
                             ('scp', ['file', 'mesh:/path'])]:
            p = self.run_script(script, *args)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn('duplicate alias', p.stderr)

    def test_invalid_transport_does_not_modify_file(self):
        before = (self.root/'hosts.conf').read_bytes()
        p = self.run_script('hosts-manage.sh', 'add', 'bad', 'user@node', '', 'garbage')
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(before, (self.root/'hosts.conf').read_bytes())


if __name__ == '__main__':
    unittest.main()
