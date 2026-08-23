#!/bin/sh
# build-dropbear.sh - Reproducible host-side build of extensions/sshk/bin/dropbearmulti.
#
# Usage:
#   build/build-dropbear.sh               # build version pinned in extensions/sshk/DROPBEAR_VERSION
#   build/build-dropbear.sh 2024.86       # build a specific upstream release
#
# Output lands in ./out/ (gitignored). To ship a rebuild:
#   cp out/dropbearmulti extensions/sshk/bin/
# and update extensions/sshk/DROPBEAR_VERSION if you changed releases.
#
# Requirements: docker. The whole toolchain (pinned musl + cross gcc + QEMU
# smoke test) lives inside the image, so nothing else is needed on the host.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is required (it provides the cross toolchain and QEMU smoke test)." >&2
    exit 1
fi

if [ $# -gt 0 ]; then
    VER="$1"
else
    VER="$(cat "$ROOT/extensions/sshk/DROPBEAR_VERSION")"
fi

OUT="$ROOT/out"
mkdir -p "$OUT"

echo "==> building builder image"
docker build -t sshk-dropbear-builder "$HERE"

echo "==> compiling dropbearmulti $VER"
docker run --rm \
    -v "$OUT:/out" \
    sshk-dropbear-builder "$VER" /out

echo ""
echo "Artifact: $OUT/dropbearmulti"
echo "To ship:  cp out/dropbearmulti extensions/sshk/bin/ && git add extensions/sshk/bin/dropbearmulti"
[ "$VER" != "$(cat "$ROOT/extensions/sshk/DROPBEAR_VERSION")" ] && {
    echo "NOTE: you built a different release than the pinned one; update extensions/sshk/DROPBEAR_VERSION if adopting it."
}
exit 0
