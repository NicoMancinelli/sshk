#!/bin/sh
BINDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$BINDIR/ui-common.sh"
sshk_ui_begin 'sshk Tailscale Setup'
sshk_ui_line 'Requires separately installed Kindle-compatible'
sshk_ui_line 'tailscale + tailscaled, already logged in.'
sshk_ui_line 'Use your Tailscale extension to start/login.'
sshk_ui_line 'Without TUN, start tailscaled with:'
sshk_ui_line '  --tun=userspace-networking'
sshk_ui_line 'sshk uses tailscale nc for outbound SSH/SCP.'
sshk_ui_line 'It does not start or install Tailscale.'
sshk_ui_line 'Custom daemon socket? Put its absolute path'
sshk_ui_line 'on line 1 of extensions/sshk/tailscale.socket.'
sshk_ui_line 'CLI overrides: SSHK_TAILSCALE_BIN and'
sshk_ui_line 'SSHK_TAILSCALE_SOCKET (export before sshk).'
sshk_ui_line 'Run tailscale --socket=/your/socket status'
sshk_ui_line 'then up to authenticate if needed, in kterm.'
sshk_ui_line 'Remote SSH server + tailnet access required.'
sshk_ui_line 'This does not expose Kindle SSH to a tailnet.'
