#!/bin/sh
# install.sh - Installs SSH client into kterm

# Instant visual feedback on Kindle screen
eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

BINDIR="$(cd "$(dirname "$0")" && pwd)"
KTERM_SH="/mnt/us/extensions/kterm/bin/kterm.sh"

eips_print "Installing SSH into kterm..."

# Check if kterm is installed
if [ ! -f "$KTERM_SH" ]; then
    eips_print "Error: kterm not found at /mnt/us/extensions/kterm"
    exit 1
fi

# Ensure our wrapper scripts are executable
chmod +x "$BINDIR/dropbearmulti"
chmod +x "$BINDIR/dbclient"
chmod +x "$BINDIR/dropbearkey"
chmod +x "$BINDIR/ssh"
chmod +x "$BINDIR/ssh-tailscale"
chmod +x "$BINDIR/install.sh"
chmod +x "$BINDIR/uninstall.sh"
chmod +x "$BINDIR/genkey.sh"
chmod +x "$BINDIR/showkey.sh"

# Backup original kterm.sh if not done yet
if [ ! -f "${KTERM_SH}.orig" ]; then
    cp "$KTERM_SH" "${KTERM_SH}.orig"
fi

# Patch kterm.sh PATH if not already patched
if grep -q "extensions/sshk/bin" "$KTERM_SH"; then
    eips_print "PATH already added in kterm.sh"
else
    # Insert PATH export right after the shebang
    sed -i 's|#!/bin/sh|#!/bin/sh\nexport PATH=/mnt/us/extensions/sshk/bin:$PATH|' "$KTERM_SH"
    eips_print "Success! PATH added to kterm.sh"
fi

# Also generate an SSH key if it doesn't exist yet
if [ ! -f "$BINDIR/kindle_native_key" ]; then
    eips_print "Generating native SSH key..."
    "$BINDIR/genkey.sh"
else
    eips_print "Installation complete!"
fi
