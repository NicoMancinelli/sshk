#!/bin/sh
# showkey.sh - Extracts and saves public key to user storage root.
#
# dropbearkey -y prints both the public key line and a fingerprint line on
# stdout. We capture stdout to a temp file so the public key extraction and
# the fingerprint lookup both operate on the same content, and so any error
# message on stderr is preserved (the previous version had no stderr
# redirection, so a failed key extraction would print scary-looking dropbear
# internals on the user's terminal while the script still reported success).

set -e

eips_print() {
    echo "sshk: $1"
    eips 0 0 "                                                                                "
    eips 0 0 "sshk: $1"
}

BINDIR="$(cd "$(dirname "$0")" && pwd)"
US_ROOT="${SSHK_US_ROOT:-/mnt/us}"
KEYNAME="${1:-native}"
KEY="$BINDIR/kindle_${KEYNAME}_key"

if [ "$KEYNAME" = "native" ]; then
    PUBKEY_OUT="$US_ROOT/kindle_ssh_key.pub"
else
    PUBKEY_OUT="$US_ROOT/kindle_${KEYNAME}_ssh_key.pub"
fi

if [ ! -f "$KEY" ]; then
    eips_print "Error: No key '$KEYNAME' found."
    exit 1
fi

# Run dropbearkey once and tee to a temp file so we can both extract the
# public key line and grab the fingerprint without a second invocation.
PUBKEY_TMP=$(mktemp "${TMPDIR:-/tmp}/sshk-pubkey.XXXXXX")
trap 'rm -f "$PUBKEY_TMP"' EXIT INT TERM HUP

if ! "$BINDIR/dropbearkey" -y -f "$KEY" > "$PUBKEY_TMP" 2> "${PUBKEY_TMP}.err"; then
    cat "${PUBKEY_TMP}.err" >&2
    eips_print "Failed to extract public key (dropbearkey -y exited non-zero)."
    exit 1
fi

PUBKEY_LINE=$(grep "^ssh-" "$PUBKEY_TMP" || true)
if [ -z "$PUBKEY_LINE" ]; then
    eips_print "Failed to extract public key (no 'ssh-' line in dropbearkey output)."
    cat "$PUBKEY_TMP" >&2
    exit 1
fi

printf '%s\n' "$PUBKEY_LINE" > "$PUBKEY_OUT"

FINGERPRINT=$(grep '^Fingerprint' "$PUBKEY_TMP" | awk '{print $2}')
if [ -n "$FINGERPRINT" ]; then
    eips_print "Saved: $FINGERPRINT"
fi
cat "$PUBKEY_OUT"
