#!/bin/sh
# server-toggle.sh - Single menu action: starts the inbound SSH server when
# stopped, stops it when running. Delegates to server-start.sh / server-stop.sh.

BINDIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="/tmp/sshk_dropbear.pid"
PORT="2222"

# Same anchored pattern used by server-start.sh and server-stop.sh so we
# don't false-positive on the wrapper shell argv (which itself contains
# "-p $PORT" during start-up).
DROPBEAR_PATTERN="dropbear .*-p $PORT"

RUNNING=""
if [ -f "$PIDFILE" ]; then
    P=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
        RUNNING="$P"
    fi
fi
# Dropbear daemonizes; pidfile PID may be stale. Fall back to pgrep, anchored
# to the actual multi-call binary so the start-up wrapper is not matched.
if [ -z "$RUNNING" ] && command -v pgrep >/dev/null 2>&1; then
    RUNNING=$(pgrep -f "$DROPBEAR_PATTERN" 2>/dev/null | head -n 1)
fi

if [ -n "$RUNNING" ]; then
    exec "$BINDIR/server-stop.sh"
else
    exec "$BINDIR/server-start.sh"
fi
