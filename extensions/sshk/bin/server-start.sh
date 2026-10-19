#!/bin/sh
# server-start.sh - Starts the inbound Dropbear SSH server on Kindle (port 2222)

case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
# shellcheck disable=SC1091  # resolved via $BINDIR at runtime; linted standalone
. "$BINDIR/server-common.sh"

# Already running? Refresh the pidfile and report instead of racing a second
# daemon onto the same port.
LIVE_PID=$(sshk_server_live_pid)
if [ -n "$LIVE_PID" ]; then
    echo "$LIVE_PID" > "$SSHK_SERVER_PIDFILE"
    eips -c 2>/dev/null
    sshk_eips_row 2 "SSH Server is already running!"
    sshk_eips_row 3 "PID: $LIVE_PID (Port $SSHK_SERVER_PORT)"
    echo "SSH Server already running (PID $LIVE_PID, port $SSHK_SERVER_PORT)."
    exit 0
fi

# Ensure the host key exists.
HOST_KEY="$BINDIR/kindle_host_ed25519_key"
if [ ! -f "$HOST_KEY" ]; then
    sshk_eips_row 2 "Generating host key..."
    "$BINDIR/dropbearkey" -t ed25519 -f "$HOST_KEY" >/dev/null 2>&1
fi

WIFI_IP=$(sshk_wifi_ip)
[ -n "$WIFI_IP" ] || WIFI_IP="<Kindle-IP>"

# Start dropbear. -p: port, -r: hostkey.
# NOTE: deliberately NO -B (blank-password logins). Kindle root accounts often
# have no password; inbound access is public-key only via
# extensions/sshk/.ssh/authorized_keys (see authorize-server.sh).
"$BINDIR/dropbearmulti" dropbear -p "$SSHK_SERVER_PORT" -r "$HOST_KEY" > /tmp/dropbear.log 2>&1 &
WRAPPER_PID=$!

# Dropbear double-forks: the immediate child of WRAPPER_PID is a short-lived
# parent that itself forks the actual daemon. Wait for it to settle and capture
# the live PID from the process table so the pidfile points at the right
# process for server-stop.sh.
sleep 2
LIVE_PID=$(sshk_server_live_pid)
[ -n "$LIVE_PID" ] || LIVE_PID="$WRAPPER_PID"
echo "$LIVE_PID" > "$SSHK_SERVER_PIDFILE"

# Display status on the e-ink screen.
eips -c 2>/dev/null
sshk_eips_row 1 "========================================"
sshk_eips_row 2 "  sshk: Inbound SSH Server Started"
sshk_eips_row 3 "========================================"
sshk_eips_row 5 "Status: RUNNING (PID: $LIVE_PID)"
sshk_eips_row 6 "Port: $SSHK_SERVER_PORT"
sshk_eips_row 7 "IP: $WIFI_IP"
sshk_eips_row 9 "Connect from your PC:"
sshk_eips_row 10 "  ssh root@$WIFI_IP -p $SSHK_SERVER_PORT"
sshk_eips_row 12 "========================================"

echo "SSH Server started on $WIFI_IP:$SSHK_SERVER_PORT (PID: $LIVE_PID)"
