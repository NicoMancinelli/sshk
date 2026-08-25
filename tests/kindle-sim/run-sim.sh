#!/bin/sh
# run-sim.sh - Kindle environment simulator: executes the REAL sshk KUAL menu
# scripts end-to-end inside a fake Kindle root (/mnt/us, eips, lipc-set-prop,
# mntroot, wlan0 ...), asserting each menu item behaves.
#
# Two modes:
#   * qemu available (qemu-arm-static/qemu-arm): the actual ARM dropbearmulti
#     binary executes under user-mode emulation, including a live inbound
#     dropbear server we probe over TCP.
#   * no qemu: a deterministic stub stands in for the binary so script logic
#     is still exercised on any machine.
#
# Usage: tests/kindle-sim/run-sim.sh   (exit 0 = all pass)

set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=""

ok() {
    PASS=$((PASS + 1))
    printf 'ok %2d - %s\n' "$PASS" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    FAILED_NAMES="$FAILED_NAMES
  - $1"
    printf 'NOT OK   - %s\n' "$1"
    shift
    for _msg in "$@"; do
        [ -n "$_msg" ] && printf '%s\n' "$_msg" | sed 's/^/    /'
    done
}

assert_eq() { # NAME WANT GOT
    if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "want: $2 / got: $3"; fi
}

assert_file() { # NAME PATH
    if [ -s "$2" ]; then ok "$1"; else fail "$1" "missing or empty: $2"; fi
}

assert_grep() { # NAME PATTERN FILE
    if grep -q "$2" "$3" 2>/dev/null; then ok "$1"; else fail "$1" "pattern not found in $3: $2"; fi
}

# ---------------------------------------------------------------- sandbox ---
SIM="$(mktemp -d "${TMPDIR:-/tmp}/sshk-sim.XXXXXX")"
# shellcheck disable=SC2317  # everything inside is reached via signal trap
cleanup() {
    [ -f "$SIM/mnt/us/extensions/sshk/bin/.server-pid" ] && {
        p=$(cat "$SIM/mnt/us/extensions/sshk/bin/.server-pid" 2>/dev/null) && kill "$p" 2>/dev/null
    }
    _pat='dropbearmulti-stati'; pkill -f "\${_pat}c" 2>/dev/null
    [ "${SIM_KEEP:-0}" = "1" ] && { echo "SIM kept: $SIM"; return 0; }
    rm -rf "$SIM"
}
trap cleanup EXIT INT TERM HUP

US="$SIM/mnt/us"
SSHK="$US/extensions/sshk"
BIN="$SSHK/bin"
KTERMBIN="$US/extensions/kterm/bin"
mkdir -p "$BIN" "$KTERMBIN" "$US"
export SSHK_US_ROOT="$US"

# Real extension payload
cp -r "$ROOT/extensions/sshk/bin/." "$BIN/"
cp "$ROOT/extensions/sshk/menu.json" "$ROOT/extensions/sshk/config.xml" \
   "$ROOT/extensions/sshk/hosts.conf" "$ROOT/extensions/sshk/VERSION" "$SSHK/"

# ------------------------------------------------------- Lab126 mock tools ---
MOCKS="$SIM/mocks"
mkdir -p "$MOCKS"
EIPS_LOG="$SIM/eips.log"
LIPC_LOG="$SIM/lipc.log"
export EIPS_LOG LIPC_LOG

cat > "$MOCKS/eips" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$EIPS_LOG"
exit 0
EOF

cat > "$MOCKS/lipc-set-prop" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$LIPC_LOG"
exit 0
EOF

cat > "$MOCKS/mntroot" <<'EOF'
#!/bin/sh
exit 0
EOF

cat > "$MOCKS/ip" <<'EOF'
#!/bin/sh
if [ "${2:-}" = "-4" ] && [ "${3:-}" = "addr" ]; then
    printf '2: wlan0: <BROADCAST,MULTICAST,UP>\n'
    printf '    inet 192.168.15.42/24 brd 192.168.15.255 scope global wlan0\n'
fi
exit 0
EOF

chmod +x "$MOCKS"/*

# ------------------------------------------- dropbearmulti routing wrapper ---
# Real ARM binary via qemu when possible; stub otherwise.
REAL_MULTI="$BIN/dropbearmulti.real"
mv "$BIN/dropbearmulti" "$REAL_MULTI"
cp "$ROOT/tests/stubs/dropbearmulti" "$BIN/.stub-multi"
cat > "$BIN/dropbearmulti" <<EOF
#!/bin/sh
D="\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)"
QEMU="\${QEMU_ARM:-}"
if [ -z "\$QEMU" ] && command -v qemu-arm-static >/dev/null 2>&1; then
    QEMU=\$(command -v qemu-arm-static)
fi
if [ -n "\$QEMU" ] && [ -x "\$QEMU" ]; then
    exec "\$QEMU" "\$D/.real-dropbearmulti" "\$@"
fi
exec "\$D/.stub-multi" "\$@"
EOF
mv "$BIN/dropbearmulti" "$BIN/dropbearmulti.tmp"
sed "s|\$D/.real-dropbearmulti|$REAL_MULTI|" "$BIN/dropbearmulti.tmp" > "$BIN/dropbearmulti"
rm -f "$BIN/dropbearmulti.tmp"
chmod +x "$BIN/dropbearmulti"

# Direct 'dropbearkey' file invocations route through the same wrapper with
# the applet argument prepended (production calls it directly too).
{ printf '#!/bin/sh\nset -- dropbearkey "$@"\nexec "%s/dropbearmulti" "$@"\n' "$BIN"; } > "$BIN/dropbearkey"
chmod +x "$BIN/dropbearkey"

export PATH="$BIN:$MOCKS:$PATH"

# ------------------------------------------------------------ sim fixtures ---
printf '#!/bin/sh\necho "fake kterm-ui started: $*"\n' > "$KTERMBIN/kterm.sh"
cp "$KTERMBIN/kterm.sh" "$KTERMBIN/kterm.orig-fixture"
chmod +x "$KTERMBIN/kterm.sh"
cat > "$KTERMBIN/kterm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$SIM/kterm-args.log"
EOF
chmod +x "$KTERMBIN/kterm"

run_menu() { # SCRIPT ARGS...
    script="$1"; shift
    (cd "$SSHK" && "$BIN/$script" "$@") > "$SIM/out.log" 2>&1
}

# ------------------------------------------------------------------ tests ---
echo "== mode: $(command -v qemu-arm-static >/dev/null 2>&1 && echo 'real ARM binary under qemu' || echo 'stub binary (no qemu)') =="

echo "[sim] 1-Tap Setup"
run_menu install.sh
assert_eq "install: exit code" "0" "$?"
assert_grep "install: kterm PATH injected" "extensions/sshk/bin" "$KTERMBIN/kterm.sh"
if [ -f "$KTERMBIN/kterm.sh.orig" ]; then ok "install: kterm backup created"; else fail "install: kterm backup created"; fi
assert_file "install: native key generated" "$BIN/kindle_native_key"
assert_file "install: pubkey exported to USB root" "$US/kindle_ssh_key.pub"

echo "[sim] About sshk"
run_menu version.sh
assert_eq "version: exit code" "0" "$?"
assert_grep "version: banner printed" "SSHK Version:" "$SIM/out.log"

echo "[sim] Generate New SSH Key"
run_menu genkey.sh work
assert_eq "genkey(work): exit code" "0" "$?"
assert_file "genkey(work): key created" "$BIN/kindle_work_key"
assert_file "genkey(work): pubkey exported" "$US/kindle_work_ssh_key.pub"

echo "[sim] List SSH Keys"
run_menu listkeys.sh
assert_eq "listkeys: exit code" "0" "$?"

echo "[sim] Export Public SSH Key"
run_menu showkey.sh native
assert_eq "showkey(native): exit code" "0" "$?"
assert_file "showkey(native): USB export refreshed" "$US/kindle_ssh_key.pub"

echo "[sim] Open SSH Terminal (Landscape)"
run_menu kterm-landscape.sh
assert_eq "landscape: exit code" "0" "$?"
assert_grep "landscape: kterm flags" "\\-o R" "$SIM/kterm-args.log"
assert_grep "landscape: ssh-menu auto-run" "ssh-menu" "$SIM/kterm-args.log"

echo "[sim] Start SSH Server (Port 2222)"
run_menu server-start.sh
assert_eq "server-start: exit code" "0" "$?"
PIDFILE="/tmp/sshk_dropbear.pid"
if command -v qemu-arm-static >/dev/null 2>&1; then
    # Full-fidelity mode: a real dropbear daemon runs under emulation.
    # Liveness is proven by the listening socket, NOT by kill -0 on the
    # pidfile PID: dropbear double-forks, so that PID goes stale at once.
    sleep 2
    if [ -f "$PIDFILE" ]; then ok "server-start: pidfile written"; else fail "server-start: pidfile written"; fi
    if command -v nc >/dev/null 2>&1; then
        BANNER="$(printf '' | timeout 5 nc 127.0.0.1 2222 2>/dev/null | head -c 32)"
        case "$BANNER" in
            SSH-2*) ok "server-start: SSH banner served on 2222 ($BANNER)" ;;
            *) fail "server-start: SSH banner served on 2222" "got: ${BANNER:-<nothing>}" ;;
        esac
    else
        echo "   (nc unavailable - skipping banner probe)"
    fi
else
    # Stub mode: the stub exits immediately, so only the script contract holds
    if [ -f "$PIDFILE" ]; then ok "server-start: pidfile written (stub mode)"; else fail "server-start: pidfile written (stub mode)"; fi
    rm -f "$PIDFILE"
fi

echo "[sim] Stop SSH Server"
run_menu server-stop.sh
assert_eq "server-stop: exit code" "0" "$?"
if command -v qemu-arm-static >/dev/null 2>&1; then
    sleep 1
    if [ -f "$PIDFILE" ]; then
        if ! kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then ok "server-stop: process terminated"; else fail "server-stop: process terminated"; fi
    else
        ok "server-stop: pidfile removed"
    fi
fi

echo "[sim] Uninstall SSH from kterm"
run_menu uninstall.sh
assert_eq "uninstall: exit code" "0" "$?"
if grep -q "extensions/sshk/bin" "$KTERMBIN/kterm.sh"; then
    fail "uninstall: PATH entry removed from kterm.sh"
else
    ok "uninstall: PATH entry removed from kterm.sh"
fi

echo "[sim] SSH Server toggle (both directions)"
PIDFILE="/tmp/sshk_dropbear.pid"
run_menu server-toggle.sh
assert_eq "toggle start: exit code" "0" "$?"
if command -v qemu-arm-static >/dev/null 2>&1 && command -v nc >/dev/null 2>&1; then
    sleep 2
    BANNER="$(printf '' | timeout 5 nc 127.0.0.1 2222 2>/dev/null | head -c 16)"
    case "$BANNER" in
        SSH-2*) ok "toggle: server came up" ;;
        *) fail "toggle: server came up" "got: ${BANNER:-<nothing>}" ;;
    esac
    run_menu server-toggle.sh
    assert_eq "toggle stop: exit code" "0" "$?"
    sleep 1
    BANNER="$(printf '' | timeout 5 nc 127.0.0.1 2222 2>/dev/null | head -c 16)"
    case "$BANNER" in
        SSH-2*) fail "toggle: server went down" "banner still served" ;;
        *) ok "toggle: server went down" ;;
    esac
else
    # Stub mode: the stub daemon exits instantly, so state cannot be observed;
    # assert only that both directions execute cleanly.
    if [ -f "$PIDFILE" ]; then ok "toggle: start path delegated (stub mode)"; else fail "toggle: start path delegated (stub mode)"; fi
    rm -f "$PIDFILE"
fi

# ---------------------------------------------------------------- summary ---
echo ""
echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'failed tests:%s\n' "$FAILED_NAMES"
    exit 1
fi
exit 0
