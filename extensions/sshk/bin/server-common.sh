#!/bin/sh
# Inbound server ownership is verified against exact /proc arguments before
# signaling. A stale pidfile alone is never evidence of ownership.
SSHK_SERVER_PORT=${SSHK_SERVER_PORT:-2222}
SSHK_SERVER_RUNTIME=${SSHK_SERVER_RUNTIME:-/tmp/sshk-server}
SSHK_SERVER_PIDFILE="$SSHK_SERVER_RUNTIME/server.pid"
SSHK_SERVER_LOG="$SSHK_SERVER_RUNTIME/server.log"
SSHK_SERVER_PROC_ROOT=${SSHK_SERVER_PROC_ROOT:-/proc}
SSHK_SERVER_BINARY=${SSHK_SERVER_BINARY:-$BINDIR/dropbearmulti}
SSHK_SERVER_HOST_KEY="$BINDIR/kindle_host_ed25519_key"

sshk_eips_row() {
    eips 0 "$1" "                                                                                " 2>/dev/null || :
    eips 0 "$1" "$2" 2>/dev/null || :
}

# First shortlist /proc cmdlines by the exact bundled binary path in one grep.
# Candidate files are then parsed one at a time: BusyBox awk does not
# consistently support NUL record separators, and grep -H prefixes every
# argument once it treats NUL as a record boundary.
sshk_server_match_file() {
    file=$1
    mode=$2
    pid=${file%/cmdline}
    pid=${pid##*/}
    tr '\000' '\n' < "$file" 2>/dev/null | awk \
        -v mode="$mode" -v binary="$SSHK_SERVER_BINARY" -v port="$SSHK_SERVER_PORT" \
        -v key="$SSHK_SERVER_HOST_KEY" -v pidfile="$SSHK_SERVER_PIDFILE" \
        -v pid="$pid" '
    { arg[NR]=$0 }
    END {
        start=1
        if (arg[1] ~ /(^|\/)qemu-arm(-static)?$/) start=2
        count=NR
        if (mode=="legacy" && arg[1]=="dropbear") {
            if (count==5 && arg[2]=="-p" && arg[3]==port &&
                arg[4]=="-r" && arg[5]==key) print pid
            exit
        }
        if (count < start+5 || arg[start]!=binary || arg[start+1]!="dropbear" ||
            arg[start+2]!="-p" || arg[start+3]!=port ||
            arg[start+4]!="-r" || arg[start+5]!=key) exit 1
        if (mode=="legacy") {
            if (count==start+5) print pid
            exit
        }
        if (count < start+9 || arg[start+6]!="-P" || arg[start+7]!=pidfile) exit 1
        foreground=0; keyonly=0; bad=0
        for (i=start+8; i<=count; i++) {
            if (arg[i]=="-F") foreground++
            else if (arg[i]=="-s") keyonly++
            else bad=1
        }
        if (foreground==1 && keyonly==1 && !bad && pid>1) print pid
    }'
}

sshk_server_match() {
    mode=$1
    shift
    grep -alF "$SSHK_SERVER_BINARY" "$@" 2>/dev/null |
        while IFS= read -r file; do sshk_server_match_file "$file" "$mode"; done || :
}

sshk_server_owned() {
    case "$1" in ''|*[!0-9]*|0|1) return 1 ;; esac
    [ "$(sshk_server_match current "$SSHK_SERVER_PROC_ROOT/$1/cmdline")" = "$1" ]
}

sshk_server_live_pid() {
    # The pidfile is only a fast candidate: it still requires exact ownership.
    if [ -r "$SSHK_SERVER_PIDFILE" ]; then
        candidate=$(cat "$SSHK_SERVER_PIDFILE" 2>/dev/null)
        if sshk_server_owned "$candidate"; then
            printf '%s\n' "$candidate"
            return
        fi
    fi
    sshk_server_match current "$SSHK_SERVER_PROC_ROOT"/[0-9]*/cmdline
}

sshk_server_legacy_pid() {
    # Legacy Dropbear may rewrite argv[0] to just "dropbear" after forking.
    grep -alF "$SSHK_SERVER_HOST_KEY" "$SSHK_SERVER_PROC_ROOT"/[0-9]*/cmdline 2>/dev/null |
        while IFS= read -r file; do sshk_server_match_file "$file" legacy; done || :
}

sshk_server_legacy_notice() {
    sshk_eips_row 2 "Old sshk SSH server still running."
    sshk_eips_row 4 "Reboot Kindle, then start SSH again."
    echo "An old sshk SSH server is still running. Reboot the Kindle, then start SSH again to apply the upgraded server settings." >&2
}

sshk_server_listening() {
    sshk_server_owned "$1" || return 1
    hexport=$(printf '%04X' "$SSHK_SERVER_PORT")
    sockets=$(awk -v port=":$hexport" '$2 ~ port "$" && $4=="0A" {print $10}' \
        "$SSHK_SERVER_PROC_ROOT/$1/net/tcp" "$SSHK_SERVER_PROC_ROOT/$1/net/tcp6" 2>/dev/null)
    for fd in "$SSHK_SERVER_PROC_ROOT/$1/fd/"*; do
        target=$(readlink "$fd" 2>/dev/null) || continue
        for inode in $sockets; do
            [ "$target" = "socket:[$inode]" ] && return 0
        done
    done
    return 1
}

sshk_server_lock() {
    umask 077
    case "$SSHK_SERVER_PORT" in ''|*[!0-9]*) echo "Invalid SSH server port." >&2; return 1 ;; esac
    [ "$SSHK_SERVER_PORT" -ge 1 ] && [ "$SSHK_SERVER_PORT" -le 65535 ] || return 1
    if [ -L "$SSHK_SERVER_RUNTIME" ]; then
        echo "Unsafe SSH server runtime directory." >&2; return 1
    fi
    mkdir -m 700 "$SSHK_SERVER_RUNTIME" 2>/dev/null || :
    [ -d "$SSHK_SERVER_RUNTIME" ] && [ "$(stat -c %u "$SSHK_SERVER_RUNTIME")" = "$(id -u)" ] || return 1
    chmod 700 "$SSHK_SERVER_RUNTIME" || return 1
    if ! mkdir "$SSHK_SERVER_RUNTIME/lock" 2>/dev/null; then
        echo "Another SSH server action is running (or its lock needs recovery)." >&2
        return 1
    fi
    trap 'rmdir "$SSHK_SERVER_RUNTIME/lock" 2>/dev/null || :' 0
    trap 'exit 1' HUP INT TERM
}

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


# Consumed by sourcing lifecycle scripts.
: "$SSHK_SERVER_LOG"
