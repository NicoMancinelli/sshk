#!/bin/sh

BINDIR="$(cd "$(dirname "$0")" && pwd)"
EXTDIR="$(cd "$BINDIR/.." && pwd)"

eips_print() {
    ROW="$1"
    TEXT="$2"
    eips 0 "$ROW" "                                                    "
    eips 0 "$ROW" "$TEXT"
}

VERSION="Unknown"
if [ -f "$EXTDIR/VERSION" ]; then
    VERSION="$(cat "$EXTDIR/VERSION")"
fi

DB_VERSION="$("$BINDIR/dropbearmulti" dbclient -V 2>&1 | head -1)"
if [ -z "$DB_VERSION" ]; then
    DB_VERSION="Unknown"
fi

KEYS_COUNT=0
for key in "$BINDIR"/kindle_*_key; do
    if [ -f "$key" ]; then
        KEYS_COUNT=$((KEYS_COUNT + 1))
    fi
done

KNOWN_HOSTS_STATUS="Not set up"
if [ -h "/root/.ssh/known_hosts" ] || [ -f "/root/.ssh/known_hosts" ]; then
    KNOWN_HOSTS_STATUS="Set up"
fi

echo "SSHK Version: $VERSION"
echo "Dropbear: $DB_VERSION"
echo "Keys found: $KEYS_COUNT"
echo "Known hosts: $KNOWN_HOSTS_STATUS"

eips -c
eips_print 2 "SSHK Version: $VERSION"
eips_print 3 "Dropbear: $DB_VERSION"
eips_print 4 "Keys found: $KEYS_COUNT"
eips_print 5 "Known hosts: $KNOWN_HOSTS_STATUS"
