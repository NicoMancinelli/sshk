#!/bin/sh
# install.sh - 1-Tap Installer & Setup for sshk

BINDIR="$(cd "$(dirname "$0")" && pwd)"
EXTDIR="$(cd "$BINDIR/.." && pwd)"
KTERM_SH="/mnt/us/extensions/kterm/bin/kterm.sh"
VERSION=$(cat "$EXTDIR/VERSION" 2>/dev/null || echo "1.1.1")

eips_print_row() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                                                "
    eips 0 "$ROW" "$TEXT"
}

# Clear display screen for installation status
eips -c 2>/dev/null
eips_print_row 1 "========================================"
eips_print_row 2 "  sshk v$VERSION: 1-Tap Installation"
eips_print_row 3 "========================================"

echo "=== sshk v$VERSION: 1-Tap Installation ==="

# Step 1: Ensure all binaries & scripts are executable
chmod +x "$BINDIR/dropbearmulti"
chmod +x "$BINDIR/dbclient"
chmod +x "$BINDIR/dropbearkey"
chmod +x "$BINDIR/dropbear" 2>/dev/null
chmod +x "$BINDIR/ssh"
chmod +x "$BINDIR/sshk" 2>/dev/null
chmod +x "$BINDIR/ssh-tailscale"
chmod +x "$BINDIR/ssh-menu" 2>/dev/null
chmod +x "$BINDIR/scp" 2>/dev/null
chmod +x "$BINDIR/scp-tailscale" 2>/dev/null
chmod +x "$BINDIR/server-start.sh" 2>/dev/null
chmod +x "$BINDIR/server-stop.sh" 2>/dev/null
chmod +x "$BINDIR/kterm-landscape.sh" 2>/dev/null
chmod +x "$BINDIR/install.sh"
chmod +x "$BINDIR/uninstall.sh"
chmod +x "$BINDIR/genkey.sh"
chmod +x "$BINDIR/showkey.sh"
chmod +x "$BINDIR/listkeys.sh" 2>/dev/null
chmod +x "$BINDIR/version.sh" 2>/dev/null
chmod +x "$BINDIR/eips-refresh" 2>/dev/null

echo "[1/4] Permissions set."

# Step 2: Configure kterm PATH
if [ -f "$KTERM_SH" ]; then
    if [ ! -f "${KTERM_SH}.orig" ]; then
        cp "$KTERM_SH" "${KTERM_SH}.orig"
    fi
    if ! grep -q "extensions/sshk/bin" "$KTERM_SH"; then
        # Prepend a PATH export below the shebang without depending on the
        # first line's exact contents; write through the same file so the
        # exec bit and ownership survive.
        TMPF="${KTERM_SH}.patch.$$"
        {
            echo '#!/bin/sh'
            echo 'export PATH=/mnt/us/extensions/sshk/bin:$PATH'
            tail -n +2 "$KTERM_SH"
        } > "$TMPF"
        cat "$TMPF" > "$KTERM_SH"
        rm -f "$TMPF"
    fi
    # Verify the patch actually landed — never claim success on a silent no-op
    if grep -q "export PATH=/mnt/us/extensions/sshk/bin" "$KTERM_SH"; then
        echo "[2/4] kterm PATH configured."
        eips_print_row 5 "[OK] kterm PATH configured"
    else
        echo "[2/4] WARNING: could not patch $KTERM_SH automatically."
        echo "       Add this line to it manually: export PATH=/mnt/us/extensions/sshk/bin:\$PATH"
        eips_print_row 5 "[!!] kterm patch failed (see log)"
    fi
else
    echo "[2/4] Note: kterm not yet installed."
    eips_print_row 5 "[--] kterm not found (install kterm)"
fi

# Step 3: Configure persistent known_hosts
SSH_DIR="/mnt/us/extensions/sshk/.ssh"
mkdir -p "$SSH_DIR"
if [ ! -L "/root/.ssh" ]; then
    if command -v mntroot >/dev/null 2>&1; then
        mntroot rw 2>/dev/null
        if [ -d "/root/.ssh" ]; then
            cp -a /root/.ssh/* "$SSH_DIR/" 2>/dev/null
            rm -rf /root/.ssh
        fi
        ln -sf "$SSH_DIR" /root/.ssh
        mntroot ro 2>/dev/null
        echo "[3/4] Known hosts storage enabled."
        eips_print_row 6 "[OK] Known hosts enabled"
    else
        echo "[3/4] Note: mntroot not found (auto-accept active)."
        eips_print_row 6 "[OK] Auto-accept fallback active"
    fi
else
    eips_print_row 6 "[OK] Known hosts already active"
fi

# Step 4: Generate native SSH key if missing
KEY="$BINDIR/kindle_native_key"
if [ ! -f "$KEY" ]; then
    echo "[4/4] Generating ed25519 SSH key..."
    eips_print_row 7 "Generating ed25519 key..."
    "$BINDIR/dropbearkey" -t ed25519 -f "$KEY" > /tmp/genkey.out 2>&1
fi

# Export public key to USB root
if [ -f "$KEY" ]; then
    "$BINDIR/showkey.sh" "native" >/dev/null 2>&1
    FINGERPRINT=$("$BINDIR/dropbearkey" -y -f "$KEY" 2>/dev/null | grep Fingerprint | awk '{print $2}')
    echo "[4/4] SSH key ready: $FINGERPRINT"
    eips_print_row 7 "[OK] SSH Key: $FINGERPRINT"
    eips_print_row 8 "[OK] Pubkey: /mnt/us/kindle_ssh_key.pub"
else
    eips_print_row 7 "[--] Failed to generate key"
fi

eips_print_row 10 "Ready! Open kterm & type: ssh user@host"
eips_print_row 11 "========================================"

echo ""
echo "Installation complete! You can now open kterm and run 'ssh user@host'."
