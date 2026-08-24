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
make -j"$(nproc)" > "$WORK/musl-build.log" 2>&1 || { tail -n 40 "$WORK/musl-build.log" >&2; exit 1; }
make install > "$WORK/musl-install.log" 2>&1 || { tail -n 40 "$WORK/musl-install.log" >&2; exit 1; }

echo "==> where did musl install go?"
grep -m3 'opt/musl-arm' "$WORK/musl-install.log" || echo "(no /opt/musl-arm paths found in install log)"

# Some cross configurations skip musl's tool-wrapper installation; both
# artifacts are deterministic templates, so regenerate them if missing.
if [ ! -f "$PREFIX/lib/musl-gcc.specs" ]; then
    mkdir -p "$PREFIX/lib"
    sh "$WORK/musl-$MUSL_VER/tools/musl-gcc.specs.sh" \
        "$PREFIX/include" "$PREFIX/lib" "/lib/ld-musl-arm.so.1" \
        > "$PREFIX/lib/musl-gcc.specs"
    echo "==> regenerated missing musl-gcc.specs"
fi
if [ ! -x "$PREFIX/bin/musl-gcc" ]; then
    mkdir -p "$PREFIX/bin"
    printf '#!/bin/sh\nexec "${REALGCC:-arm-linux-gnueabi-gcc}" "$@" -specs "%s/lib/musl-gcc.specs"\n' "$PREFIX" \
        > "$PREFIX/bin/musl-gcc"
    chmod +x "$PREFIX/bin/musl-gcc"
    echo "==> regenerated missing musl-gcc wrapper"
fi

echo "==> sanity check: musl-gcc must produce a runnable static ARM binary"
printf 'int main(void){return 42;}\n' > "$WORK/probe.c"
if ! "$PREFIX/bin/musl-gcc" -static -fno-PIE -no-pie "$WORK/probe.c" -o "$WORK/probe" 2> "$WORK/probe.err"; then
    echo "musl-gcc probe FAILED:" >&2
    cat "$WORK/probe.err" >&2
    exit 1
fi
# probe returns 42; qemu propagates the code (guarded so set -e survives it)
[ "$(qemu-arm-static "$WORK/probe" >/dev/null 2>&1; echo $?)" = "42" ]

cd "$WORK/dropbear-$VER"
echo "==> configuring Dropbear $VER (static, bundled libtom)"
if ! ./configure \
    CC="$PREFIX/bin/musl-gcc" \
    --host=arm-linux-musleabi \
    --enable-bundled-libtom \
    --disable-syslog \
    --disable-lastlog \
    --disable-wtmp \
    --disable-wtmpx \
    CFLAGS="-Os -fno-PIE -ffunction-sections -fdata-sections" \
    LDFLAGS="-no-pie -Wl,--gc-sections"; then
    echo "dropbear configure FAILED; config.log tail:" >&2
    tail -n 80 config.log >&2
    exit 1
fi

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
