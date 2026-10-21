#!/bin/sh
# uninstall.sh - Restores kterm PATH and removes the sshk known_hosts
# symlink (only if the symlink target is the sshk-managed directory).
#
# Refuses to run unless the user types "YES" at the prompt, or the script is
# invoked with --force. The KUAL menu wires this up via the "Setup & Maintenance >
# Uninstall sshk" item; the read is from /dev/tty so it works whether the
# script is run from a KUAL action (no stdin) or from a kterm prompt.

set -e
umask 077
ROOT_HOME="${SSHK_ROOT_HOME:-/root}"

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                " 2>/dev/null || true
    eips 0 0 "sshk: $1" 2>/dev/null || true
}

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force|-f|-y|--yes)
            FORCE=1
            ;;
        *)
            echo "sshk: unknown argument: $arg" >&2
            echo "Usage: uninstall.sh [--force]" >&2
            exit 2
            ;;
    esac
done

if [ "$FORCE" -ne 1 ]; then
    # Prefer /dev/tty so KUAL (which doesn't connect stdin) still works
    # when the user runs this from kterm directly. Fall back to stdin if
    # /dev/tty isn't available (e.g. piped from a non-interactive shell).
    if [ -r /dev/tty ]; then
        TTY=/dev/tty
    else
        TTY=/dev/stdin
    fi

    cat <<'BANNER' >&2

sshk: this removes the sshk PATH entry and restores managed SSH data to your home.
sshk: your SSH keys (kindle_*_key) on the USB drive are NOT removed.
sshk: to remove them too, delete extensions/sshk/bin/kindle_*_key manually.

BANNER

    printf 'Type YES to confirm uninstall: ' >&2
    if ! read -r reply < "$TTY"; then
        echo "sshk: could not read confirmation; aborting" >&2
        exit 1
    fi
    if [ "$reply" != "YES" ]; then
        echo "sshk: confirmation failed; aborting" >&2
        exit 1
    fi
fi

US_ROOT="${SSHK_US_ROOT:-/mnt/us}"
KTERM_SH="$US_ROOT/extensions/kterm/bin/kterm.sh"

eips_print "Uninstalling SSH from kterm..."

# Remove exactly our PATH line, preserving all subsequent user changes.
# Retain .orig as a manual recovery copy, never overwrite the live script with it.
if [ -f "$KTERM_SH" ]; then
    TMPF=$(mktemp "${KTERM_SH}.patch.XXXXXX")
    trap 'rm -f "$TMPF"' EXIT
    cp -p "$KTERM_SH" "$TMPF"
    awk '$0 != "export PATH=/mnt/us/extensions/sshk/bin:$PATH"' "$KTERM_SH" > "$TMPF"
    mv "$TMPF" "$KTERM_SH"
    trap - EXIT
fi

EXPECTED_TARGET="$US_ROOT/extensions/sshk/.ssh"
if [ -L "$ROOT_HOME/.ssh" ]; then
    ACTUAL_TARGET=$(readlink -f "$ROOT_HOME/.ssh" 2>/dev/null) || ACTUAL_TARGET=""
    EXPECTED_REAL=$(readlink -f "$EXPECTED_TARGET" 2>/dev/null) || EXPECTED_REAL="$EXPECTED_TARGET"
    if [ -n "$ACTUAL_TARGET" ] && [ "$ACTUAL_TARGET" = "$EXPECTED_REAL" ]; then
        REMOUNTED=0
        if [ "$ROOT_HOME" = /root ] && command -v mntroot >/dev/null 2>&1; then
            mntroot rw
            REMOUNTED=1
        fi
        # Copy first; a failed copy leaves the live symlink and USB data intact.
        STAGED=""
        trap '[ -z "$STAGED" ] || rm -rf "$STAGED"; [ "$REMOUNTED" -eq 0 ] || mntroot ro' EXIT
        STAGED=$(mktemp -d "$ROOT_HOME/.ssh-sshk-restore.XXXXXX")
        cp -Rp "$EXPECTED_TARGET/." "$STAGED/"
        # USB FAT permissions may be broad; the restored home must be private.
        chmod 700 "$STAGED"
        for FILE in authorized_keys known_hosts; do
            if [ -f "$STAGED/$FILE" ] && [ ! -L "$STAGED/$FILE" ]; then
                chmod 600 "$STAGED/$FILE"
            fi
        done
        rm "$ROOT_HOME/.ssh"
        if ! mv "$STAGED" "$ROOT_HOME/.ssh"; then
            ln -s "$EXPECTED_TARGET" "$ROOT_HOME/.ssh" || :
            echo "Error restoring SSH directory; USB data remains at $EXPECTED_TARGET" >&2
            exit 1
        fi
        STAGED=""
        if [ "$REMOUNTED" -eq 1 ]; then mntroot ro; fi
        trap - EXIT
    fi
fi

eips_print "Uninstall complete. SSH data and extension files retained."
