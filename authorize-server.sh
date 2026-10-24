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
            [ "$#" -ge 2 ] || { echo "Missing port after -p" >&2; exit 2; }
            PORT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

case "$TARGET" in -*) echo "Invalid target" >&2; exit 2 ;; esac
case "$PORT" in ''|*[!0-9]*) echo "Invalid port" >&2; exit 2 ;; esac
if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Invalid port" >&2; exit 2
fi

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
            TEMP_PUB=$(mktemp "${TMPDIR:-/tmp}/sshk-public.XXXXXX")
            trap 'rm -f "$TEMP_PUB"' EXIT HUP INT TERM
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
        echo "${RED}File '$user_key_path' not found. In KUAL > sshk, use SSH Keys > Create Default Key, then Export Default Public Key.${NC}" >&2
        exit 1
    fi
fi

PUBKEY_CONTENT=$(tr -d '\r' < "$PUBKEY_FILE")
if ! printf '%s\n' "$PUBKEY_CONTENT" | awk 'NF { n++; if ($1 !~ /^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))$/ || $2 !~ /^[A-Za-z0-9+\/=]+$/) bad=1 } END { exit (n != 1 || bad) }'; then
    echo "Expected one OpenSSH public key (.pub)." >&2
    exit 1
fi
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
printf '%s\n' "$PUBKEY_CONTENT" | ssh -p "$PORT" "$TARGET" '
set -e
umask 077
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
KEY=$(tr -d "\r")
[ -n "$KEY" ] || exit 1
if ! grep -qxF "$KEY" ~/.ssh/authorized_keys 2>/dev/null; then
    printf "\n%s\n" "$KEY" >> ~/.ssh/authorized_keys
fi
'

echo ""
echo "${BOLD}${GREEN}====================================================${NC}"
echo "${BOLD}${GREEN}   🎉 Success! Server Authorized!                   ${NC}"
echo "${BOLD}${GREEN}====================================================${NC}"
echo "Your Kindle can now connect to ${BOLD}$TARGET${NC} without a password!"
echo "Open kterm on your Kindle and run:"
echo "     ${BLUE}ssh -p $PORT $TARGET${NC}"
echo ""

echo "To authorize this computer to access the Kindle instead, use:"
echo "  ./authorize-kindle.sh /path/to/Kindle [computer-key.pub]"
