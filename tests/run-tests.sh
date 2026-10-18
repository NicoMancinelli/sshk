#!/bin/sh
# run-tests.sh - Functional tests for sshk shell wrappers.
#
# Runs the real wrapper scripts from extensions/sshk/bin inside a sandbox
# where dbclient/dropbearmulti/lipc-set-prop/tailscale/showkey are replaced
# by deterministic stubs, then asserts on the exact argv each wrapper passes
# down. No Kindle device or root access required.
#
# Usage: tests/run-tests.sh    (exit 0 = all pass)

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
FAILED_NAMES=""

# ---------------------------------------------------------------- sandbox ---
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/sshk-tests.XXXXXX")"
cleanup() {
    # shellcheck disable=SC2317  # reached via signal trap, not a direct call
    rm -rf "$SANDBOX"
}
trap cleanup EXIT INT TERM HUP

BIN="$SANDBOX/bin"
mkdir -p "$BIN"
# ssh / ssh-tailscale / scp-tailscale source sshk-common.sh from BINDIR, so it
# has to be staged alongside them.
for wrapper in ssh ssh-tailscale scp scp-tailscale sshk-common.sh; do
    cp "$ROOT/extensions/sshk/bin/$wrapper" "$BIN/" || exit 1
done
cp "$ROOT"/tests/stubs/* "$BIN/" || exit 1
cp "$BIN/dropbearmulti" "$BIN/dropbearkey"   # multi-call binary: same code, two names
chmod +x "$BIN"/*

export PATH="$BIN:$PATH"
SSHK_TEST_LOG="$SANDBOX/dbclient.log"
LIPC_LOG="$SANDBOX/lipc.log"
export SSHK_TEST_LOG LIPC_LOG

HOSTS_CONF="$SANDBOX/hosts.conf"
NATIVE_KEY="$BIN/kindle_native_key"

# Mirror the wrapper's own probe: does OPTS get a leading "-y"?
if [ -w /root/.ssh/known_hosts ] || touch /root/.ssh/known_hosts 2>/dev/null; then
    Y=""
else
    Y="-y"
fi

# ---------------------------------------------------------------- helpers ---
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
        if [ -n "$_msg" ]; then
            printf '%s\n' "$_msg" | sed 's/^/    /'
        fi
    done
}

reset_case() {
    rm -f "$BIN"/kindle_*_key "$SSHK_TEST_LOG" "$LIPC_LOG" "$HOSTS_CONF"
}

write_hosts() {
    printf '%b' "$1" > "$HOSTS_CONF"
}

# join_args ARGS... -> one non-empty arg per line (matches stub log format)
join_args() {
    for a in "$@"; do
        if [ -n "$a" ]; then
            printf '%s\n' "$a"
        fi
    done
}

# assert_dbclient_args NAME EXPECTED_ARG...
assert_dbclient_args() {
    _name="$1"
    shift
    join_args "$@" > "$SANDBOX/expected"
    if diff -u "$SANDBOX/expected" "$SSHK_TEST_LOG" > "$SANDBOX/diff" 2>&1; then
        ok "$_name"
    else
        fail "$_name" "argv mismatch:" "$(cat "$SANDBOX/diff")"
    fi
}

# assert_rc NAME EXPECTED_RC ACTUAL_RC [STDERR_FILE NEEDLE]
assert_rc() {
    _name="$1"; _want="$2"; _got="$3"
    if [ "$_want" = "$_got" ]; then
        ok "$_name"
    else
        fail "$_name" "exit code: want $_want, got $_got"
    fi
}

# ------------------------------------------------------------------ tests ---
echo "== ssh wrapper =="

reset_case
"$BIN/ssh" user@example.com >/dev/null 2>&1
assert_dbclient_args "plain target injects native key" \
    "$Y" -i "$NATIVE_KEY" user@example.com
if [ -f "$NATIVE_KEY" ]; then
    ok "first run auto-generates native key"
else
    fail "first run auto-generates native key" "kindle_native_key missing after run"
fi

reset_case
write_hosts "# sshk hosts\n\nmyserver admin@192.168.1.10\n\nwork dev@work.example.com:2222\n"
"$BIN/ssh" myserver >/dev/null 2>&1
assert_dbclient_args "alias resolves host (comments/blanks skipped)" \
    "$Y" -i "$NATIVE_KEY" admin@192.168.1.10

reset_case
write_hosts "work dev@work.example.com:2222\n"
"$BIN/ssh" work >/dev/null 2>&1
assert_dbclient_args "alias expands host:port into -p" \
    "$Y" -i "$NATIVE_KEY" -p 2222 dev@work.example.com

reset_case
write_hosts "tailnet user@mypc work\n"
: > "$BIN/kindle_work_key"
"$BIN/ssh" tailnet >/dev/null 2>&1
assert_dbclient_args "alias selects named key" \
    "$Y" -i "$BIN/kindle_work_key" user@mypc
if [ ! -f "$NATIVE_KEY" ]; then
    ok "named key present: native key generation skipped"
else
    fail "named key present: native key generation skipped" "kindle_native_key should not exist"
fi

reset_case
"$BIN/ssh" -i home user@example.com >/dev/null 2>&1
assert_dbclient_args "-i name maps to kindle_<name>_key" \
    "$Y" -i "$BIN/kindle_home_key" user@example.com

reset_case
"$BIN/ssh" -i /absolute/path/key user@example.com >/dev/null 2>&1
assert_dbclient_args "-i absolute path passes through unchanged" \
    "$Y" -i /absolute/path/key user@example.com

reset_case
"$BIN/ssh" -p 2222 user@example.com >/dev/null 2>&1
assert_dbclient_args "custom port flag forwarded" \
    "$Y" -i "$NATIVE_KEY" -p 2222 user@example.com

reset_case
"$BIN/ssh" user@example.com >/dev/null 2>&1
if [ "$(wc -l < "$LIPC_LOG")" = "6" ] \
    && [ "$(sed -n '3p' "$LIPC_LOG")" = "1" ] \
    && [ "$(sed -n '6p' "$LIPC_LOG")" = "0" ]; then
    ok "screensaver inhibited during session, restored on exit"
else
    fail "screensaver inhibited during session, restored on exit" \
        "lipc-set-prop log:" "$(cat "$LIPC_LOG" 2>/dev/null)"
fi

echo "== ssh-tailscale wrapper =="

reset_case
"$BIN/ssh-tailscale" >/dev/null 2>&1
assert_rc "no arguments -> usage error (exit 1)" "1" "$?"

reset_case
"$BIN/ssh-tailscale" -L 8080:localhost:80 >/dev/null 2>&1
assert_rc "options but no target -> error (exit 1)" "1" "$?"

reset_case
"$BIN/ssh-tailscale" user@myhost.example >/dev/null 2>&1
assert_dbclient_args "plain target tunnels via tailscale nc" \
    "$Y" -i "$NATIVE_KEY" -J "tailscale nc myhost.example 22" user@myhost.example

reset_case
"$BIN/ssh-tailscale" -p 2223 user@myhost.example >/dev/null 2>&1
assert_dbclient_args "custom port reaches ProxyCommand" \
    "$Y" -i "$NATIVE_KEY" -J "tailscale nc myhost.example 2223" user@myhost.example

reset_case
write_hosts "tsbox u@10.0.0.5:2280 w\n"
: > "$BIN/kindle_w_key"
"$BIN/ssh-tailscale" tsbox >/dev/null 2>&1
assert_dbclient_args "alias resolves host, port and named key over tailscale" \
    "$Y" -J "tailscale nc 10.0.0.5 2280" -i "$BIN/kindle_w_key" u@10.0.0.5

reset_case
SSHK_TEST_FORCE_AUTO_ACCEPT=1 "$BIN/ssh-tailscale" user@myhost.example >/dev/null 2>&1
assert_dbclient_args "known_hosts probe forces -y on tailscale when unwritable" \
    -y -i "$NATIVE_KEY" -J "tailscale nc myhost.example 22" user@myhost.example

reset_case
SSHK_TEST_FORCE_AUTO_ACCEPT=1 "$BIN/ssh" user@example.com >/dev/null 2>&1
assert_dbclient_args "known_hosts probe forces -y on ssh when unwritable" \
    -y -i "$NATIVE_KEY" user@example.com

reset_case
"$BIN/ssh-tailscale" -i work user@host.example >/dev/null 2>&1
assert_dbclient_args "ssh-tailscale -i name maps to kindle_<name>_key" \
    "$Y" -J "tailscale nc host.example 22" -i "$BIN/kindle_work_key" user@host.example
if [ ! -f "$NATIVE_KEY" ]; then
    ok "ssh-tailscale -i name: native key generation skipped"
else
    fail "ssh-tailscale -i name: native key generation skipped" "kindle_native_key should not exist"
fi

reset_case
# Build a sealed PATH that contains only an empty directory so neither
# `command -v tailscale` nor any stray host binary can satisfy the lookup.
SEALED="$SANDBOX/sealed"
mkdir -p "$SEALED"
PATH="$SEALED" "$BIN/ssh-tailscale" user@example.com >/tmp/sshr.err 2>&1
_RC=$?
assert_rc "ssh-tailscale without tailscale binary -> exit 1" "1" "$_RC"
if grep -q "tailscale" /tmp/sshr.err; then
    ok "ssh-tailscale missing-binary error mentions tailscale"
else
    fail "ssh-tailscale missing-binary error mentions tailscale" "stderr was:" "$(cat /tmp/sshr.err)"
fi
rm -rf "$SEALED"
# PATH was sealed above; the wrapper's PATH was already exported at sandbox
# setup, so subsequent calls still see $BIN first.

echo "== shared helpers (sshk-common.sh) =="

# The known_hosts probe, the screensaver calls and the alias lookup now live in
# exactly one file. These checks fail if a future edit reintroduces a
# per-wrapper copy — which is how the two SSH wrappers drifted apart before
# v1.5 (ssh verified host keys while ssh-tailscale auto-accepted them).
LIB="$ROOT/extensions/sshk/bin/sshk-common.sh"
if [ -f "$LIB" ]; then
    ok "shared helper library sshk-common.sh is shipped"
else
    fail "shared helper library sshk-common.sh is shipped" "missing $LIB"
fi

for fn in sshk_known_hosts_flags sshk_map_identity sshk_lookup_alias \
          sshk_alias_names sshk_native_key_opts sshk_inhibit_screensaver; do
    if [ -f "$LIB" ] && grep -q "^$fn()" "$LIB"; then
        ok "sshk-common.sh defines $fn"
    else
        fail "sshk-common.sh defines $fn" "no '^$fn()' definition in $LIB"
    fi
done

for wrapper in ssh ssh-tailscale scp-tailscale; do
    if grep -q 'sshk-common.sh' "$ROOT/extensions/sshk/bin/$wrapper"; then
        ok "$wrapper sources the shared library"
    else
        fail "$wrapper sources the shared library" "no sshk-common.sh reference"
    fi
done

# Single-source-of-truth guards.
_count=$(grep -rl 'touch /root/.ssh/known_hosts' "$ROOT/extensions/sshk/bin" | wc -l)
if [ "$_count" = "1" ]; then
    ok "known_hosts probe defined in exactly one file"
else
    fail "known_hosts probe defined in exactly one file" \
        "found in $_count files: $(grep -rl 'touch /root/.ssh/known_hosts' "$ROOT/extensions/sshk/bin" | tr '\n' ' ')"
fi
_count=$(grep -rl 'preventScreenSaver' "$ROOT/extensions/sshk/bin" | wc -l)
if [ "$_count" = "1" ]; then
    ok "screensaver calls defined in exactly one file"
else
    fail "screensaver calls defined in exactly one file" \
        "found in $_count files: $(grep -rl 'preventScreenSaver' "$ROOT/extensions/sshk/bin" | tr '\n' ' ')"
fi

# Direct unit checks of the helpers (sourced in a subshell, bypassing the
# wrappers) so the shared code is covered on its own terms.
if [ -f "$LIB" ]; then
    _out=$(SSHK_TEST_FORCE_AUTO_ACCEPT=1
           . "$LIB"
           sshk_known_hosts_flags)
    if [ "$_out" = "-y" ]; then
        ok "sshk_known_hosts_flags honours the forced auto-accept probe"
    else
        fail "sshk_known_hosts_flags honours the forced auto-accept probe" "got: $_out"
    fi

    _out=$(. "$LIB"; sshk_map_identity work /base)
    if [ "$_out" = "/base/kindle_work_key" ]; then
        ok "sshk_map_identity expands a bare key name"
    else
        fail "sshk_map_identity expands a bare key name" "got: $_out"
    fi

    _out=$(. "$LIB"; sshk_map_identity /abs/key /base)
    if [ "$_out" = "/abs/key" ]; then
        ok "sshk_map_identity passes an absolute path through unchanged"
    else
        fail "sshk_map_identity passes an absolute path through unchanged" "got: $_out"
    fi

    reset_case
    write_hosts "alpha admin@10.0.0.1\nalias2 root@h.example:2222 km\n"
    _out=$(. "$LIB"
           sshk_lookup_alias "$HOSTS_CONF" alias2 && \
           printf '%s|%s|%s' "$SSHK_ALIAS_HOST" "$SSHK_ALIAS_PORT" "$SSHK_ALIAS_KEY")
    if [ "$_out" = "root@h.example|2222|km" ]; then
        ok "sshk_lookup_alias splits host, port and key"
    else
        fail "sshk_lookup_alias splits host, port and key" "got: $_out"
    fi

    _rc=$(. "$LIB"; sshk_lookup_alias "$HOSTS_CONF" nosuch; echo $?)
    if [ "$_rc" = "1" ]; then
        ok "sshk_lookup_alias reports a miss with rc 1"
    else
        fail "sshk_lookup_alias reports a miss with rc 1" "got rc: $_rc"
    fi

    # An alias whose target contains shell metacharacters must round-trip as
    # data through the shared lookup (the ssh-menu path relies on this).
    reset_case
    write_hosts "evil host;echoPWNED\n"
    _out=$(. "$LIB"; sshk_lookup_alias "$HOSTS_CONF" evil && printf '%s' "$SSHK_ALIAS_HOST")
    if [ "$_out" = "host;echoPWNED" ]; then
        ok "sshk_lookup_alias returns metacharacter targets verbatim"
    else
        fail "sshk_lookup_alias returns metacharacter targets verbatim" "got: $_out"
    fi
fi

echo "== help & first-run ergonomics =="

reset_case
write_hosts "myserver admin@192.168.1.10\nwork dev@work.example.com:2222\n"

# -h/--help are handled by the wrapper itself (never forwarded to dbclient),
# exit 0, and list the user's saved aliases so help doubles as a host list.
"$BIN/ssh" -h > "$SANDBOX/help.txt" 2>&1
_rc=$?
assert_rc "ssh -h exits 0" "0" "$_rc"
if grep -q "Usage: ssh" "$SANDBOX/help.txt"; then
    ok "ssh -h prints usage"
else
    fail "ssh -h prints usage" "output was:" "$(cat "$SANDBOX/help.txt")"
fi
if grep -q "myserver" "$SANDBOX/help.txt" && grep -q "work" "$SANDBOX/help.txt"; then
    ok "ssh -h lists saved aliases"
else
    fail "ssh -h lists saved aliases" "output was:" "$(cat "$SANDBOX/help.txt")"
fi
if [ ! -s "$SSHK_TEST_LOG" ]; then
    ok "ssh -h does not invoke dbclient"
else
    fail "ssh -h does not invoke dbclient" "dbclient log: $(cat "$SSHK_TEST_LOG")"
fi

"$BIN/ssh" --help >/dev/null 2>&1
assert_rc "ssh --help exits 0" "0" "$?"

# No target and no terminal -> usage + exit 1. The interactive picker is only
# offered on a tty (and only when ssh-menu is installed next to the wrapper),
# so scripted/no-tty callers still get a predictable error.
"$BIN/ssh" < /dev/null > "$SANDBOX/noargs.txt" 2>&1
assert_rc "ssh with no args (no tty) exits 1" "1" "$?"
if grep -q "Usage: ssh" "$SANDBOX/noargs.txt"; then
    ok "ssh with no args prints usage"
else
    fail "ssh with no args prints usage" "output was:" "$(cat "$SANDBOX/noargs.txt")"
fi
if grep -q 'exec "$BINDIR/ssh-menu"' "$ROOT/extensions/sshk/bin/ssh" && \
   grep -q '\[ -t 0 \]' "$ROOT/extensions/sshk/bin/ssh"; then
    ok "ssh offers the quick-connect picker on a terminal"
else
    fail "ssh offers the quick-connect picker on a terminal" \
        "expected '[ -t 0 ]' + 'exec \"\$BINDIR/ssh-menu\"' in the ssh wrapper"
fi

"$BIN/ssh-tailscale" -h >/dev/null 2>&1
assert_rc "ssh-tailscale -h exits 0" "0" "$?"
"$BIN/scp-tailscale" -h >/dev/null 2>&1
assert_rc "scp-tailscale -h exits 0" "0" "$?"

echo "== scp wrappers =="

reset_case
"$BIN/scp" file.txt user@example.com:/tmp/file.txt >/dev/null 2>&1
assert_dbclient_args "scp forwards files when no key exists yet" \
    scp file.txt user@example.com:/tmp/file.txt

reset_case
: > "$NATIVE_KEY"
"$BIN/scp" file.txt user@example.com:/tmp/file.txt >/dev/null 2>&1
assert_dbclient_args "scp injects native key when present" \
    scp -i "$NATIVE_KEY" file.txt user@example.com:/tmp/file.txt

reset_case
FAKE_NO_SCP=1 "$BIN/scp" a b:/c >/dev/null 2>&1
assert_rc "scp detects binary without SCP support (exit 1)" "1" "$?"

reset_case
"$BIN/scp-tailscale" >/dev/null 2>&1
assert_rc "scp-tailscale without args -> usage error (exit 1)" "1" "$?"

reset_case
"$BIN/scp-tailscale" file.txt user@myhost.example:/tmp/file.txt >/dev/null 2>&1
assert_dbclient_args "scp-tailscale delegates through ssh-tailscale (-S)" \
    scp -S "$BIN/ssh-tailscale" file.txt user@myhost.example:/tmp/file.txt

reset_case
: > "$BIN/kindle_work_key"
"$BIN/scp-tailscale" -i work -P 2223 file.txt u@10.0.0.5:/dst >/dev/null 2>&1
assert_dbclient_args "scp-tailscale forwards user -i/-P to dropbear-scp" \
    scp -S "$BIN/ssh-tailscale" -i work -P 2223 file.txt u@10.0.0.5:/dst

reset_case
: > "$BIN/kindle_native_key"
"$BIN/scp-tailscale" -P 2223 file.txt u@10.0.0.5:/dst >/dev/null 2>&1
assert_dbclient_args "scp-tailscale -P forwards port and native key" \
    scp -S "$BIN/ssh-tailscale" -i "$NATIVE_KEY" -P 2223 file.txt u@10.0.0.5:/dst

reset_case
write_hosts "work_server u@10.0.0.5:2223 workkey\n"
: > "$BIN/kindle_native_key"
: > "$BIN/kindle_workkey_key"
"$BIN/scp-tailscale" file.txt work_server >/dev/null 2>&1
assert_dbclient_args "scp-tailscale resolves alias to user@host + port + key" \
    scp -S "$BIN/ssh-tailscale" -i "$NATIVE_KEY" -P 2223 -i workkey file.txt u@10.0.0.5

reset_case
# No native key, no alias; just an explicit absolute-path -i (passes through).
"$BIN/scp-tailscale" -i /absolute/path/key file u@10.0.0.5:/dst >/dev/null 2>&1
assert_dbclient_args "scp-tailscale -i absolute path passes through" \
    scp -S "$BIN/ssh-tailscale" -i /absolute/path/key file u@10.0.0.5:/dst

reset_case
# Boolean flags (-r, -C, -q, ...) must NOT eat the next argv slot.
"$BIN/scp-tailscale" -r -C dir/ u@10.0.0.5:/dst >/dev/null 2>&1
assert_dbclient_args "scp-tailscale boolean flags don't eat next argv" \
    scp -S "$BIN/ssh-tailscale" -r -C dir/ u@10.0.0.5:/dst

reset_case
# Value-consuming flag (-l 1000) must eat the next argv slot.
"$BIN/scp-tailscale" -l 1000 file u@10.0.0.5:/dst >/dev/null 2>&1
assert_dbclient_args "scp-tailscale -l keeps its argument" \
    scp -S "$BIN/ssh-tailscale" -l 1000 file u@10.0.0.5:/dst

reset_case
# Download case: target is a local path, source is the remote one.
"$BIN/scp-tailscale" user@10.0.0.5:/src ./localdir >/dev/null 2>&1
assert_dbclient_args "scp-tailscale download uses last positional as target" \
    scp -S "$BIN/ssh-tailscale" user@10.0.0.5:/src ./localdir

reset_case
# Multiple sources, single target.
"$BIN/scp-tailscale" src1 src2 src3 user@10.0.0.5:/dst >/dev/null 2>&1
assert_dbclient_args "scp-tailscale handles multiple sources" \
    scp -S "$BIN/ssh-tailscale" src1 src2 src3 user@10.0.0.5:/dst

echo "== ssh-menu wrapper =="

# ssh-menu's alias lookup used to use `eval`, which meant any shell-meta in
# a hosts.conf line (e.g. `"evil; rm -rf /tmp"`) was at risk of being
# evaluated the moment the user picked that alias. The new implementation
# stores the alias list in a newline-separated variable and looks it up with
# `sed -n "${n}p"`, which preserves the value verbatim.

MENU_SANDBOX="$SANDBOX/menu"
mkdir -p "$MENU_SANDBOX/bin" "$MENU_SANDBOX"
for f in ssh-menu ssh-tailscale sshk-common.sh; do
    cp "$ROOT/extensions/sshk/bin/$f" "$MENU_SANDBOX/bin/"
    chmod +x "$MENU_SANDBOX/bin/$f"
done
# Stub `ssh` so we can assert exactly what argv ssh-menu passes to it.
cat > "$MENU_SANDBOX/bin/ssh" <<'STUBEOF'
#!/bin/sh
echo "$*" >> "$SSHK_TEST_LOG"
STUBEOF
chmod +x "$MENU_SANDBOX/bin/ssh"
# Keep ssh-menu's confirmation pauses instant during tests.
printf '#!/bin/sh\nexit 0\n' > "$MENU_SANDBOX/bin/sleep"
chmod +x "$MENU_SANDBOX/bin/sleep"
# hosts.conf with a comment, blank lines, and three aliases. The middle
# alias contains shell metacharacters (single quotes, semicolons, spaces)
# that the old `eval`-based lookup would have executed if selected. The new
# implementation must treat the alias as data and pass it verbatim to ssh.
# (Note: `awk '{print $1}'` truncates at the first whitespace, so the alias
# itself must not contain spaces — this is a limitation of the alias
# format, not of the lookup.)
cat > "$MENU_SANDBOX/hosts.conf" <<'CONF'
# This is a comment line, ignored.

alpha admin@10.0.0.1
'evil;rm-rf/tmp' admin@10.0.0.2
gamma root@10.0.0.3
CONF

reset_case
# Choice "2" should select the second alias verbatim and exec ssh with it.
echo "2" | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" >/dev/null 2>&1
if [ "$(cat "$SSHK_TEST_LOG" 2>/dev/null)" = "'evil;rm-rf/tmp'" ]; then
    ok "ssh-menu picks aliases by index without eval"
else
    fail "ssh-menu picks aliases by index without eval" "got: $(cat "$SSHK_TEST_LOG" 2>/dev/null)"
fi
# Verify the sandbox is still present (the literal alias must not have been
# evaluated as a shell command).
if [ -d "$MENU_SANDBOX" ]; then
    ok "ssh-menu does not eval shell metacharacters in alias names"
else
    fail "ssh-menu does not eval shell metacharacters in alias names" "sandbox was removed"
fi

reset_case
# Out-of-range numeric choice should print Invalid and re-exec; ssh is never
# invoked, so the log stays empty.
echo "99" | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" >/dev/null 2>&1
if [ ! -s "$SSHK_TEST_LOG" ]; then
    ok "ssh-menu rejects out-of-range numeric choice"
else
    fail "ssh-menu rejects out-of-range numeric choice" "ssh was invoked with: $(cat "$SSHK_TEST_LOG")"
fi

reset_case
# Letter choice "q" should quit (no ssh invocation).
echo "q" | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" >/dev/null 2>&1
if [ ! -s "$SSHK_TEST_LOG" ]; then
    ok "ssh-menu quits on q"
else
    fail "ssh-menu quits on q" "ssh was invoked with: $(cat "$SSHK_TEST_LOG")"
fi

# Forgiving input: a full alias name, or a raw user@host target, may be typed
# at the prompt instead of only its menu number.
reset_case
printf 'gamma\n' | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" >/dev/null 2>&1
if [ "$(cat "$SSHK_TEST_LOG" 2>/dev/null)" = "gamma" ]; then
    ok "ssh-menu accepts an alias name typed in full"
else
    fail "ssh-menu accepts an alias name typed in full" "got: $(cat "$SSHK_TEST_LOG" 2>/dev/null)"
fi

reset_case
printf 'user@10.1.2.3\n' | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" >/dev/null 2>&1
if [ "$(cat "$SSHK_TEST_LOG" 2>/dev/null)" = "user@10.1.2.3" ]; then
    ok "ssh-menu accepts a raw user@host target"
else
    fail "ssh-menu accepts a raw user@host target" "got: $(cat "$SSHK_TEST_LOG" 2>/dev/null)"
fi

# Add-host must reject an alias that would corrupt the whitespace-separated
# hosts.conf format, and must not write it.
_cp_before=$(cat "$MENU_SANDBOX/hosts.conf")
_aout=$(printf 'a\nbad name\n' | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" 2>&1)
case "$_aout" in
    *"may only contain"*) ok "ssh-menu rejects an alias with spaces" ;;
    *) fail "ssh-menu rejects an alias with spaces" "output: $_aout" ;;
esac
if [ "$(cat "$MENU_SANDBOX/hosts.conf")" = "$_cp_before" ]; then
    ok "ssh-menu does not write a rejected alias"
else
    fail "ssh-menu does not write a rejected alias" "hosts.conf changed"
fi

# Happy path: a well-formed alias is appended to hosts.conf.
reset_case
printf 'a\nnewhost\nadmin@10.9.9.9\n\n' | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" >/dev/null 2>&1
if grep -q '^newhost admin@10.9.9.9$' "$MENU_SANDBOX/hosts.conf"; then
    ok "ssh-menu appends a valid host alias"
else
    fail "ssh-menu appends a valid host alias" "hosts.conf: $(cat "$MENU_SANDBOX/hosts.conf")"
fi
# Restore the original alias set for the render checks below.
grep -v '^newhost admin@10.9.9.9$' "$MENU_SANDBOX/hosts.conf" > "$MENU_SANDBOX/hosts.conf.tmp"
mv "$MENU_SANDBOX/hosts.conf.tmp" "$MENU_SANDBOX/hosts.conf"

# The menu must render the saved aliases with a stable index (so one keypress
# connects) and print a metacharacter alias verbatim, not evaluated.
_out=$(printf 'q\n' | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" 2>&1)
case "$_out" in
    *"[1] alpha"*) ok "ssh-menu renders saved aliases with an index" ;;
    *) fail "ssh-menu renders saved aliases with an index" "output:" "$_out" ;;
esac
case "$_out" in
    *"'evil;rm-rf/tmp'"*) ok "ssh-menu renders metacharacter aliases verbatim" ;;
    *) fail "ssh-menu renders metacharacter aliases verbatim" "output:" "$_out" ;;
esac

# A first-time user (no hosts.conf entries) should be told how to add one.
rm -f "$MENU_SANDBOX/hosts.conf"
_out=$(printf 'q\n' | PATH="$MENU_SANDBOX/bin:$PATH" SSHK_TEST_LOG="$SSHK_TEST_LOG" "$MENU_SANDBOX/bin/ssh-menu" 2>&1)
case "$_out" in
    *"No saved hosts"*) ok "ssh-menu guides an empty hosts.conf" ;;
    *) fail "ssh-menu guides an empty hosts.conf" "output:" "$_out" ;;
esac

echo "== server scripts =="

# The inbound-server scripts share server-common.sh (mirroring the client's
# sshk-common.sh) so the port, the pidfile path and the process-match pattern
# live in exactly one place. The pattern must be a `dropbear .*-p <PORT>` token
# match: under qemu-arm-static the daemon argv begins with `qemu-arm-static`,
# so we cannot anchor on `dropbearmulti`, and the phrase is specific enough not
# to false-positive on the wrapper shell.
if grep -q 'SSHK_DROPBEAR_PATTERN="dropbear .*-p \$SSHK_SERVER_PORT"' extensions/sshk/bin/server-common.sh && \
   grep -q 'SSHK_SERVER_PORT="2222"' extensions/sshk/bin/server-common.sh; then
    ok "server-common.sh defines the sshk dropbear pattern + port"
else
    fail "server-common.sh defines the sshk dropbear pattern + port" \
        "expected the dropbear pattern and port in server-common.sh"
fi

for s in server-start.sh server-stop.sh server-toggle.sh server-status.sh; do
    if grep -q 'server-common.sh' "extensions/sshk/bin/$s"; then
        ok "$s sources server-common.sh"
    else
        fail "$s sources server-common.sh" "expected a '.' source of server-common.sh"
    fi
done

# server-start.sh must overwrite the pidfile with the LIVE daemon PID (the
# wrapper PID goes stale at once because dropbear double-forks), and must be
# idempotent so server-toggle.sh cannot race a second daemon onto the port.
if grep -q 'sshk_server_live_pid' extensions/sshk/bin/server-start.sh && \
   grep -q 'echo "$LIVE_PID" > "$SSHK_SERVER_PIDFILE"' extensions/sshk/bin/server-start.sh && \
   grep -q 'is already running' extensions/sshk/bin/server-start.sh; then
    ok "server-start.sh records the live daemon PID and is idempotent"
else
    fail "server-start.sh records the live daemon PID and is idempotent" \
        "expected a live-PID pidfile write and an already-running guard"
fi

# server-stop.sh must kill only our dropbear (via the shared pattern).
if grep -qE 'pkill -f "\$SSHK_DROPBEAR_PATTERN"|pgrep -f "\$SSHK_DROPBEAR_PATTERN"' extensions/sshk/bin/server-stop.sh; then
    ok "server-stop.sh kills only the sshk dropbear process"
else
    fail "server-stop.sh kills only the sshk dropbear process" \
        "expected pkill/pgrep -f \"\$SSHK_DROPBEAR_PATTERN\" in server-stop.sh"
fi

# server-status.sh must run cleanly and report the state plus the connect hint.
# Stub pgrep to report "no match" so the check is deterministic and never
# writes a pidfile or touches a real process.
_ss_stub=$(mktemp -d "${TMPDIR:-/tmp}/sshk-pgrep.XXXXXX")
printf '#!/bin/sh\nexit 1\n' > "$_ss_stub/pgrep"
chmod +x "$_ss_stub/pgrep"
_ss_out=$(PATH="$_ss_stub:$PATH" sh extensions/sshk/bin/server-status.sh 2>&1); _ss_rc=$?
rm -rf "$_ss_stub"
assert_rc "server-status.sh exits 0" "0" "$_ss_rc"
case "$_ss_out" in
    *"SSH server"*) ok "server-status.sh reports server state" ;;
    *) fail "server-status.sh reports server state" "output: $_ss_out" ;;
esac

# eips-refresh is invoked directly by ssh-menu ("Refresh E-Ink Screen") but was
# the only script in bin/ checked in without the executable bit, so that menu
# option failed on a fresh install. Guard the mode.
if [ -x "$ROOT/extensions/sshk/bin/eips-refresh" ]; then
    ok "eips-refresh is executable (ssh-menu invokes it directly)"
else
    fail "eips-refresh is executable (ssh-menu invokes it directly)" \
        "eips-refresh must ship with the executable bit set"
fi

# uninstall.sh must verify the /root/.ssh symlink target before removing it.
# Otherwise we would happily clobber a symlink the user set up for some
# other purpose (e.g. an OpenSSH home on a developer Kindle).
if grep -q 'EXPECTED_TARGET' extensions/sshk/bin/uninstall.sh && \
   grep -q 'ACTUAL_TARGET' extensions/sshk/bin/uninstall.sh; then
    ok "uninstall.sh only removes the sshk known_hosts symlink"
else
    fail "uninstall.sh only removes the sshk known_hosts symlink" \
        "expected EXPECTED_TARGET / ACTUAL_TARGET guard in uninstall.sh"
fi

# authorize-server.sh must pipe the public key through stdin so that a
# malicious or corrupted key text containing shell metacharacters cannot
# inject commands on the remote host. We use a string-grep rather than
# searching for the literal `<<'REMOTE'` here-doc opener: the heredoc
# opener itself contains a `<<` that bash/dash will (incorrectly) parse as
# the start of a here-document inside our double-quoted grep argument.
if grep -q 'sshk_pending_key.pub' authorize-server.sh && \
   grep -q 'REMOTE' authorize-server.sh && \
   ! grep -q "grep -qxF '\$PUBKEY_CONTENT" authorize-server.sh && \
   ! grep -q "echo '\$PUBKEY_CONTENT" authorize-server.sh; then
    ok "authorize-server.sh does not interpolate PUBKEY_CONTENT into a shell command"
else
    fail "authorize-server.sh does not interpolate PUBKEY_CONTENT into a shell command" \
        "expected heredoc-based ssh invocation without \$PUBKEY_CONTENT interpolation"
fi

# uninstall.sh now requires explicit confirmation (typed YES) so a stray tap
# in the KUAL menu cannot clobber the install. We test the three contract
# paths here in the host sandbox.
if [ -x "$BIN/../bin/uninstall.sh" ]; then
    UNINSTALL_SH="$BIN/../bin/uninstall.sh"
elif [ -x "$ROOT/extensions/sshk/bin/uninstall.sh" ]; then
    UNINSTALL_SH="$ROOT/extensions/sshk/bin/uninstall.sh"
else
    fail "uninstall.sh exists and is executable" "missing $ROOT/extensions/sshk/bin/uninstall.sh"
    UNINSTALL_SH=""
fi
if [ -n "${UNINSTALL_SH:-}" ]; then
    # Path 1: wrong answer -> abort with non-zero exit.
    RC=$(printf 'nope\n' | SSHK_US_ROOT="$SANDBOX" "$UNINSTALL_SH" >/dev/null 2>&1; echo $?)
    if [ "$RC" -ne 0 ]; then
        ok "uninstall.sh rejects non-YES answer"
    else
        fail "uninstall.sh rejects non-YES answer" "exit was 0"
    fi
    # Path 2: --force -> exits 0, runs the cleanup. We can't assert on
    # kterm.sh here because the script runs in-process and the eips helper
    # isn't available; just confirm --force returns 0.
    RC=$(SSHK_US_ROOT="$SANDBOX" "$UNINSTALL_SH" --force >/dev/null 2>&1; echo $?)
    if [ "$RC" -eq 0 ]; then
        ok "uninstall.sh --force proceeds without prompting"
    else
        fail "uninstall.sh --force proceeds without prompting" "exit was $RC"
    fi
    # Path 3: contract check — the script must gate the prompt on user
    # input, not auto-confirm.
    if grep -q 'if \[ "\$FORCE" -ne 1 \]' "$UNINSTALL_SH" && \
       grep -q 'read -r reply' "$UNINSTALL_SH" && \
       grep -q 'YES' "$UNINSTALL_SH"; then
        ok "uninstall.sh has explicit YES confirmation gate"
    else
        fail "uninstall.sh has explicit YES confirmation gate" \
            "expected FORCE check + read -r reply + YES comparison"
    fi
fi

# ---------------------------------------------------------------- summary ---
echo ""
echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'failed tests:%s\n' "$FAILED_NAMES"
    exit 1
fi
exit 0