#!/bin/sh
# authorize-server.sh - Automatically adds Kindle's SSH public key to your remote server
# Usage: ./authorize-server.sh user@host [-p port]

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo "Usage: ./authorize-server.sh user@host [-p port]"
    echo "Example: ./authorize-server.sh pi@raspberrypi.local"
    exit 1
fi

TARGET="$1"
shift
PORT="22"

while [ $# -gt 0 ]; do
    case "$1" in
        -p)
            PORT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "${BOLD}${BLUE}====================================================${NC}"
echo "${BOLD}${BLUE}   sshk: Authorize Server with Kindle SSH Key       ${NC}"
echo "${BOLD}${BLUE}====================================================${NC}"
echo ""

# Locate public key
PUBKEY_FILE=""

# Check mounted Kindle paths
for path in \
    "/Volumes/Kindle/kindle_ssh_key.pub" \
    "/Volumes/Kindle"*/kindle_ssh_key.pub \
    "/media/$USER/Kindle/kindle_ssh_key.pub" \
    "/run/media/$USER/Kindle/kindle_ssh_key.pub" \
    "./kindle_ssh_key.pub"; do
    if [ -f "$path" ]; then
        PUBKEY_FILE="$path"
        break
    fi
done

# If pubkey file not on USB root, check if we can read it from extensions/sshk/
if [ -z "$PUBKEY_FILE" ]; then
    for path in \
        "/Volumes/Kindle/extensions/sshk/bin/kindle_native_key" \
        "./extensions/sshk/bin/kindle_native_key"; do
        if [ -f "$path" ]; then
            # Found the private key file; extract its PUBLIC half locally
            # (never upload or install private key material on a server)
            TEMP_PUB="/tmp/kindle_temp_key.pub"
            if command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -y -f "$path" > "$TEMP_PUB" 2>/dev/null; then
                PUBKEY_FILE="$TEMP_PUB"
                break
            fi
        fi
    done
fi

if [ -z "$PUBKEY_FILE" ]; then
    echo "${YELLOW}Could not automatically find 'kindle_ssh_key.pub'.${NC}"
    printf "Enter the path to your Kindle's public key file: "
    read -r user_key_path
    if [ -f "$user_key_path" ]; then
        PUBKEY_FILE="$user_key_path"
    else
        echo "${RED}File '$user_key_path' not found. Make sure you tapped 'Generate SSH Key' or '1-Tap Setup' in KUAL.${NC}" >&2
        exit 1
    fi
fi

PUBKEY_CONTENT=$(cat "$PUBKEY_FILE")
echo "${GREEN}✓ Found Kindle Public Key:${NC}"
echo "  $PUBKEY_CONTENT"
echo ""
echo "${BLUE}Connecting to $TARGET (port $PORT) to install public key...${NC}"

# Upload the key via SSH, piping it through stdin so the key text is NEVER
# interpolated into the remote command line. This prevents a malicious or
# corrupted key file (or any environment that re-encodes the key text) from
# injecting shell metacharacters into the remote shell.
#
# The remote side: ensure ~/.ssh exists, ensure authorized_keys is in place,
# strip a CR character that some Dropbear builds append to the key line, then
# append the key (or no-op if it's already present).
ssh -p "$PORT" "$TARGET" <<'REMOTE'
set -e
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
# Strip a trailing CR so this works on hosts that send CRLF on the wire.
tr -d '\r' > ~/.ssh/sshk_pending_key.pub
KEY=$(cat ~/.ssh/sshk_pending_key.pub)
if ! grep -qxF "$KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    printf '%s\n' "$KEY" >> ~/.ssh/authorized_keys
fi
rm -f ~/.ssh/sshk_pending_key.pub
REMOTE

echo ""
echo "${BOLD}${GREEN}====================================================${NC}"
echo "${BOLD}${GREEN}   🎉 Success! Server Authorized!                   ${NC}"
echo "${BOLD}${GREEN}====================================================${NC}"
echo "Your Kindle can now connect to ${BOLD}$TARGET${NC} without a password!"
echo "Open kterm on your Kindle and run:"
echo "     ${BLUE}ssh $TARGET${NC}"
echo ""

# Optional: Inbound authorization (authorize this PC to SSH into Kindle)
LOCAL_PUBKEY=""
for key in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
    if [ -f "$key" ]; then
        LOCAL_PUBKEY="$key"
        break
    fi
done

KINDLE_SSH_DIR=""
for kdir in "/Volumes/Kindle/extensions/sshk/.ssh" "/media/$USER/Kindle/extensions/sshk/.ssh" "./extensions/sshk/.ssh"; do
    if [ -d "$kdir" ]; then
        KINDLE_SSH_DIR="$kdir"
        break
    fi
done

if [ -n "$LOCAL_PUBKEY" ] && [ -n "$KINDLE_SSH_DIR" ]; then
    mkdir -p "$KINDLE_SSH_DIR"
    touch "$KINDLE_SSH_DIR/authorized_keys"
    PC_KEY_DATA=$(cat "$LOCAL_PUBKEY")
    if ! grep -qxF "$PC_KEY_DATA" "$KINDLE_SSH_DIR/authorized_keys" 2>/dev/null; then
        echo "$PC_KEY_DATA" >> "$KINDLE_SSH_DIR/authorized_keys"
        echo "${GREEN}✓ Also authorized this computer to SSH *into* your Kindle (Port 2222)!${NC}"
        echo "  When you start the SSH Server in KUAL, you can connect with:"
        echo "  ${BLUE}ssh root@<kindle-ip> -p 2222${NC}"
        echo ""
    fi
fi
