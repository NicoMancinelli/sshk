#!/bin/sh
# server-start.sh - Starts Dropbear SSH server on Kindle (Port 2222)

BINDIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="/tmp/sshk_dropbear.pid"
PORT="2222"

# Pattern used to identify OUR dropbear process in the global process table.
# The live process argv depends on how the multi-call binary is invoked:
#   * direct:        `dropbearmulti dropbear -p <PORT> -r <KEY> ...`
#   * qemu-arm-static wrapper: `qemu-arm-static <...>/.real-dropbearmulti dropbear -p <PORT> -r <KEY> ...`
# In both cases the cmdline contains ` dropbear -p <PORT>` as a substring, so
# the pattern below matches. We do not anchor on `dropbearmulti` because
# qemu replaces its own argv before exec'ing the real binary, so the
# cmdline of the daemon process under qemu begins with `qemu-arm-static`,
# not `dropbearmulti`. The `dropbear .*-p <PORT>` token match is still
# specific enough to avoid false positives: a process whose argv happens
# to contain that exact phrase and is *not* our dropbear daemon is
# exceedingly unlikely on the Kindle.
DROPBEAR_PATTERN="dropbear .*-p $PORT"

eips_print_row() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                                                "
    eips 0 "$ROW" "$TEXT"
}

# Look up a live PID for our server, ignoring any stale content in $PIDFILE
# (Dropbear double-forks, so the pidfile PID goes stale at once). Returns the
# PID via stdout, or empty if no live server was found.
find_live_pid() {
    if command -v pgrep >/dev/null 2>&1; then
        pgrep -f "$DROPBEAR_PATTERN" 2>/dev/null | head -n 1
    fi
}

# Check if already running.
LIVE_PID=""
if LIVE_PID=$(find_live_pid) && [ -n "$LIVE_PID" ]; then
    :
fi
if [ -n "$LIVE_PID" ]; then
    echo "$LIVE_PID" > "$PIDFILE"
    eips -c 2>/dev/null
    eips_print_row 2 "SSH Server is already running!"
    eips_print_row 3 "PID: $LIVE_PID (Port $PORT)"
    exit 0
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
    WIFI_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d ' ' -f2)
fi
if [ -z "$WIFI_IP" ] && command -v ifconfig >/dev/null 2>&1; then
    WIFI_IP=$(ifconfig wlan0 2>/dev/null | grep 'inet addr:' | cut -d: -f2 | awk '{print $1}')
fi
if [ -z "$WIFI_IP" ]; then
    WIFI_IP="<Kindle-IP>"
fi

# Start dropbear server.
# -p: port, -r: hostkey, -E: log to stderr
# NOTE: deliberately NO -B (blank-password logins). Kindle root accounts often
# have no password; inbound access is public-key only via
# extensions/sshk/.ssh/authorized_keys (see authorize-server.sh).
"$BINDIR/dropbearmulti" dropbear -p "$PORT" -r "$HOST_KEY" > /tmp/dropbear.log 2>&1 &
WRAPPER_PID=$!

# Dropbear double-forks: the immediate child of WRAPPER_PID is a short-lived
# parent that itself forks the actual daemon. Wait for the daemon to settle
# and capture the live PID from the process table so $PIDFILE points at the
# right process for server-stop.sh.
sleep 2
LIVE_PID=""
if LIVE_PID=$(find_live_pid) && [ -n "$LIVE_PID" ]; then
    :
fi
if [ -z "$LIVE_PID" ]; then
    LIVE_PID="$WRAPPER_PID"
fi
echo "$LIVE_PID" > "$PIDFILE"

# Display status on e-ink screen
eips -c 2>/dev/null
eips_print_row 1 "========================================"
eips_print_row 2 "  sshk: Inbound SSH Server Started"
eips_print_row 3 "========================================"
eips_print_row 5 "Status: RUNNING (PID: $LIVE_PID)"
eips_print_row 6 "Port: $PORT"
eips_print_row 7 "IP: $WIFI_IP"
eips_print_row 9 "Connect from your PC:"
eips_print_row 10 "  ssh root@$WIFI_IP -p $PORT"
eips_print_row 12 "========================================"

echo "SSH Server started on $WIFI_IP:$PORT (PID: $LIVE_PID)"
