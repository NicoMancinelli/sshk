#!/bin/sh
# KUAL has no input stream: open a terminal for the YES confirmation.
BINDIR="$(cd "$(dirname "$0")" && pwd)"
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"
KTERM="$US_ROOT/extensions/kterm/bin/kterm"
if [ -x "$KTERM" ]; then
    exec "$KTERM" -o R -s 8 -e "$BINDIR/uninstall.sh"
fi
# shellcheck disable=SC1091
. "$BINDIR/ui-common.sh"
sshk_ui_begin "sshk: Uninstall"
sshk_ui_line "kterm binary not found. Nothing was changed."
sshk_ui_line "In an available terminal, run:"
sshk_ui_line "$BINDIR/uninstall.sh"
exit 1
