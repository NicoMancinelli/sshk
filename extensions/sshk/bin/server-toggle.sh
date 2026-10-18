#!/bin/sh
# server-toggle.sh - Single menu action: starts the inbound SSH server when
# stopped, stops it when running. Delegates to server-start.sh / server-stop.sh
# (server-start.sh is itself idempotent, so a race cannot start two daemons).

case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
# shellcheck disable=SC1091  # resolved via $BINDIR at runtime; linted standalone
. "$BINDIR/server-common.sh"

if [ -n "$(sshk_server_live_pid)" ]; then
    exec "$BINDIR/server-stop.sh"
else
    exec "$BINDIR/server-start.sh"
fi
