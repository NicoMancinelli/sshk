#!/bin/sh
# Shared discovery. Config files contain one literal path, never shell code.
sshk_tailscale_find() {
    SSHK_TS_BIN=${SSHK_TAILSCALE_BIN:-}
    if [ -z "$SSHK_TS_BIN" ]; then
        if [ -x "${SSHK_US_ROOT:-/mnt/us}/extensions/tailscale/bin/tailscale" ]; then
            SSHK_TS_BIN="${SSHK_US_ROOT:-/mnt/us}/extensions/tailscale/bin/tailscale"
        else
            SSHK_TS_BIN=$(command -v tailscale 2>/dev/null) || SSHK_TS_BIN=""
        fi
    fi
    if [ -z "$SSHK_TS_BIN" ] || [ ! -x "$SSHK_TS_BIN" ]; then
        echo 'sshk: Tailscale executable missing. See Tailscale > Setup Help.' >&2
        return 1
    fi
    SSHK_TS_SOCKET=${SSHK_TAILSCALE_SOCKET:-}
    if [ -z "$SSHK_TS_SOCKET" ] && [ -f "$BINDIR/../tailscale.socket" ]; then
        IFS= read -r SSHK_TS_SOCKET < "$BINDIR/../tailscale.socket" || :
    fi
    case "$SSHK_TS_SOCKET" in
        ''|/*) ;;
        *) echo 'sshk: tailscale.socket must contain an absolute socket path.' >&2; return 1 ;;
    esac
}
sshk_tailscale() {
    if [ -n "$SSHK_TS_SOCKET" ]; then
        "$SSHK_TS_BIN" "--socket=$SSHK_TS_SOCKET" "$@"
    else
        "$SSHK_TS_BIN" "$@"
    fi
}
sshk_tailscale_ready() {
    if ! _ts_status=$(sshk_tailscale status --json 2>&1); then
        printf 'sshk: Cannot query Tailscale; check daemon/socket and login.\n%s\n' "$_ts_status" >&2
        return 1
    fi
    if ! printf '%s\n' "$_ts_status" | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
        echo 'sshk: Tailscale is not running/logged in. See Tailscale > Setup Help.' >&2
        return 1
    fi
}
# Dropbear -J is a shell command. Quote every word, including executable path.
sshk_shell_quote() {
    printf "'"
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}
sshk_tailscale_proxy() {
    sshk_shell_quote "$SSHK_TS_BIN"
    if [ -n "$SSHK_TS_SOCKET" ]; then
        printf ' '
        sshk_shell_quote "--socket=$SSHK_TS_SOCKET"
    fi
    printf ' nc '
    sshk_shell_quote "$1"
    printf ' '
    sshk_shell_quote "$2"
}
