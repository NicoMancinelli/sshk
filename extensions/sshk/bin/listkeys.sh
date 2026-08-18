#!/bin/sh

BINDIR="$(cd "$(dirname "$0")" && pwd)"

eips_print() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                    "
    eips 0 "$ROW" "$TEXT"
}

eips -c
eips_print 2 "SSH Keys:"

ROW=4
KEYS_FOUND=0

for keyfile in "$BINDIR"/kindle_*_key; do
    if [ ! -f "$keyfile" ]; then
        continue
    fi
    KEYS_FOUND=$((KEYS_FOUND + 1))
    
    filename="$(basename "$keyfile")"
    keyname="${filename#kindle_}"
    keyname="${keyname%_key}"
    
    fingerprint="$("$BINDIR/dropbearkey" -y -f "$keyfile" 2>/dev/null | grep 'Fingerprint')"
    fingerprint="${fingerprint#*Fingerprint: }"
    
    echo "Key: $keyname"
    echo "  $fingerprint"
    
    eips_print "$ROW" "- $keyname"
    ROW=$((ROW + 1))
    eips_print "$ROW" "  $fingerprint"
    ROW=$((ROW + 2))
done

if [ "$KEYS_FOUND" -eq 0 ]; then
    echo "No keys found. Run Generate Key first."
    eips_print 4 "No keys found. Run Generate Key first."
fi
