#!/bin/sh
# genkey.sh - Generates ed25519 Dropbear SSH key on Kindle

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

BINDIR="$(cd "$(dirname "$0")" && pwd)"
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"
KEYNAME="${1:-native}"
KEY="$BINDIR/kindle_${KEYNAME}_key"

if [ -f "$KEY" ]; then
    eips_print "Key '$KEYNAME' already exists!"
    exit 0
fi

eips_print "Generating ed25519 key '$KEYNAME'..."
# Run dropbearkey to generate the key
if "$BINDIR/dropbearkey" -t ed25519 -f "$KEY" > /tmp/genkey.out 2>&1; then
    # Key generated successfully
    eips_print "Key generated! Saving public key..."
    # Call showkey to output the public key to /mnt/us/
    "$BINDIR/showkey.sh" "$KEYNAME"
else
    eips_print "Failed to generate key! Check log."
    cat /tmp/genkey.out > "$US_ROOT/sshk_error.log"
fi
