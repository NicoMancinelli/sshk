#!/bin/sh
# server-toggle.sh - Single menu action: starts the inbound SSH server when
# stopped, stops it when running. Delegates to server-start.sh / server-stop.sh.

BINDIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="/tmp/sshk_dropbear.pid"
PORT="2222"

RUNNING=""
if [ -f "$PIDFILE" ]; then
    P=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
        RUNNING="$P"
    fi
fi
# Dropbear daemonizes; pidfile PID may be stale. Fall back to pgrep.
if [ -z "$RUNNING" ] && command -v pgrep >/dev/null 2>&1; then
    RUNNING=$(pgrep -f "dropbear.*-p $PORT" 2>/dev/null | head -n 1)
fi

if [ -n "$RUNNING" ]; then
    exec "$BINDIR/server-stop.sh"
else
    exec "$BINDIR/server-start.sh"
fi
