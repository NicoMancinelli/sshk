#!/bin/sh
case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
# shellcheck disable=SC1091
. "$BINDIR/server-common.sh"

sshk_server_lock || exit 1
if [ -n "$(sshk_server_legacy_pid)" ]; then
    sshk_server_legacy_notice
    exit 1
fi
LIVE_PID=$(sshk_server_live_pid)
if [ -n "$LIVE_PID" ]; then
    for PID in $LIVE_PID; do
        if sshk_server_listening "$PID"; then
            sshk_eips_row 2 "SSH server is already running."
            echo "SSH Server already running (PID $PID, port $SSHK_SERVER_PORT)."
            exit 0
        fi
    done
    echo "SSH server process exists but is not listening; stop it before retrying." >&2
    exit 1
fi
rm -f "$SSHK_SERVER_PIDFILE"
if [ ! -s "$SSHK_SERVER_HOST_KEY" ]; then
    if ! "$BINDIR/dropbearkey" -t ed25519 -f "$SSHK_SERVER_HOST_KEY" >/dev/null 2>&1 ||
       [ ! -s "$SSHK_SERVER_HOST_KEY" ]; then
        sshk_eips_row 2 "SSH server: host key generation failed."
        echo "Cannot generate SSH host key." >&2
        exit 1
    fi
fi
chmod 600 "$SSHK_SERVER_HOST_KEY" || exit 1
# Foreground mode makes $! the real daemon after exec. Explicit -s disables
# all password authentication, including nonempty account passwords.
"$BINDIR/dropbearmulti" dropbear -p "$SSHK_SERVER_PORT" \
    -r "$SSHK_SERVER_HOST_KEY" -P "$SSHK_SERVER_PIDFILE" -F -s \
    > "$SSHK_SERVER_LOG" 2>&1 < /dev/null &
PID=$!
tries=0
while [ "$tries" -lt 5 ]; do
    sleep 1
    if sshk_server_listening "$PID"; then
        WIFI_IP=$(sshk_wifi_ip)
        [ -n "$WIFI_IP" ] || WIFI_IP="<Kindle-IP>"
        sshk_eips_row 2 "SSH server running (port $SSHK_SERVER_PORT)."
        sshk_eips_row 4 "ssh root@$WIFI_IP -p $SSHK_SERVER_PORT"
        echo "SSH Server started on $WIFI_IP:$SSHK_SERVER_PORT (PID: $PID)"
        exit 0
    fi
    kill -0 "$PID" 2>/dev/null || break
    tries=$((tries + 1))
done
if sshk_server_owned "$PID"; then kill "$PID" 2>/dev/null || :; fi
rm -f "$SSHK_SERVER_PIDFILE"
sshk_eips_row 2 "SSH server failed to start."
sshk_eips_row 4 "Port may be in use. See server.log."
echo "SSH server failed to start. Check $SSHK_SERVER_LOG (port may already be in use)." >&2
exit 1
