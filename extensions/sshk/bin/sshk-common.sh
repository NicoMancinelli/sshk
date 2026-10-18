#!/bin/sh
# sshk-common.sh - shared helpers for the sshk client wrappers.
#
# Sourced (never executed) by the `ssh`, `ssh-tailscale` and `scp-tailscale`
# wrappers so the security-relevant known_hosts probe, the hosts.conf alias
# lookup, the identity-key mapping and the power-management trap live in
# exactly one place. A fix to any of them then lands in every wrapper at once,
# which is what we want: the v1.5 audit found the wrappers had drifted apart
# (e.g. ssh-tailscale auto-accepting host keys while ssh verified them).
#
# The Kindle runs BusyBox /bin/sh, so everything here is POSIX and avoids
# bashisms. Callers set BINDIR (and CONF for the alias helper) before sourcing.
#
# Functions that "return" more than one value (sshk_lookup_alias,
# sshk_native_key_opts) do so by assigning globals. They must therefore be
# called directly, not inside a $(...) command substitution, or the
# assignments would be lost with the subshell.

# sshk_known_hosts_flags
#   Echo the extra dbclient flag for host-key handling: `-y` when
#   /root/.ssh/known_hosts cannot be created or written (auto-accept
#   fallback), and nothing otherwise. Every wrapper runs this same probe so
#   LAN and Tailscale connections share one host-key posture; skipping
#   verification on a Tailnet (personal devices, often no unique usernames)
#   would be the worst possible place to do it.
#   SSHK_TEST_FORCE_AUTO_ACCEPT=1 forces the fallback so tests can exercise it
#   deterministically off-device.
sshk_known_hosts_flags() {
    if [ "${SSHK_TEST_FORCE_AUTO_ACCEPT:-0}" = "1" ]; then
        echo "-y"
    elif [ -w "/root/.ssh/known_hosts" ] || touch /root/.ssh/known_hosts 2>/dev/null; then
        :
    else
        echo "-y"
    fi
}

# sshk_identity_path BINDIR NAME
#   Map a short key name to its on-device file: <BINDIR>/kindle_<NAME>_key.
sshk_identity_path() {
    printf '%s\n' "$1/kindle_$2_key"
}

# sshk_map_identity KEYARG BINDIR
#   Resolve a user-supplied `-i` value. A value containing a slash is a
#   literal path and passes through; a bare name is expanded with
#   sshk_identity_path (so `-i work` -> <BINDIR>/kindle_work_key).
sshk_map_identity() {
    case "$1" in
        */*) printf '%s\n' "$1" ;;
        *) sshk_identity_path "$2" "$1" ;;
    esac
}

# sshk_lookup_alias CONF NAME
#   Look NAME up in CONF (hosts.conf). On a match, set:
#     SSHK_ALIAS_HOST  target with any :port stripped (user@host / host)
#     SSHK_ALIAS_PORT  port parsed off a host:port target, or empty
#     SSHK_ALIAS_KEY   key name from the third field, or empty
#   and return 0. Return 1 when CONF is missing or NAME has no entry. Comment
#   and blank lines are skipped.
#   NAME is matched as data (`awk -v a=...`), never eval'd, so an alias whose
#   text contains shell metacharacters cannot execute code when selected.
sshk_lookup_alias() {
    _conf="$1"
    _name="$2"
    [ -f "$_conf" ] || return 1
    _match=$(grep -v '^[[:space:]]*#' "$_conf" | grep -v '^[[:space:]]*$' | awk -v a="$_name" '$1 == a {print; exit}')
    [ -n "$_match" ] || return 1
    SSHK_ALIAS_HOST=$(printf '%s\n' "$_match" | awk '{print $2}')
    # SSHK_ALIAS_KEY / SSHK_ALIAS_PORT are this function's return values; the
    # sourcing wrapper reads them, which shellcheck cannot see from here.
    # shellcheck disable=SC2034
    SSHK_ALIAS_KEY=$(printf '%s\n' "$_match" | awk '{print $3}')
    SSHK_ALIAS_PORT=""
    case "$SSHK_ALIAS_HOST" in
        *:*)
            # shellcheck disable=SC2034
            SSHK_ALIAS_PORT="${SSHK_ALIAS_HOST##*:}"
            SSHK_ALIAS_HOST="${SSHK_ALIAS_HOST%:*}"
            ;;
    esac
    return 0
}

# sshk_native_key_opts BINDIR
#   Ensure the default identity key exists (generating and exporting it on
#   first run) and set SSHK_NATIVE_OPTS to `-i <key>` when the key is
#   available, empty otherwise. Progress chatter stays on stdout, so callers
#   append SSHK_NATIVE_OPTS to their flags rather than capturing the output.
sshk_native_key_opts() {
    _bindir="$1"
    _key="$_bindir/kindle_native_key"
    # shellcheck disable=SC2034  # read by the sourcing wrapper
    SSHK_NATIVE_OPTS=""
    if [ ! -f "$_key" ]; then
        echo "sshk: First run detected - generating default SSH key..."
        "$_bindir/dropbearkey" -t ed25519 -f "$_key" >/dev/null 2>&1
        if [ -f "$_key" ]; then
            "$_bindir/showkey.sh" "native" >/dev/null 2>&1
        fi
    fi
    if [ -f "$_key" ]; then
        # shellcheck disable=SC2034  # read by the sourcing wrapper
        SSHK_NATIVE_OPTS="-i $_key"
    fi
}

# sshk_inhibit_screensaver
#   Keep the device awake for the lifetime of the caller: powerd otherwise
#   blanks the screen and shuts off wlan0 after ~10 minutes of inactivity,
#   which drops long-lived SSH sessions. No-op when lipc-set-prop is absent
#   (non-Kindle sandbox). Restores the previous state on exit.
sshk_inhibit_screensaver() {
    command -v lipc-set-prop >/dev/null 2>&1 || return 0
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null || true
    trap sshk_restore_screensaver EXIT INT TERM HUP
}

# sshk_restore_screensaver - trap handler that re-enables power management.
sshk_restore_screensaver() {
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null || true
}
