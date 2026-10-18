#!/bin/sh
# server-common.sh - shared helpers for the inbound dropbear server scripts.
#
# Sourced (never executed) by server-start.sh, server-stop.sh,
# server-toggle.sh and server-status.sh. The port, the pidfile path, the
# process-match pattern and the eips/status helpers used to be copy-pasted into
# each script, which is exactly how they can drift apart. This mirrors
# sshk-common.sh on the client side.
#
# Callers resolve BINDIR first (they need it to find this file and
# dropbearkey/dropbearmulti).

# Port and pidfile for the inbound server. The pidfile records the live daemon
# PID; dropbear double-forks, so a stale value is expected and the live PID is
# re-derived from the process table.
SSHK_SERVER_PORT="2222"
SSHK_SERVER_PIDFILE="/tmp/sshk_dropbear.pid"

# Token pattern identifying OUR dropbear daemon in the global process table.
# The live argv depends on invocation:
#   * direct: `dropbearmulti dropbear -p <port> -r <key> ...`
#   * qemu:   `qemu-arm-static <...>/.real-dropbearmulti dropbear -p <port> ...`
# In both cases ` dropbear -p <port>` appears, so we match that substring and
# deliberately do NOT anchor on `dropbearmulti` (qemu replaces its own argv
# before exec'ing the real binary). The phrase is specific enough that a false
# positive on a Kindle is exceedingly unlikely.
SSHK_DROPBEAR_PATTERN="dropbear .*-p $SSHK_SERVER_PORT"

# sshk_eips_row ROW TEXT
#   Draw TEXT at ROW, blanking the line first so a previously longer line does
#   not leave residue on the e-ink screen. No-op off Kindle (eips absent).
sshk_eips_row() {
    eips 0 "$1" "                                                                                " 2>/dev/null
    eips 0 "$1" "$2" 2>/dev/null
}

# sshk_server_live_pid
#   Print the PID of a running sshk dropbear daemon, or nothing if none is
#   running. Returns via stdout so callers can use it in `$(...)`.
sshk_server_live_pid() {
    command -v pgrep >/dev/null 2>&1 || return 0
    pgrep -f "$SSHK_DROPBEAR_PATTERN" 2>/dev/null | head -n 1
}

# sshk_wifi_ip
#   Print the wlan0 IPv4 address, or nothing. Prefers `ip`, falls back to
#   `ifconfig` for older firmware. One `awk` per source rather than the old
#   `grep | cut | awk` pipeline — Kindle forks are expensive.
sshk_wifi_ip() {
    _ip=""
    if command -v ip >/dev/null 2>&1; then
        _ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }')
    fi
    if [ -z "$_ip" ] && command -v ifconfig >/dev/null 2>&1; then
        _ip=$(ifconfig wlan0 2>/dev/null | awk '/inet addr:/ { sub(/.*inet addr:/, ""); sub(/[[:space:]].*/, ""); print; exit }')
    fi
    printf '%s\n' "$_ip"
}

# The port / pidfile / pattern above are consumed by the sourcing server
# scripts, which shellcheck cannot see from here. This reference keeps SC2034
# from firing (same idiom as sshk-common.sh).
: "$SSHK_SERVER_PORT" "$SSHK_SERVER_PIDFILE" "$SSHK_DROPBEAR_PATTERN"
