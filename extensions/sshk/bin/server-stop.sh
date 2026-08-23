#!/bin/sh
# server-stop.sh - Stops Dropbear SSH server on Kindle

PIDFILE="/tmp/sshk_dropbear.pid"

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

if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
fi

# Also kill any orphan dropbear server processes started from sshk
pkill -f "dropbear -p 2222" 2>/dev/null || true

eips_print_row 5 "Status: STOPPED"
eips_print_row 7 "Inbound SSH server is inactive."
eips_print_row 9 "========================================"

echo "SSH Server stopped."
