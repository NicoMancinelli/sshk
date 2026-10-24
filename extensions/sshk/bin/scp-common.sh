#!/bin/sh
# Shared argv-safe SCP alias handling. Sourced after choosing transport.
# Preserve each argument, including spaces and wildcard characters in paths.
COUNT=$#
i=0
HAS_I=0
HAS_P=0
SSHK_ALIAS_HOST=""
ALIAS_KEY=""
ALIAS_PORT=""
while [ "$i" -lt "$COUNT" ]; do
    arg=$1; shift; i=$((i + 1))
    case "$arg" in
        -S*) echo 'sshk: -S is reserved for Tailscale transport' >&2; exit 2 ;;
        -[ciPoFl])
            [ "$i" -lt "$COUNT" ] || { echo "sshk: $arg needs a value" >&2; exit 2; }
            value=$1; shift; i=$((i + 1))
            case "$arg" in
                -i) value=$(sshk_map_identity "$value" "$BINDIR"); HAS_I=1 ;;
                -P) HAS_P=1 ;;
            esac
            set -- "$@" "$arg" "$value" ;;
        -i?*) set -- "$@" -i "$(sshk_map_identity "${arg#-i}" "$BINDIR")"; HAS_I=1 ;;
        -P?*) set -- "$@" "$arg"; HAS_P=1 ;;
        -*) set -- "$@" "$arg" ;;
        *)
            name=${arg%%:*}
            if sshk_lookup_alias "$CONF" "$name"; then
                case "$arg" in *:*) path=${arg#*:} ;; *) path="" ;; esac
                arg="$SSHK_ALIAS_HOST:$path"
                if [ -n "$ALIAS_PORT" ] && [ -n "$SSHK_ALIAS_PORT" ] && [ "$ALIAS_PORT" != "$SSHK_ALIAS_PORT" ]; then
                    echo 'sshk: remote aliases require different ports; copy via a local file' >&2; exit 2
                fi
                ALIAS_PORT=${SSHK_ALIAS_PORT:-$ALIAS_PORT}
                ALIAS_KEY=${SSHK_ALIAS_KEY:-$ALIAS_KEY}
            fi
            set -- "$@" "$arg" ;;
    esac
done
if [ "$HAS_P" -eq 0 ] && [ -n "$ALIAS_PORT" ]; then
    set -- -P "$ALIAS_PORT" "$@"
fi
if [ "$HAS_I" -eq 0 ]; then
    if [ -n "$ALIAS_KEY" ]; then
        set -- -i "$(sshk_identity_path "$BINDIR" "$ALIAS_KEY")" "$@"
    elif [ -f "$BINDIR/kindle_native_key" ]; then
        set -- -i "$BINDIR/kindle_native_key" "$@"
    fi
fi
exec "$SCP_BIN" scp -S "$SCP_SSH" "$@"
