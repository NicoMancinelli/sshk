#!/bin/sh
# uninstall.sh - Restores kterm PATH

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

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
