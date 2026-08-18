#!/bin/sh
# install-to-kindle.sh - 1-Click Desktop Installer for sshk (macOS & Linux)
# Automatically detects connected Kindle USB drive and installs sshk

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_SOURCE="$SCRIPT_DIR/extensions/sshk"

echo ""
echo "${BOLD}${BLUE}====================================================${NC}"
echo "${BOLD}${BLUE}   sshk: Kindle SSH Client - 1-Click Installer      ${NC}"
echo "${BOLD}${BLUE}====================================================${NC}"
echo ""

if [ ! -d "$EXT_SOURCE" ]; then
    echo "${RED}Error: extensions/sshk directory not found in $SCRIPT_DIR${NC}" >&2
    exit 1
fi

# Step 1: Detect Kindle mount point
KINDLE_PATH=""

# Check macOS mounts
if [ -d "/Volumes/Kindle" ]; then
    KINDLE_PATH="/Volumes/Kindle"
fi

# Check common Linux mounts
if [ -z "$KINDLE_PATH" ]; then
    for path in \
        "/media/$USER/Kindle" \
        "/run/media/$USER/Kindle" \
        "/media/Kindle" \
        "/mnt/Kindle" \
        "/Volumes/Kindle"*; do
        if [ -d "$path" ] && { [ -d "$path/documents" ] || [ -d "$path/system" ] || [ -d "$path/extensions" ]; }; then
            KINDLE_PATH="$path"
            break
        fi
    done
fi

# If still not found, ask user
if [ -z "$KINDLE_PATH" ]; then
    echo "${YELLOW}Kindle not automatically detected.${NC}"
    echo "Please connect your Kindle via USB and ensure USB drive mode is active."
    echo ""
    printf "Enter your Kindle mount path (e.g. /Volumes/Kindle or /media/user/Kindle): "
    read -r user_input_path
    if [ -d "$user_input_path" ]; then
        KINDLE_PATH="$user_input_path"
    else
        echo "${RED}Directory '$user_input_path' does not exist. Aborting.${NC}" >&2
        exit 1
    fi
fi

echo "${GREEN}✓ Found Kindle at:${NC} $KINDLE_PATH"
echo ""

# Step 2: Copy extensions/sshk
TARGET_DIR="$KINDLE_PATH/extensions/sshk"
echo "${BLUE}Installing sshk extension to Kindle...${NC}"
mkdir -p "$KINDLE_PATH/extensions"
mkdir -p "$TARGET_DIR"

# Copy files while preserving existing user keys and config if present
if [ -f "$TARGET_DIR/hosts.conf" ]; then
    cp -r "$EXT_SOURCE"/* "$TARGET_DIR/" 2>/dev/null || true
    # Don't overwrite existing hosts.conf
else
    cp -r "$EXT_SOURCE"/* "$TARGET_DIR/"
fi

echo "${GREEN}✓ Copied sshk to $TARGET_DIR${NC}"

# Step 3: Check and auto-patch kterm if present
KTERM_SH="$KINDLE_PATH/extensions/kterm/bin/kterm.sh"
if [ -f "$KTERM_SH" ]; then
    if grep -q "extensions/sshk/bin" "$KTERM_SH"; then
        echo "${GREEN}✓ kterm PATH is already configured for sshk${NC}"
    else
        echo "${BLUE}Pre-configuring kterm PATH...${NC}"
        if [ ! -f "${KTERM_SH}.orig" ]; then
            cp "$KTERM_SH" "${KTERM_SH}.orig"
        fi
        sed -i '' 's|#!/bin/sh|#!/bin/sh\nexport PATH=/mnt/us/extensions/sshk/bin:$PATH|' "$KTERM_SH" 2>/dev/null || \
        sed -i 's|#!/bin/sh|#!/bin/sh\nexport PATH=/mnt/us/extensions/sshk/bin:$PATH|' "$KTERM_SH"
        echo "${GREEN}✓ Pre-patched kterm.sh PATH${NC}"
    fi
else
    echo "${YELLOW}ℹ Note: kterm not found at extensions/kterm.${NC}"
    echo "  Remember to install kterm on your Kindle for terminal access."
fi

# Step 4: Summary and instructions
echo ""
echo "${BOLD}${GREEN}====================================================${NC}"
echo "${BOLD}${GREEN}   🎉 Installation Complete! Next Steps:             ${NC}"
echo "${BOLD}${GREEN}====================================================${NC}"
echo ""
echo "1. ${BOLD}Safely eject${NC} your Kindle from your computer."
echo "2. Open ${BOLD}KUAL${NC} on your Kindle -> tap ${BOLD}sshk: SSH Client${NC} -> ${BOLD}1-Tap Setup${NC}."
echo "3. Open ${BOLD}kterm${NC} and start using SSH:"
echo "     ${BLUE}ssh user@host${NC}"
echo "     ${BLUE}ssh-tailscale user@host${NC}"
echo ""
echo "Tip: To easily authorize your server with your Kindle's SSH key, run:"
echo "     ${BOLD}./authorize-server.sh user@your-server-ip${NC}"
echo ""
