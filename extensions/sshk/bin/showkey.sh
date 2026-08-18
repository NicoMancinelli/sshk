#!/bin/sh
# showkey.sh - Extracts and saves public key to user storage root

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

BINDIR="$(cd "$(dirname "$0")" && pwd)"
KEYNAME="${1:-native}"
KEY="$BINDIR/kindle_${KEYNAME}_key"

if [ "$KEYNAME" = "native" ]; then
    PUBKEY_OUT="/mnt/us/kindle_ssh_key.pub"
else
    PUBKEY_OUT="/mnt/us/kindle_${KEYNAME}_ssh_key.pub"
fi

if [ ! -f "$KEY" ]; then
    eips_print "Error: No key '$KEYNAME' found."
    exit 1
fi

# Extract public key line starting with ssh-ed25519
"$BINDIR/dropbearkey" -y -f "$KEY" | grep "^ssh-" > "$PUBKEY_OUT"

if [ $? -eq 0 ]; then
    FINGERPRINT=$("$BINDIR/dropbearkey" -y -f "$KEY" | grep Fingerprint | awk '{print $2}')
    eips_print "Saved: $FINGERPRINT"
    cat "$PUBKEY_OUT"
else
    eips_print "Failed to extract public key!"
fi
