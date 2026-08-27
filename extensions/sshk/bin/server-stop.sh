#!/bin/sh
# server-stop.sh - Stops Dropbear SSH server on Kindle

PIDFILE="/tmp/sshk_dropbear.pid"
PORT="2222"

# Pattern matching our own dropbear process. Dropbear is invoked via the
# multi-call binary, so the live process argv is
# `dropbearmulti dropbear -p <PORT> -r <HOST_KEY> ...`. Anchoring on
# `^dropbearmulti dropbear` prevents accidentally killing any unrelated
# process whose argv happens to mention "dropbear -p 2222".
DROPBEAR_PATTERN="dropbear .*-p $PORT"

eips_print_row() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                                                "
    eips 0 "$ROW" "$TEXT"
}

eips -c 2>/dev/null
eips_print_row 1 "========================================"
eips_print_row 2 "  sshk: Stopping SSH Server..."
eips_print_row 3 "========================================"

STOPPED=0

# First try the pidfile. The pidfile PID is usually stale (dropbear double-
# forks), so a failed kill -0 is expected; fall back to the pidfile value
# being wrong and just rely on the process-table match below.
if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
        STOPPED=1
    fi
    rm -f "$PIDFILE"
fi

# Process-table match is the authoritative kill (covers orphans too).
if command -v pkill >/dev/null 2>&1; then
    if pkill -f "$DROPBEAR_PATTERN" 2>/dev/null; then
        STOPPED=1
    fi
elif command -v pgrep >/dev/null 2>&1; then
    PIDS=$(pgrep -f "$DROPBEAR_PATTERN" 2>/dev/null)
    if [ -n "$PIDS" ]; then
        for P in $PIDS; do
            kill "$P" 2>/dev/null || true
        done
        STOPPED=1
    fi
fi

if [ "$STOPPED" -eq 1 ]; then
    sleep 1   # let dropbear release the port before we re-clear the screen
    eips_print_row 5 "Status: STOPPED"
    eips_print_row 7 "Inbound SSH server is inactive."
else
    eips_print_row 5 "Status: NOT RUNNING"
    eips_print_row 7 "No live sshk dropbear process detected."
fi
eips_print_row 9 "========================================"

if [ "$STOPPED" -eq 1 ]; then
    echo "SSH Server stopped."
else
    echo "No SSH server was running."
fi
exit 0
