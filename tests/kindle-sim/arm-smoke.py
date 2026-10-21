#!/usr/bin/env python3
"""Exercise the shipped ARM binary and real menu scripts in a temporary root."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
qemu = os.environ.get('QEMU_ARM') or shutil.which('qemu-arm-static') or shutil.which('qemu-arm')
if not qemu:
    raise SystemExit('ARM verification requires qemu-arm-static or qemu-arm; no stub substitution.')

with tempfile.TemporaryDirectory(prefix='sshk-arm-') as temporary:
    root = Path(temporary)
    us = root / 'us'
    ext = us / 'extensions/sshk'
    shutil.copytree(ROOT / 'extensions/sshk', ext)
    bin_dir = ext / 'bin'
    real = bin_dir / 'dropbearmulti.arm'
    (bin_dir / 'dropbearmulti').rename(real)
    wrapper = bin_dir / 'dropbearmulti'
    wrapper.write_text('#!/bin/sh\nexec "$QEMU_ARM" "$SSHK_SERVER_BINARY" "$@"\n')
    wrapper.chmod(0o755)
    home = root / 'root'
    home.mkdir()
    mocks = root / 'mocks'
    mocks.mkdir()
    eips_log = root / 'eips.log'
    (mocks / 'eips').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$EIPS_LOG"\n')
    (mocks / 'eips').chmod(0o755)
    kterm = us / 'extensions/kterm/bin'
    kterm.mkdir(parents=True)
    for name in ['kterm', 'kterm.sh']:
        p = kterm / name
        p.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        p.chmod(0o755)
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    env = dict(os.environ, QEMU_ARM=qemu, SSHK_US_ROOT=str(us),
               SSHK_ROOT_HOME=str(home), SSHK_SERVER_BINARY=str(real),
               SSHK_SERVER_RUNTIME=str(root / 'runtime'), SSHK_SERVER_PORT=str(port),
               EIPS_LOG=str(eips_log), PATH=str(mocks) + ':' + os.environ['PATH'])

    def run(name, *args):
        result = subprocess.run([str(bin_dir / name), *args], env=env,
                                capture_output=True, text=True, timeout=30)
        if result.returncode:
            log = root / 'runtime/server.log'
            processes = []
            for cmd in Path('/proc').glob('[0-9]*/cmdline'):
                try:
                    argv = cmd.read_bytes().replace(b'\0', b' ').decode(errors='replace')
                    if str(real) in argv or 'dropbear' in argv:
                        processes.append(f'{cmd.parent.name}: {argv}')
                except OSError:
                    pass
            checks = []
            for item in processes:
                pid, _ = item.split(':', 1)
                check = subprocess.run(['sh', '-c', 'BINDIR="$1"; . "$1/server-common.sh"; echo owned=$(sshk_server_owned "$2" && echo yes || echo no); echo listening=$(sshk_server_listening "$2" && echo yes || echo no); cat "$SSHK_SERVER_PROC_ROOT/$2/net/tcp"', 'sh', str(bin_dir), pid], env=env, capture_output=True, text=True)
                checks.append(check.stdout)
            raise AssertionError(f'{name}: {result.stdout}\n{result.stderr}\n' +
                                 (log.read_text() if log.exists() else '') +
                                 '\nPROCESS DEBUG: ' + repr(processes) + '\n' + repr(checks))
        print('PASS', name, *args)
        return result.stdout

    try:
        run('install.sh')
        key = (bin_dir / 'kindle_native_key').read_bytes()
        run('install.sh')
        assert (bin_dir / 'kindle_native_key').read_bytes() == key
        assert (us / 'kindle_ssh_key.pub').read_text().startswith('ssh-ed25519 ')
        run('genkey.sh', 'work')
        run('showkey.sh', 'work')
        run('listkeys.sh')
        assert '-o\nR' in run('kterm-landscape.sh')
        run('setup-status.sh')
        run('key-help.sh')
        run('server-start.sh')
        pidfile = root / 'runtime/server.pid'
        pid = pidfile.read_text()
        run('server-start.sh')
        assert pidfile.read_text() == pid
        with socket.create_connection(('127.0.0.1', port), timeout=5) as client:
            assert client.recv(256).startswith(b'SSH-2.0-')
        assert 'RUNNING' in run('server-status.sh')
        run('server-stop.sh')
        run('server-stop.sh')
        with socket.socket() as client:
            client.settimeout(2)
            assert client.connect_ex(('127.0.0.1', port)) != 0
        run('server-toggle.sh')
        run('server-toggle.sh')
        with (kterm / 'kterm.sh').open('a') as f:
            f.write('# later user change\n')
        run('uninstall.sh', '--force')
        assert '# later user change' in (kterm / 'kterm.sh').read_text()
        assert (bin_dir / 'kindle_native_key').read_bytes() == key
        run('install.sh')
        print('PASS real ARM key generation, lifecycle, TCP banner, recovery and menu smoke checks')
    finally:
        # Only the staged binary/hostkey/runtime signature can be signaled.
        subprocess.run([str(bin_dir / 'server-stop.sh')], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
