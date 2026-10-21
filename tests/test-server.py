"""Server lifecycle checks using a small loopback-only daemon, never host SSH."""
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DAEMON = r'''
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int n, char **v) {
  int port=0; char *pidfile=NULL;
  for(int i=1;i<n-1;i++) {
    if(!strcmp(v[i],"-p")) port=atoi(v[i+1]);
    if(!strcmp(v[i],"-P")) pidfile=v[i+1];
  }
  if(getenv("FAKE_FAIL")) return 1;
  int fd=socket(AF_INET,SOCK_STREAM,0), yes=1;
  setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof yes);
  struct sockaddr_in a={0}; a.sin_family=AF_INET;
  a.sin_addr.s_addr=htonl(INADDR_LOOPBACK); a.sin_port=htons(port);
  if(bind(fd,(void*)&a,sizeof a)||listen(fd,2)) return 2;
  FILE *f=fopen(pidfile,"w"); if(!f) return 3;
  fprintf(f,"%d\n",getpid()); fclose(f);
  for(;;) pause();
}
'''

@unittest.skipUnless(shutil.which('cc'), 'C compiler required for isolated daemon fixture')
class Server(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        self.bin=self.root/'bin'
        self.bin.mkdir()
        for p in (ROOT/'extensions/sshk/bin').glob('server-*.sh'):
            shutil.copy2(p,self.bin/p.name)
        source=self.root/'daemon.c'; source.write_text(DAEMON)
        subprocess.run(['cc',str(source),'-o',str(self.bin/'dropbearmulti')],check=True)
        (self.bin/'kindle_host_ed25519_key').write_text('fixture key')
        self.runtime=self.root/'runtime'
        with socket.socket() as s:
            s.bind(('127.0.0.1',0)); self.port=s.getsockname()[1]
        self.env=dict(os.environ,SSHK_SERVER_RUNTIME=str(self.runtime),SSHK_SERVER_PORT=str(self.port))
        self.addCleanup(self.stop_cleanup)

    def run_script(self,name,success=True):
        r=subprocess.run(['sh',str(self.bin/f'server-{name}.sh')],env=self.env,
                         text=True,capture_output=True,timeout=12)
        if success: self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        else: self.assertNotEqual(r.returncode,0,r.stdout+r.stderr)
        return r.stdout+r.stderr

    def stop_cleanup(self):
        subprocess.run(['sh',str(self.bin/'server-stop.sh')],env=self.env,
                       stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=12)

    def test_repeated_start_stop_and_lost_pidfile(self):
        self.assertIn('started',self.run_script('start'))
        pid=(self.runtime/'server.pid').read_text()
        self.assertIn('already running',self.run_script('start'))
        self.assertEqual((self.runtime/'server.pid').read_text(),pid)
        self.assertIn('RUNNING',self.run_script('status'))
        (self.runtime/'server.pid').unlink()
        self.assertIn('stopped',self.run_script('stop'))
        self.assertIn('No SSH',self.run_script('stop'))
        self.assertIn('not running',self.run_script('status'))

    def test_stale_pid_does_not_kill_unrelated_process(self):
        sleeper=subprocess.Popen(['sleep','30'])
        self.addCleanup(sleeper.wait); self.addCleanup(sleeper.terminate)
        self.runtime.mkdir(mode=0o700)
        (self.runtime/'server.pid').write_text(str(sleeper.pid))
        self.run_script('stop')
        self.assertIsNone(sleeper.poll())

    def test_failed_start_is_not_reported_as_running(self):
        self.env['FAKE_FAIL']='1'
        self.assertIn('failed to start',self.run_script('start',False))
        self.assertFalse((self.runtime/'server.pid').exists())
        self.assertIn('not running',self.run_script('status'))

    def test_occupied_port(self):
        with socket.socket() as s:
            s.bind(('127.0.0.1',self.port)); s.listen()
            self.assertIn('failed to start',self.run_script('start',False))
            self.assertEqual(s.getsockname()[1],self.port)

    def test_host_key_failure(self):
        (self.bin/'kindle_host_ed25519_key').unlink()
        self.assertIn('host key',self.run_script('start',False))

    def test_symlink_runtime_rejected(self):
        elsewhere=self.root/'elsewhere'; elsewhere.mkdir()
        self.runtime.symlink_to(elsewhere)
        self.assertIn('Unsafe',self.run_script('start',False))
        self.assertEqual(list(elsewhere.iterdir()),[])

    def test_legacy_daemon_requires_explicit_upgrade_recovery(self):
        proc=self.root/'proc'; proc.mkdir()
        self.env['SSHK_SERVER_PROC_ROOT']=str(proc)
        folder=proc/'4321'; folder.mkdir()
        args=[str(self.bin/'dropbearmulti'),'dropbear','-p',str(self.port),'-r',
              str(self.bin/'kindle_host_ed25519_key')]
        (folder/'cmdline').write_bytes(('\0'.join(args)+'\0').encode())
        for action in ('start','stop','status'):
            out=self.run_script(action,False)
            self.assertIn('Reboot the Kindle',out)
            self.assertNotIn('STOPPED',out)
        (folder/'cmdline').write_bytes(('\0'.join(['dropbear','-p',str(self.port),'-r',
              str(self.bin/'kindle_host_ed25519_key')])+'\0').encode())
        for action in ('start','stop','status'):
            out=self.run_script(action,False)
            self.assertIn('Reboot the Kindle',out)

    def test_exact_argv_required(self):
        proc=self.root/'proc'; proc.mkdir()
        self.env['SSHK_SERVER_PROC_ROOT']=str(proc)
        folder=proc/'4321'; folder.mkdir()
        args=[str(self.bin/'dropbearmulti'),'dropbear','-p',str(self.port),'-r',
              str(self.bin/'kindle_host_ed25519_key'),'-P',str(self.runtime/'server.pid'),'-F','-s']
        def live(arguments):
            (folder/'cmdline').write_bytes(('\0'.join(arguments)+'\0').encode())
            r=subprocess.run(['sh','-c','BINDIR="$1"; . "$1/server-common.sh"; sshk_server_live_pid',
                              'sh',str(self.bin)],env=self.env,capture_output=True,text=True,check=True)
            return r.stdout.strip()
        self.assertEqual(live(args),'4321')
        self.assertEqual(live(['unrelated']+args),'')
        self.assertEqual(live([a.replace('kindle_host_ed25519_key','other_key') for a in args]),'')
        self.assertEqual(live(args[:-1]),'')
        self.assertEqual(live([a.replace(str(self.port),str(self.port)+'0') for a in args]),'')

if __name__=='__main__': unittest.main()
