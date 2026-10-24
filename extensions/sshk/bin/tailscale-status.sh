#!/bin/sh
BINDIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$BINDIR/tailscale-common.sh"
# shellcheck disable=SC1091
. "$BINDIR/ui-common.sh"
sshk_ui_begin 'sshk Tailscale Status'
if ! sshk_tailscale_find 2>/dev/null; then
    sshk_ui_line 'Tailscale executable not found.'
    sshk_ui_line 'Open Tailscale > Setup Help.'
    exit 0
fi
sshk_ui_line "CLI: $SSHK_TS_BIN"
sshk_ui_line "Socket: ${SSHK_TS_SOCKET:-Tailscale default}"
if sshk_tailscale_ready 2>/dev/null; then
    sshk_ui_line 'Tailscale is running and logged in.'
    sshk_ui_line "Tailnet IP: $(sshk_tailscale ip -4 2>/dev/null)"
    sshk_ui_line 'Use Open SSH and choose Custom Tailscale,'
    sshk_ui_line 'or save a host with transport tailscale.'
else
    sshk_ui_line 'Daemon unavailable, stopped, or not logged in.'
    sshk_ui_line 'Check your Tailscale extension and socket.'
    sshk_ui_line 'Open Setup Help; run tailscale status in kterm.'
fi
