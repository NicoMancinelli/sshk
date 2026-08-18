#!/bin/sh
# server-start.sh - Starts Dropbear SSH server on Kindle (Port 2222)

BINDIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="/tmp/sshk_dropbear.pid"
PORT="2222"

eips_print_row() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                                                "
    eips 0 "$ROW" "$TEXT"
}

# Check if already running
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if kill -0 "$OLD_PID" 2>/dev/null; then
        eips -c 2>/dev/null
        eips_print_row 2 "SSH Server is already running!"
        eips_print_row 3 "PID: $OLD_PID (Port $PORT)"
        exit 0
    fi
    rm -f "$PIDFILE"
fi

# Ensure host keys exist
HOST_KEY="$BINDIR/kindle_host_ed25519_key"
if [ ! -f "$HOST_KEY" ]; then
    eips_print_row 2 "Generating host key..."
    "$BINDIR/dropbearkey" -t ed25519 -f "$HOST_KEY" >/dev/null 2>&1
fi

# Determine current IP address
WIFI_IP=""
if command -v ip >/dev/null 2>&1; then
    WIFI_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d' ' -f2)
fi
if [ -z "$WIFI_IP" ] && command -v ifconfig >/dev/null 2>&1; then
    WIFI_IP=$(ifconfig wlan0 2>/dev/null | grep 'inet addr:' | cut -d: -f2 | awk '{print $1}')
fi
if [ -z "$WIFI_IP" ]; then
    WIFI_IP="<Kindle-IP>"
fi

# Start dropbear server
# -p: port, -r: hostkey, -B: allow empty password (or uses system auth), -E: log to stderr
"$BINDIR/dropbearmulti" dropbear -p "$PORT" -r "$HOST_KEY" -B > /tmp/dropbear.log 2>&1 &
SERVER_PID=$!

echo "$SERVER_PID" > "$PIDFILE"
sleep 1

# Display status on e-ink screen
eips -c 2>/dev/null
eips_print_row 1 "========================================"
eips_print_row 2 "  sshk: Inbound SSH Server Started"
eips_print_row 3 "========================================"
eips_print_row 5 "Status: RUNNING (PID: $SERVER_PID)"
eips_print_row 6 "Port: $PORT"
eips_print_row 7 "IP: $WIFI_IP"
eips_print_row 9 "Connect from your PC:"
eips_print_row 10 "  ssh root@$WIFI_IP -p $PORT"
eips_print_row 12 "========================================"

echo "SSH Server started on $WIFI_IP:$PORT (PID: $SERVER_PID)"
