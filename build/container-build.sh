#!/bin/sh
# Container-side build script: compiles a static dropbearmulti for Kindle.
# Runs INSIDE the container built from build/Dockerfile (see build-dropbear.sh).
#
# Usage: container-build.sh <dropbear-version> <out-dir>
set -eu

VER="${1:?usage: container-build.sh <dropbear-version> <out-dir>}"
OUT="${2:?usage: container-build.sh <dropbear-version> <out-dir>}"

MUSL_VER="1.2.5"
ZLIB_VER="1.3.1"
WORK="/tmp/build"
PREFIX="/opt/musl-arm"
mkdir -p "$WORK" "$OUT"

echo "==> fetching musl $MUSL_VER, zlib $ZLIB_VER and Dropbear $VER"

# fetch OUT_FILE URL_PRIMARY [URL_FALLBACK...] — 3 tries per URL
fetch() {
    _out="$1"; shift
    for _url in "$@"; do
        _try=1
        while [ "$_try" -le 3 ]; do
            echo "    GET $_url (attempt $_try)"
            if curl -fsSL --retry 2 --retry-delay 3 -o "$_out" "$_url"; then
                return 0
            fi
            _try=$((_try + 1))
            sleep 5
        done
    done
    echo "all mirrors failed for $_out" >&2
    return 1
}

fetch "$WORK/musl.tar.gz" \
    "https://musl.libc.org/releases/musl-${MUSL_VER}.tar.gz" \
    "https://git.musl-libc.org/cgit/musl/snapshot/musl-${MUSL_VER}.tar.gz"
fetch "$WORK/dropbear.tar.bz2" \
    "https://matt.ucc.asn.au/dropbear/releases/dropbear-${VER}.tar.bz2" \
    "https://github.com/mkj/dropbear/archive/refs/tags/DROPBEAR_${VER}.tar.gz"
fetch "$WORK/zlib.tar.gz" \
    "https://zlib.net/zlib-${ZLIB_VER}.tar.gz" \
    "https://github.com/madler/zlib/releases/download/v${ZLIB_VER}/zlib-${ZLIB_VER}.tar.gz"
tar -xzf "$WORK/musl.tar.gz" -C "$WORK"
tar -xzf "$WORK/zlib.tar.gz" -C "$WORK"
# GNU tar sniffs compression; GitHub's fallback tag archive differs in name+format
tar -xf "$WORK/dropbear.tar.bz2" -C "$WORK"
if [ ! -d "$WORK/dropbear-$VER" ] && [ -d "$WORK/dropbear-DROPBEAR_$VER" ]; then
    mv "$WORK/dropbear-DROPBEAR_$VER" "$WORK/dropbear-$VER"
fi

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

# Some cross configurations skip musl's tool-wrapper installation; regenerate
# both artifacts ourselves. Our specs deliberately NEVER emit a dynamic linker
# (Debian's hardening injects -Wl,-pie which otherwise downgrades -static to a
# dynamic PIE needing /lib/ld-musl-arm.so.1 at runtime — absent on Kindles).
mkdir -p "$PREFIX/lib"
cat > "$PREFIX/lib/musl-gcc.specs" <<SPECSEOF
%rename cpp_options old_cpp_options

*cpp_options:
-nostdinc -isystem $PREFIX/include %(old_cpp_options)

*cc1:
%(cc1_cpu) -nostdinc -isystem $PREFIX/include

*link_libgcc:
-L$PREFIX/lib

*libgcc:
libgcc.a%s %:if-exists(libgcc_eh.a%s)

*startfile:
%{!shared: $PREFIX/lib/crt1.o} $PREFIX/lib/crti.o crtbeginS.o%s

*endfile:
crtendS.o%s $PREFIX/lib/crtn.o

*link:
-nostdlib -static %{shared:-shared} %{rdynamic:-export-dynamic}
SPECSEOF
if [ ! -x "$PREFIX/bin/musl-gcc" ]; then
    mkdir -p "$PREFIX/bin"
    printf '#!/bin/sh\nexec "${REALGCC:-arm-linux-gnueabi-gcc}" "$@" -specs "%s/lib/musl-gcc.specs"\n' "$PREFIX" \
        > "$PREFIX/bin/musl-gcc"
    chmod +x "$PREFIX/bin/musl-gcc"
    echo "==> regenerated missing musl-gcc wrapper"
fi

echo "==> building zlib $ZLIB_VER (static, for SSH compression)"
cd "$WORK/zlib-$ZLIB_VER"
CC="$PREFIX/bin/musl-gcc" \
AR="arm-linux-gnueabi-ar" \
RANLIB="arm-linux-gnueabi-ranlib" \
./configure --static --prefix="$PREFIX" > "$WORK/zlib-config.log" 2>&1 || { tail -n 30 "$WORK/zlib-config.log" >&2; exit 1; }
make -j"$(nproc)" > "$WORK/zlib-build.log" 2>&1 || { tail -n 30 "$WORK/zlib-build.log" >&2; exit 1; }
make install > /dev/null 2>&1

echo "==> sanity check: musl-gcc must produce a runnable static ARM binary"
printf 'int main(void){return 42;}\n' > "$WORK/probe.c"
if ! "$PREFIX/bin/musl-gcc" -static -fno-PIE -no-pie "$WORK/probe.c" -o "$WORK/probe" 2> "$WORK/probe.err"; then
    echo "musl-gcc probe COMPILE FAILED:" >&2
    cat "$WORK/probe.err" >&2
    exit 1
fi
file "$WORK/probe"
set +e
qemu-arm-static "$WORK/probe"
QEMU_RC=$?
set -e
echo "==> probe exit code under qemu: $QEMU_RC (want 42)"
if [ "$QEMU_RC" != "42" ]; then
    echo "qemu smoke test failed" >&2
    exit 1
fi

cd "$WORK/dropbear-$VER"
echo "==> configuring Dropbear $VER (static, bundled libtom, system zlib)"
if ! ./configure \
    CC="$PREFIX/bin/musl-gcc" \
    --host=arm-linux-musleabi \
    --enable-bundled-libtom \
    --disable-syslog \
    --disable-lastlog \
    --disable-wtmp \
    --disable-wtmpx \
    CFLAGS="-Os -fno-PIE -ffunction-sections -fdata-sections -DDROPBEAR_SVR_PASSWORD_AUTH=0" \
    LDFLAGS="-no-pie -Wl,--gc-sections"; then
    echo "dropbear configure FAILED; config.log tail:" >&2
    tail -n 80 config.log >&2
    exit 1
fi

echo "==> compiling objects"
# Explicit AR/RANLIB: without them the bundled libtom sub-makes silently
# produce no archive under this toolchain.
arm-linux-gnueabi-ar rcs "$PREFIX/lib/libcrypt.a"
make -j"$(nproc)" MULTI=1 STATIC=1 PROGRAMS="dbclient dropbear dropbearkey scp" \
    AR="arm-linux-gnueabi-ar" RANLIB="arm-linux-gnueabi-ranlib"

echo "==> explicit static final link via ld"
# Debian's cross-gcc injects hardening (-Wl,-pie etc.) that downgrades -static
# to a dynamic PIE regardless of driver flags. Drive ld directly with every
# component named so nothing can be reinterpreted.
# shellcheck disable=SC2035  # intentional single-dir glob
OBJECTS=""
for f in *.o; do
    [ -f "$f" ] || continue
    OBJECTS="$OBJECTS \"$f\""
done
if [ -z "${OBJECTS:-}" ]; then
    echo "no dropbear objects found for manual link" >&2
    exit 1
fi
LIBGCC_DIR="$(dirname "$(arm-linux-gnueabi-gcc -print-libgcc-file-name)")"
cat > "$WORK/relink.sh" <<RELINK_EOF
#!/bin/sh
set -eu
cd "$WORK/dropbear-$VER"
exec arm-linux-gnueabi-ld \\
    --gc-sections -static \\
    -o dropbearmulti-static \\
    $PREFIX/lib/crt1.o $PREFIX/lib/crti.o \\
    $OBJECTS \\
    libtomcrypt/libtomcrypt.a libtommath/libtommath.a \\
    -L$PREFIX/lib -lz \\
    $PREFIX/lib/libc.a \\
    --start-group $LIBGCC_DIR/libgcc.a $LIBGCC_DIR/libgcc_eh.a --end-group \\
    $PREFIX/lib/crtn.o
RELINK_EOF
sh "$WORK/relink.sh" || { echo "manual static link failed" >&2; exit 1; }

# Binary lands at the source root (2020.x) or under src/ depending on release
DBMULTI="dropbearmulti-static"
[ -f "$DBMULTI" ] || { echo "static link produced no output" >&2; exit 1; }
arm-linux-gnueabi-strip "$DBMULTI"
cp "$DBMULTI" "$OUT/dropbearmulti"

echo "==> verifying the artifact is fully static (hard requirement for Kindles)"
file "$OUT/dropbearmulti"
if file "$OUT/dropbearmulti" | grep -q 'statically linked'; then
    echo "==> OK: statically linked"
else
    echo "FATAL: artifact is not statically linked — it would not run on a Kindle" >&2
    exit 1
fi

echo "==> smoke test under qemu-user (executes the ARM binary end to end)"
rm -f /tmp/smoke_key
qemu-arm-static "$OUT/dropbearmulti" dropbearkey -t ed25519 -f /tmp/smoke_key > "$WORK/smoke.log" 2>&1 || { cat "$WORK/smoke.log" >&2; exit 1; }
test -s /tmp/smoke_key
rm -f /tmp/smoke_key

{
    echo "dropbear version : $VER"
    echo "musl version     : $MUSL_VER"
    echo "zlib version     : $ZLIB_VER (static)"
    echo "float ABI        : soft-float (musleabi) for broad Kindle support"
    echo "programs         : dbclient dropbear dropbearkey scp"
    echo "note             : inbound server PASSWORD auth disabled (musl >= 1.2.5"
    echo "                     dropped crypt()); public-key auth is unaffected and"
    echo "                     is the flow sshk documents (authorize-server.sh)"
} > "$OUT/BUILD-INFO.txt"
sha256sum "$OUT/dropbearmulti" > "$OUT/dropbearmulti.sha256"

echo "==> done"
file "$OUT/dropbearmulti"
cat "$OUT/dropbearmulti.sha256"
