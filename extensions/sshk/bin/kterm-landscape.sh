#!/bin/sh
# kterm-landscape.sh - Launches kterm in Landscape mode with ssh-menu

BINDIR="$(cd "$(dirname "$0")" && pwd)"
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"

KTERM_BIN="$US_ROOT/extensions/kterm/bin/kterm"
SSHMENU="$BINDIR/ssh-menu"

if [ -x "$KTERM_BIN" ]; then
    # -o R: Landscape orientation, -s 8: Readable font, -e: Auto-run ssh-menu
    exec "$KTERM_BIN" -o R -s 8 -e "$SSHMENU"
else
    # Fallback to running kterm.sh if kterm binary direct path differs
    KTERM_SH="$US_ROOT/extensions/kterm/bin/kterm.sh"
    if [ -x "$KTERM_SH" ]; then
        echo "Using kterm launcher; type ssh to connect."
        exec "$KTERM_SH"
    else
        echo "sshk: kterm not found. Install it in $US_ROOT/extensions/kterm." >&2
        eips 0 0 "kterm missing: install extensions/kterm" 2>/dev/null || :
        exit 1
    fi
fi
