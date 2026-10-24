#!/bin/sh
# Small e-ink status pages. Full output always remains available in kterm.
sshk_ui_begin() {
    SSHK_UI_ROW=1
    eips -c 2>/dev/null || :
    sshk_ui_line "$1"
    SSHK_UI_ROW=3
}

sshk_ui_line() {
    printf '%s\n' "$1"
    # Bound output to a conservative 48 columns and 22 rows. Never wrap a
    # long fingerprint or address into adjacent UI text on a small Kindle.
    _ui_count=$(printf '%s\n' "$1" | fold -w 48 | wc -l | tr -d ' ')
    _ui_row=$SSHK_UI_ROW
    while IFS= read -r _ui_line; do
        if [ "$_ui_row" -lt 22 ]; then
            eips 0 "$_ui_row" "                                                " 2>/dev/null || :
            eips 0 "$_ui_row" "$_ui_line" 2>/dev/null || :
        elif [ "$_ui_row" -eq 22 ]; then
            eips 0 22 "More details available in kterm.                 " 2>/dev/null || :
        fi
        _ui_row=$((_ui_row + 1))
    done <<EOF_UI
$(printf '%s\n' "$1" | fold -w 48)
EOF_UI
    SSHK_UI_ROW=$((SSHK_UI_ROW + _ui_count))
}
