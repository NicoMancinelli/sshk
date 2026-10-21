#!/bin/sh
# kterm-landscape.sh - Launches kterm in Landscape mode with ssh-menu

case "$0" in
    */*) BINDIR="${0%/*}" ;;
    *) BINDIR="." ;;
esac
BINDIR="$(cd "$BINDIR" && pwd)"
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"

KTERM_DIR="$US_ROOT/extensions/kterm"
KTERM_BIN="$KTERM_DIR/bin/kterm"
SSHMENU="$BINDIR/ssh-menu"

# Export environment so subshells and terminal curses/vte apps function properly
export PATH="$BINDIR:$PATH"
export TERM="${TERM:-xterm}"
if [ -d "$KTERM_DIR/vte/terminfo" ]; then
    export TERMINFO="$KTERM_DIR/vte/terminfo"
fi

# Detect Kindle display DPI for proper on-screen keyboard sizing
PARAM=""
if [ -f /var/log/Xorg.0.log ]; then
    DPI=$(grep DPI /var/log/Xorg.0.log 2>/dev/null | sed -n 's/.*(\([0-9]\+\), [0-9]\+).*/\1/p')
    if [ -n "$DPI" ] && [ "$DPI" -gt 290 ] 2>/dev/null && [ -f "$KTERM_DIR/layouts/keyboard-300dpi.xml" ]; then
        PARAM="-l $KTERM_DIR/layouts/keyboard-300dpi.xml"
    elif [ -n "$DPI" ] && [ "$DPI" -gt 200 ] 2>/dev/null && [ -f "$KTERM_DIR/layouts/keyboard-200dpi.xml" ]; then
        PARAM="-l $KTERM_DIR/layouts/keyboard-200dpi.xml"
    fi
fi

if [ -x "$KTERM_BIN" ]; then
    # -o R: Landscape orientation, -s 8: Readable font, -e: Auto-run ssh-menu
    exec "$KTERM_BIN" $PARAM -o R -s 8 -e "$SSHMENU"
else
    # Fallback to running kterm.sh if kterm binary direct path differs
    KTERM_SH="$KTERM_DIR/bin/kterm.sh"
    if [ -x "$KTERM_SH" ]; then
        echo "Using kterm launcher; type ssh to connect."
        exec "$KTERM_SH" -o R -s 8 -e "$SSHMENU"
    else
        echo "sshk: kterm not found. Install it in $US_ROOT/extensions/kterm." >&2
        eips 0 0 "kterm missing: install extensions/kterm" 2>/dev/null || :
        exit 1
    fi
fi
