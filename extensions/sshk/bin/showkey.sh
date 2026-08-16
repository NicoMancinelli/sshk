#!/bin/sh
# showkey.sh - Extracts and saves public key to user storage root

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

BINDIR="$(cd "$(dirname "$0")" && pwd)"
KEY="$BINDIR/kindle_native_key"
PUBKEY_OUT="/mnt/us/kindle_ssh_key.pub"

if [ ! -f "$KEY" ]; then
    eips_print "Error: No key found. Run Generate Key first."
    exit 1
fi

# Extract public key line starting with ssh-ed25519
# dropbearkey -y output format contains fingerprint on first line,
# public key on second line, and fingerprint on third line.
# We can filter the output using grep
"$BINDIR/dropbearkey" -y -f "$KEY" | grep "^ssh-" > "$PUBKEY_OUT"

if [ $? -eq 0 ]; then
    eips_print "Saved public key to /mnt/us/kindle_ssh_key.pub!"
else
    eips_print "Failed to extract public key!"
fi
