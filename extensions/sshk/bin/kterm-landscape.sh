#!/bin/sh
# kterm-landscape.sh - Launches kterm in Landscape mode with ssh-menu

KTERM_BIN="/mnt/us/extensions/kterm/bin/kterm"
SSHMENU="/mnt/us/extensions/sshk/bin/ssh-menu"

if [ -f "$KTERM_BIN" ]; then
    # -o R: Landscape orientation, -s 8: Readable font, -e: Auto-run ssh-menu
    exec "$KTERM_BIN" -o R -s 8 -e "$SSHMENU"
else
    # Fallback to running kterm.sh if kterm binary direct path differs
    KTERM_SH="/mnt/us/extensions/kterm/bin/kterm.sh"
    if [ -f "$KTERM_SH" ]; then
        exec "$KTERM_SH"
    else
        eips 0 0 "Error: kterm not found at /mnt/us/extensions/kterm"
        exit 1
    fi
fi
