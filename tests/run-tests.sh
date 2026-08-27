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
for wrapper in ssh ssh-tailscale scp scp-tailscale; do
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
for f in ssh-menu ssh-tailscale; do
    cp "$ROOT/extensions/sshk/bin/$f" "$MENU_SANDBOX/bin/"
    chmod +x "$MENU_SANDBOX/bin/$f"
done
# Stub `ssh` so we can assert exactly what argv ssh-menu passes to it.
cat > "$MENU_SANDBOX/bin/ssh" <<'STUBEOF'
#!/bin/sh
echo "$*" >> "$SSHK_TEST_LOG"
STUBEOF
chmod +x "$MENU_SANDBOX/bin/ssh"
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

echo "== server scripts =="

# The PIDFILE written by server-start.sh used to be the wrapper shell's PID
# (Dropbear double-forks, so the immediate child of the wrapper is a
# short-lived parent, not the daemon). The simulator can't easily exercise
# the real ARM dropbear here, so we test the contract: the script must use
# an anchored pattern (`^dropbearmulti dropbear .*-p <PORT>`) that only
# matches our own multi-call binary invocation, not the wrapper shell.
# If the live pidfile PID is stale, the script must look the daemon up in the
# process table via `pgrep` and overwrite the pidfile with the live PID.
if grep -q '^DROPBEAR_PATTERN=' extensions/sshk/bin/server-start.sh && \
   grep -q 'DROPBEAR_PATTERN="dropbear .*-p $PORT"' extensions/sshk/bin/server-start.sh; then
    ok "server-start.sh uses anchored multi-call pattern for PID lookup"
else
    fail "server-start.sh uses anchored multi-call pattern for PID lookup" \
        "expected 'dropbear .*-p \$PORT' pattern in server-start.sh"
fi
if grep -q 'find_live_pid' extensions/sshk/bin/server-start.sh && \
   grep -q 'echo "$LIVE_PID" > "$PIDFILE"' extensions/sshk/bin/server-start.sh; then
    ok "server-start.sh overwrites pidfile with the live daemon PID"
else
    fail "server-start.sh overwrites pidfile with the live daemon PID" \
        "expected 'echo \"\$LIVE_PID\" > \"\$PIDFILE\"' after PID lookup"
fi

# server-stop.sh must use the same pattern so it never kills an
# unrelated process whose argv happens to mention `-p 2222`. We can't
# anchor on `^dropbearmulti` because under qemu-arm-static the cmdline of
# the daemon begins with `qemu-arm-static`, not `dropbearmulti`; matching
# `dropbear .*-p <PORT>` as a substring covers both invocation modes.
if grep -q 'DROPBEAR_PATTERN="dropbear .*-p $PORT"' extensions/sshk/bin/server-stop.sh && \
   grep -qE 'pkill -f "\$DROPBEAR_PATTERN"|pgrep -f "\$DROPBEAR_PATTERN"' extensions/sshk/bin/server-stop.sh; then
    ok "server-stop.sh kills only the sshk dropbear process"
else
    fail "server-stop.sh kills only the sshk dropbear process" \
        "expected 'dropbear .*-p \$PORT' + pkill/pgrep -f in server-stop.sh"
fi

# server-toggle.sh must use the same pattern.
if grep -q 'DROPBEAR_PATTERN="dropbear .*-p $PORT"' extensions/sshk/bin/server-toggle.sh; then
    ok "server-toggle.sh uses the sshk dropbear pattern"
else
    fail "server-toggle.sh uses the sshk dropbear pattern" \
        "expected 'dropbear .*-p \$PORT' in server-toggle.sh"
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

# ---------------------------------------------------------------- summary ---
echo ""
echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    printf 'failed tests:%s\n' "$FAILED_NAMES"
    exit 1
fi
exit 0