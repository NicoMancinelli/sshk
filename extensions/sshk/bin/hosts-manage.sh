#!/bin/sh
# Atomic, serialized updates to hosts.conf. Never evaluate host-file content.
set -eu
BINDIR="$(cd "$(dirname "$0")" && pwd)"
CONF="$BINDIR/../hosts.conf"
OP=${1:-}
NAME=${2:-}
TARGET=${3:-}
KEY=${4:-}
TRANSPORT=${5:-direct}
case "$TRANSPORT" in direct|tailscale) ;; *) echo "Transport must be direct or tailscale." >&2; exit 2 ;; esac
case "$OP" in add|edit|remove) ;; *) exit 2 ;; esac
case "$NAME" in ''|*[!A-Za-z0-9_-]*) echo "Alias may only contain letters, digits, '_' and '-'." >&2; exit 2 ;; esac
if [ "$OP" != remove ]; then
    case "$TARGET" in ''|-*|*[[:space:]#]*) echo "Invalid target: no spaces, '#', or leading '-'." >&2; exit 2 ;; esac
    case "$KEY" in *[!A-Za-z0-9_-]*) echo "Key name may only contain letters, digits, '_' and '-'." >&2; exit 2 ;; esac
fi
LOCK="$CONF.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Host file is busy. Retry; if interrupted, remove hosts.conf.lock." >&2
    exit 1
fi
TMP=""
trap '[ -z "$TMP" ] || rm -f "$TMP"; rmdir "$LOCK"' EXIT
trap 'exit 1' HUP INT TERM
[ ! -L "$CONF" ] || { echo "Refusing to replace a symlink." >&2; exit 1; }
COUNT=0
if [ -f "$CONF" ]; then
    COUNT=$(awk -v name="$NAME" '$1==name { n++ } END { print n+0 }' "$CONF")
fi
if [ "$OP" = add ]; then
    [ "$COUNT" -eq 0 ] || { echo "Alias already exists; use Edit." >&2; exit 1; }
else
    [ "$COUNT" -eq 1 ] || { echo "Expected one matching alias; found $COUNT. File unchanged." >&2; exit 1; }
fi
TMP=$(mktemp "$CONF.tmp.XXXXXX")
export SSHK_HOST_TRANSPORT="$TRANSPORT"
export SSHK_HOST_NAME="$NAME" SSHK_HOST_TARGET="$TARGET" SSHK_HOST_KEY="$KEY" SSHK_HOST_OP="$OP"
# ENVIRON preserves backslashes literally, unlike awk -v replacement values.
if [ -f "$CONF" ]; then
    awk '
    BEGIN { name=ENVIRON["SSHK_HOST_NAME"]; op=ENVIRON["SSHK_HOST_OP"]; entry=name " " ENVIRON["SSHK_HOST_TARGET"]; key=ENVIRON["SSHK_HOST_KEY"]; if (ENVIRON["SSHK_HOST_TRANSPORT"]=="tailscale") entry=entry " " (key!="" ? key : "-") " tailscale"; else if (key!="") entry=entry " " key }
    $1==name && op=="remove" { next }
    $1==name && op=="edit" { comment=index($0,"#"); print entry (comment ? " " substr($0,comment) : ""); next }
    { print }
    ' "$CONF" > "$TMP"
fi
if [ "$OP" = add ]; then
    if [ "$TRANSPORT" = tailscale ]; then
        printf '%s %s %s tailscale\n' "$NAME" "$TARGET" "${KEY:--}" >> "$TMP"
    else
        printf '%s %s%s\n' "$NAME" "$TARGET" "${KEY:+ $KEY}" >> "$TMP"
    fi
fi
mv "$TMP" "$CONF"
TMP=""
echo "Host $OP complete: $NAME"
