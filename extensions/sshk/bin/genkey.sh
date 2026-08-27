#!/bin/sh
# genkey.sh - Generates ed25519 Dropbear SSH key on Kindle

set -e

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

BINDIR="$(cd "$(dirname "$0")" && pwd)"
KEYNAME="${1:-native}"
KEY="$BINDIR/kindle_${KEYNAME}_key"

if [ -f "$KEY" ]; then
    eips_print "Key '$KEYNAME' already exists!"
    exit 0
fi

eips_print "Generating ed25519 key '$KEYNAME'..."

# Capture stderr to a temp file and only surface it if dropbearkey fails.
# The previous version wrote the error log into $US_ROOT/sshk_error.log on
# failure, which only worked on Kindle (where /mnt/us exists); elsewhere
# `cat > /mnt/us/sshk_error.log` would silently fail.
ERR_TMP=$(mktemp "${TMPDIR:-/tmp}/sshk-genkey.XXXXXX")
trap 'rm -f "$ERR_TMP"' EXIT INT TERM HUP

if "$BINDIR/dropbearkey" -t ed25519 -f "$KEY" > /dev/null 2> "$ERR_TMP"; then
    eips_print "Key generated! Saving public key..."
    "$BINDIR/showkey.sh" "$KEYNAME"
else
    eips_print "Failed to generate key!"
    cat "$ERR_TMP" >&2
    exit 1
fi
