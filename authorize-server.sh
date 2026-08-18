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
            # Found private key file on Kindle
            TEMP_PUB="/tmp/kindle_temp_key.pub"
            # If dropbearkey or ssh-keygen can extract it, or if it already exists
            PUBKEY_FILE="$path"
            break
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

# Upload key using SSH
ssh -p "$PORT" "$TARGET" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$PUBKEY_CONTENT' ~/.ssh/authorized_keys || echo '$PUBKEY_CONTENT' >> ~/.ssh/authorized_keys"

echo ""
echo "${BOLD}${GREEN}====================================================${NC}"
echo "${BOLD}${GREEN}   🎉 Success! Server Authorized!                   ${NC}"
echo "${BOLD}${GREEN}====================================================${NC}"
echo "Your Kindle can now connect to ${BOLD}$TARGET${NC} without a password!"
echo "Open kterm on your Kindle and run:"
echo "     ${BLUE}ssh $TARGET${NC}"
echo ""
