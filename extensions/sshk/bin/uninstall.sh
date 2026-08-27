#!/bin/sh
# uninstall.sh - Restores kterm PATH and removes the sshk known_hosts
# symlink (only if the symlink target is the sshk-managed directory).
#
# Refuses to run unless the user types "YES" at the prompt, or the script is
# invoked with --force. The KUAL menu wires this up via the "⚙️ More >
# 🗑️ Uninstall" item; the read is from /dev/tty so it works whether the
# script is run from a KUAL action (no stdin) or from a kterm prompt.

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

sshk: this will restore kterm.sh and remove the sshk known_hosts symlink.
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

# Restore from backup if possible
if [ -f "${KTERM_SH}.orig" ]; then
    mv "${KTERM_SH}.orig" "$KTERM_SH"
    eips_print "Restored kterm.sh from backup!"
else
    # Fallback to removing the PATH line manually
    if [ -f "$KTERM_SH" ]; then
        sed -i 's|export PATH=/mnt/us/extensions/sshk/bin:\$PATH||g' "$KTERM_SH"
        eips_print "Removed PATH entry from kterm.sh"
    else
        eips_print "kterm not found, nothing to do."
    fi
fi

# Remove the known_hosts symlink ONLY if it points at our sshk directory.
# Without this check we would happily clobber a symlink the user set up for
# some other purpose (e.g. an OpenSSH home on a developer Kindle).
EXPECTED_TARGET="$US_ROOT/extensions/sshk/.ssh"
if [ -L "/root/.ssh" ]; then
    ACTUAL_TARGET=$(readlink -f "/root/.ssh" 2>/dev/null) || ACTUAL_TARGET=""
    EXPECTED_REAL=$(readlink -f "$EXPECTED_TARGET" 2>/dev/null) || EXPECTED_REAL="$EXPECTED_TARGET"
    if [ -n "$ACTUAL_TARGET" ] && [ "$ACTUAL_TARGET" = "$EXPECTED_REAL" ]; then
        if command -v mntroot >/dev/null 2>&1; then
            mntroot rw 2>/dev/null
            rm -f /root/.ssh
            mkdir -p /root/.ssh
            mntroot ro 2>/dev/null
        fi
    fi
fi

eips_print "Uninstall complete."
