#!/bin/sh
# server-stop.sh - Stops the inbound Dropbear SSH server on Kindle

case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
# shellcheck disable=SC1091  # resolved via $BINDIR at runtime; linted standalone
. "$BINDIR/server-common.sh"

eips -c 2>/dev/null
sshk_eips_row 1 "========================================"
sshk_eips_row 2 "  sshk: Stopping SSH Server..."
sshk_eips_row 3 "========================================"

STOPPED=0

# First try the pidfile. The pidfile PID is usually stale (dropbear double-
# forks), so a failed kill -0 is expected; the process-table match below is the
# authoritative kill and also covers orphans.
if [ -f "$SSHK_SERVER_PIDFILE" ]; then
    PID=$(cat "$SSHK_SERVER_PIDFILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        STOPPED=1
    fi
    rm -f "$SSHK_SERVER_PIDFILE"
fi

if command -v pkill >/dev/null 2>&1; then
    if pkill -f "$SSHK_DROPBEAR_PATTERN" 2>/dev/null; then
        STOPPED=1
    fi
elif command -v pgrep >/dev/null 2>&1; then
    PIDS=$(pgrep -f "$SSHK_DROPBEAR_PATTERN" 2>/dev/null)
    if [ -n "$PIDS" ]; then
        for P in $PIDS; do
            kill "$P" 2>/dev/null || true
        done
        STOPPED=1
    fi
fi

if [ "$STOPPED" -eq 1 ]; then
    sleep 1   # let dropbear release the port before we re-clear the screen
    sshk_eips_row 5 "Status: STOPPED"
    sshk_eips_row 7 "Inbound SSH server is inactive."
    echo "SSH Server stopped."
else
    sshk_eips_row 5 "Status: NOT RUNNING"
    sshk_eips_row 7 "No live sshk dropbear process detected."
    echo "No SSH server was running."
fi
sshk_eips_row 9 "========================================"
exit 0
