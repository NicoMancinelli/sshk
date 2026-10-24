#!/bin/sh
case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
# shellcheck disable=SC1091
. "$BINDIR/server-common.sh"

sshk_server_lock || exit 1
if [ -n "$(sshk_server_legacy_pid)" ]; then
    sshk_server_legacy_notice
    exit 1
fi
PIDS=$(sshk_server_live_pid)
for PID in $PIDS; do
    # Recheck immediately before signaling; never trust a pidfile or regex.
    if sshk_server_owned "$PID"; then kill "$PID" 2>/dev/null || :; fi
done
tries=0
while [ -n "$(sshk_server_live_pid)" ] && [ "$tries" -lt 5 ]; do
    sleep 1
    tries=$((tries + 1))
done
if [ -n "$(sshk_server_live_pid)" ]; then
    sshk_eips_row 2 "SSH server did not stop."
    echo "SSH server did not stop; inspect $SSHK_SERVER_LOG." >&2
    exit 1
fi
rm -f "$SSHK_SERVER_PIDFILE"
sshk_eips_row 2 "SSH server stopped."
if [ -n "$PIDS" ]; then echo "SSH Server stopped."; else echo "No SSH server was running."; fi
