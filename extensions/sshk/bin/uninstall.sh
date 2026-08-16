#!/bin/sh
# uninstall.sh - Restores kterm PATH

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

KTERM_SH="/mnt/us/extensions/kterm/bin/kterm.sh"

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
