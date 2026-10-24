#!/bin/sh
# install.sh - 1-Tap Installer & Setup for sshk

set -e
umask 077
ROOT_HOME="${SSHK_ROOT_HOME:-/root}"

BINDIR="$(cd "$(dirname "$0")" && pwd)"
EXTDIR="$(cd "$BINDIR/.." && pwd)"
# USB root; overridable for simulation (tests/kindle-sim). Production default.
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"
KTERM_SH="$US_ROOT/extensions/kterm/bin/kterm.sh"
# Read VERSION defensively. If the file is missing (corrupted install, CI
# sandbox) we still want to print something useful instead of `v` followed by
# nothing. Strip whitespace so trailing newlines don't leak.
if [ -r "$EXTDIR/VERSION" ]; then
    VERSION=$(tr -d '[:space:]' < "$EXTDIR/VERSION")
else
    VERSION=""
fi
if [ -z "$VERSION" ]; then
    VERSION="unknown"
fi

eips_print_row() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                                                " 2>/dev/null || :
    eips 0 "$ROW" "$TEXT" 2>/dev/null || :
}

# Clear display screen for installation status
eips -c 2>/dev/null || :
eips_print_row 1 "========================================"
eips_print_row 2 "  sshk v$VERSION: 1-Tap Installation"
eips_print_row 3 "========================================"

echo "=== sshk v$VERSION: 1-Tap Installation ==="

# Step 1: Ensure all binaries & scripts are executable. The previous version
# was 19 separate `chmod +x` lines, half of which suppressed errors so a
# typo'd filename would slip through silently. One glob + case statement
# covers every shipping executable; missing files just don't match the glob.
# Specific names are listed first so a future `*.sh` suffix wouldn't shadow
# them. (The plain scripts we ship today all already carry `.sh` — this list
# catches the suffix-less wrappers `dbclient`, `dropbear`, `dropbearkey`,
# `dropbearmulti`, `scp`, `scp-tailscale`, `ssh`, `ssh-tailscale`, `sshk`,
# `ssh-menu`, `server-toggle.sh`, and `eips-refresh`.)
for f in "$BINDIR"/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    case "$name" in
        dbclient|dropbear|dropbearkey|dropbearmulti|scp|scp-tailscale|ssh|ssh-tailscale|sshk|ssh-menu|eips-refresh|server-toggle.sh|*.sh)
            chmod +x "$f"
            ;;
    esac
done

echo "[1/4] Permissions set."

# Step 2: Add only our PATH line; keep the original script and user edits.
if [ -f "$KTERM_SH" ]; then
    # shellcheck disable=SC2016
    if ! grep -Fqx 'export PATH=/mnt/us/extensions/sshk/bin:$PATH' "$KTERM_SH"; then
        [ -e "${KTERM_SH}.orig" ] || cp -p "$KTERM_SH" "${KTERM_SH}.orig"
        TMPF=$(mktemp "${KTERM_SH}.patch.XXXXXX")
        trap 'rm -f "$TMPF"' EXIT
        cp -p "$KTERM_SH" "$TMPF"
        awk 'NR == 1 {print; print "export PATH=/mnt/us/extensions/sshk/bin:$PATH"; next} {print}' "$KTERM_SH" > "$TMPF"
        mv "$TMPF" "$KTERM_SH"
        trap - EXIT
    fi
    echo "[2/4] kterm PATH configured."
else
    echo "[2/4] kterm not installed; install it to use the terminal."
fi

# Step 3: Never replace existing SSH configuration, including foreign symlinks.
SSH_DIR="$EXTDIR/.ssh"
mkdir -p "$SSH_DIR"
if [ -e "$ROOT_HOME/.ssh" ] || [ -L "$ROOT_HOME/.ssh" ]; then
    if [ ! -d "$ROOT_HOME/.ssh" ]; then
        echo "Error: $ROOT_HOME/.ssh is not a usable directory; preserved unchanged." >&2
        exit 1
    fi
    echo "[3/4] Existing SSH configuration preserved: $ROOT_HOME/.ssh"
else
    REMOUNTED=0
    if [ "$ROOT_HOME" = /root ] && command -v mntroot >/dev/null 2>&1; then
        mntroot rw
        REMOUNTED=1
    fi
    trap '[ "$REMOUNTED" -eq 0 ] || mntroot ro' EXIT
    ln -s "$SSH_DIR" "$ROOT_HOME/.ssh"
    if [ "$REMOUNTED" -eq 1 ]; then mntroot ro; fi
    trap - EXIT
    echo "[3/4] Persistent SSH storage enabled."
fi

# Activate staged inbound keys without replacing existing authorized keys.
if [ -f "$SSH_DIR/authorized_keys" ] && [ "$(readlink -f "$ROOT_HOME/.ssh")" != "$(readlink -f "$SSH_DIR")" ]; then
    REMOUNTED=0
    AUTH_TMP=""
    if [ "$ROOT_HOME" = /root ] && command -v mntroot >/dev/null 2>&1; then
        mntroot rw
        REMOUNTED=1
    fi
    trap '[ -z "$AUTH_TMP" ] || rm -f "$AUTH_TMP"; [ "$REMOUNTED" -eq 0 ] || mntroot ro' EXIT
    AUTH_TMP=$(mktemp "$ROOT_HOME/.ssh/.authorized_keys.XXXXXX")
    if [ -L "$ROOT_HOME/.ssh/authorized_keys" ]; then
        echo "Error: authorized_keys is a symlink; merge $SSH_DIR/authorized_keys manually." >&2
        exit 1
    fi
    if [ -f "$ROOT_HOME/.ssh/authorized_keys" ]; then
        awk '{print}' "$ROOT_HOME/.ssh/authorized_keys" > "$AUTH_TMP"
    fi
    while IFS= read -r KEY_LINE || [ -n "$KEY_LINE" ]; do
        [ -n "$KEY_LINE" ] || continue
        grep -Fqx -- "$KEY_LINE" "$AUTH_TMP" || printf '%s\n' "$KEY_LINE" >> "$AUTH_TMP"
    done < "$SSH_DIR/authorized_keys"
    chmod 600 "$AUTH_TMP"
    mv "$AUTH_TMP" "$ROOT_HOME/.ssh/authorized_keys"
    AUTH_TMP=""
    if [ "$REMOUNTED" -eq 1 ]; then mntroot ro; fi
    trap - EXIT
    echo "Staged inbound authorized keys merged; existing keys retained."
fi

# Step 4: Generate native SSH key if missing
KEY="$BINDIR/kindle_native_key"
if [ ! -f "$KEY" ]; then
    echo "[4/4] Generating ed25519 SSH key..."
    eips_print_row 7 "Generating ed25519 key..."
    KEY_STAGE=$(mktemp -d "$BINDIR/.keygen.XXXXXX")
    trap 'rm -rf "$KEY_STAGE"' EXIT
    "$BINDIR/dropbearkey" -t ed25519 -f "$KEY_STAGE/key"
    "$BINDIR/dropbearkey" -y -f "$KEY_STAGE/key" >/dev/null
    mv "$KEY_STAGE/key" "$KEY"
    rmdir "$KEY_STAGE"
    trap - EXIT
fi

# Export public key to USB root
if [ -f "$KEY" ]; then
    "$BINDIR/showkey.sh" "native" >/dev/null
    FINGERPRINT=$("$BINDIR/dropbearkey" -y -f "$KEY" 2>/dev/null | grep Fingerprint | awk '{print $2}')
    echo "[4/4] SSH key ready: $FINGERPRINT"
    eips_print_row 7 "[OK] SSH Key: $FINGERPRINT"
    eips_print_row 8 "[OK] Pubkey: /mnt/us/kindle_ssh_key.pub"
else
    eips_print_row 7 "[--] Failed to generate key"
    exit 1
fi

eips_print_row 10 "Ready! Open kterm and type: ssh"
eips_print_row 11 "========================================"

echo ""
echo "Installation complete!"
echo "  * Open kterm and type 'ssh' to open the quick-connect menu."
echo "  * Add a host in the menu with [a], or edit extensions/sshk/hosts.conf."
echo "  * Authorize a server from your computer: ./authorize-server.sh user@host"
