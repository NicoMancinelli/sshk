#!/bin/sh
# server-status.sh - Reports whether the inbound Dropbear SSH server is running
# and, when it is, the exact command to connect to this Kindle from a computer.

case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
# shellcheck disable=SC1091  # resolved via $BINDIR at runtime; linted standalone
. "$BINDIR/server-common.sh"

LIVE_PID=$(sshk_server_live_pid)
WIFI_IP=$(sshk_wifi_ip)
[ -n "$WIFI_IP" ] || WIFI_IP="<Kindle-IP>"

eips -c 2>/dev/null
sshk_eips_row 1 "========================================"
sshk_eips_row 2 "  sshk: SSH Server Status"
sshk_eips_row 3 "========================================"

LISTENING_PID=""
for PID in $LIVE_PID; do
    if sshk_server_listening "$PID"; then LISTENING_PID="$PID"; break; fi
done
LIVE_PID="$LISTENING_PID"
if [ -n "$LIVE_PID" ]; then
    sshk_eips_row 5 "Status: RUNNING (PID: $LIVE_PID)"
    sshk_eips_row 6 "Port: $SSHK_SERVER_PORT"
    sshk_eips_row 7 "IP: $WIFI_IP"
    sshk_eips_row 9 "Connect from your PC:"
    sshk_eips_row 10 "  ssh root@$WIFI_IP -p $SSHK_SERVER_PORT"
    echo "SSH server RUNNING (PID $LIVE_PID) on $WIFI_IP:$SSHK_SERVER_PORT"
    echo "Connect from your PC:  ssh root@$WIFI_IP -p $SSHK_SERVER_PORT"
elif [ -n "$(sshk_server_legacy_pid)" ]; then
    sshk_server_legacy_notice
    exit 1
else
    sshk_eips_row 5 "Status: STOPPED"
    sshk_eips_row 7 "Start it from KUAL > sshk > SSH Server."
    echo "SSH server is not running. Start it from KUAL > sshk > SSH Server."
fi
sshk_eips_row 12 "========================================"
exit 0
