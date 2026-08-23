#!/bin/sh
# Container-side build script: compiles a static dropbearmulti for Kindle.
# Runs INSIDE the container built from build/Dockerfile (see build-dropbear.sh).
#
# Usage: container-build.sh <dropbear-version> <out-dir>
set -eu

VER="${1:?usage: container-build.sh <dropbear-version> <out-dir>}"
OUT="${2:?usage: container-build.sh <dropbear-version> <out-dir>}"

MUSL_VER="1.2.5"
WORK="/tmp/build"
PREFIX="/opt/musl-arm"
mkdir -p "$WORK" "$OUT"

echo "==> fetching musl $MUSL_VER and Dropbear $VER"
curl -fsSL -o "$WORK/musl.tar.gz" "https://musl.libc.org/releases/musl-${MUSL_VER}.tar.gz"
curl -fsSL -o "$WORK/dropbear.tar.bz2" "https://matt.ucc.asn.au/dropbear/releases/dropbear-${VER}.tar.bz2"
tar -xzf "$WORK/musl.tar.gz" -C "$WORK"
tar -xjf "$WORK/dropbear.tar.bz2" -C "$WORK"

echo "==> bootstrapping musl cross toolchain ($MUSL_VER, arm-linux-musleabi)"
cd "$WORK/musl-$MUSL_VER"
CC=arm-linux-gnueabi-gcc \
AR=arm-linux-gnueabi-ar \
RANLIB=arm-linux-gnueabi-ranlib \
./configure \
    --target=arm-linux-musleabi \
    --prefix="$PREFIX"
make -j"$(nproc)" >/dev/null
make install >/dev/null

echo "==> configuring Dropbear $VER (static, bundled libtom)"
cd "$WORK/dropbear-$VER"
./configure \
    CC="$PREFIX/bin/musl-gcc" \
    --host=arm-linux-musleabi \
    --enable-bundled-libtom \
    --disable-syslog \
    --disable-lastlog \
    --disable-wtmp \
    --disable-wtmpx \
    CFLAGS="-Os -ffunction-sections -fdata-sections" \
    LDFLAGS="-Wl,--gc-sections"

echo "==> building multi-call binary (dbclient, dropbear, dropbearkey, scp)"
make -j"$(nproc)" MULTI=1 STATIC=1 PROGRAMS="dbclient dropbear dropbearkey scp"

arm-linux-gnueabi-strip src/dropbearmulti
cp src/dropbearmulti "$OUT/dropbearmulti"

echo "==> smoke test under qemu-user (executes the ARM binary end to end)"
rm -f /tmp/smoke_key
qemu-arm-static "$OUT/dropbearmulti" dropbearkey -t ed25519 -f /tmp/smoke_key >/dev/null
test -s /tmp/smoke_key
rm -f /tmp/smoke_key

{
    echo "dropbear version : $VER"
    echo "musl version     : $MUSL_VER"
    echo "float ABI        : soft-float (musleabi) for broad Kindle support"
    echo "programs         : dbclient dropbear dropbearkey scp"
} > "$OUT/BUILD-INFO.txt"
sha256sum "$OUT/dropbearmulti" > "$OUT/dropbearmulti.sha256"

echo "==> done"
file "$OUT/dropbearmulti"
cat "$OUT/dropbearmulti.sha256"
