#!/bin/sh
# Read-only setup diagnostics, available both from KUAL and a terminal.
BINDIR="$(cd "$(dirname "$0")" && pwd)"
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"
# shellcheck disable=SC1091
. "$BINDIR/server-common.sh"
# shellcheck disable=SC1091
. "$BINDIR/ui-common.sh"
report() { sshk_ui_line "$1"; }
sshk_ui_begin "sshk: Setup & Status"
if [ -x "$US_ROOT/extensions/kterm/bin/kterm" ] || [ -x "$US_ROOT/extensions/kterm/bin/kterm.sh" ]; then
    report "Terminal: installed"
else
    report "Terminal: missing"
    report "  Install kterm in extensions/kterm."
fi
if [ -s "$BINDIR/kindle_native_key" ]; then
    report "Kindle client key: present"
else
    report "Kindle client key: missing"
    report "  SSH Keys > Create Default Key"
fi
if [ -s "$US_ROOT/kindle_ssh_key.pub" ]; then
    report "Exported public key: present"
else
    report "Exported public key: missing"
    report "  SSH Keys > Export Default Public Key"
fi
if [ -s "${SSHK_ROOT_HOME:-/root}/.ssh/authorized_keys" ]; then
    report "Computer access keys: active"
elif [ -s "$BINDIR/../.ssh/authorized_keys" ]; then
    report "Computer access keys: staged"
    report "  Run Install / Repair to activate."
else
    report "Computer access keys: missing"
    report "  SSH Keys > Connection Setup Help"
fi
if [ -n "$(sshk_server_live_pid)" ]; then
    report "SSH server: running (port 2222)"
else
    report "SSH server: stopped"
    report "  SSH Server > Start Server"
fi
report ""
report "Address: SSH Server > Server Status"
report "Tailscale: see Tailscale > Status"
report "First install: Setup & Maintenance"
report "  > Install / Repair"
exit 0
