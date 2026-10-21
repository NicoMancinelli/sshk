#!/bin/sh
# Authorize a computer's PUBLIC key on a USB-mounted Kindle.
set -eu
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 KINDLE_MOUNT [COMPUTER_PUBLIC_KEY.pub]" >&2
    exit 2
fi
MOUNT=$1
KEY=${2:-"$HOME/.ssh/id_ed25519.pub"}
if [ ! -d "$MOUNT/extensions/sshk" ]; then
    echo "No sshk installation at $MOUNT/extensions/sshk" >&2
    exit 1
fi
if [ ! -f "$KEY" ]; then
    echo "Public key not found: $KEY" >&2
    echo "Create one with ssh-keygen, or supply your .pub file as the second argument." >&2
    exit 1
fi
# Accept one plain OpenSSH public-key record, never a private key or options.
DATA=$(tr -d '\r' < "$KEY")
if ! printf '%s\n' "$DATA" | awk 'NF { n++; if ($1 !~ /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))$/ || $2 !~ /^[A-Za-z0-9+\/=]+$/) bad=1 } END { exit (n != 1 || bad) }'; then
    echo "Expected one OpenSSH public key (.pub), without authorized_keys options." >&2
    exit 1
fi
DIR="$MOUNT/extensions/sshk/.ssh"
mkdir -p "$DIR"
touch "$DIR/authorized_keys"
# Compare key type and payload so changing a comment does not duplicate a key.
if awk 'NR==FNR { type=$1; key=$2; next } $1==type && $2==key { found=1 } END { exit !found }' "$KEY" "$DIR/authorized_keys"; then
    echo "Computer key already authorized."
else
    # A leading newline also handles a pre-existing file without a final newline.
    printf '\n%s\n' "$DATA" >> "$DIR/authorized_keys"
    echo "Computer public key authorized on Kindle."
fi
echo "Eject USB, run KUAL > sshk > Setup & Maintenance > Install / Repair once."
echo "Then SSH Server > Start Server; Server Status shows the address."
