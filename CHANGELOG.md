# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.3] - 2026-08-24

### Added
- Kindle environment simulator (`tests/kindle-sim/run-sim.sh`): all 9 KUAL menu actions executed end-to-end in CI, real ARM binary under qemu-user emulation including a live inbound-server banner probe on port 2222

### Fixed
- `server-start.sh`: "already running?" detection no longer relies on a stale pidfile PID (Dropbear double-forks); falls back to pgrep on our port
- `install.sh`/`showkey.sh`/`genkey.sh`/`uninstall.sh`/`kterm-landscape.sh`: USB-root paths honor `SSHK_US_ROOT` override; extension-relative paths derive from script location instead of hardcoding `/mnt/us`

## [1.2] - 2026-08-24

### Security
- **Inbound server**: `server-start.sh` no longer passes Dropbear's `-B` (blank-password logins). Kindle root accounts often have no password; inbound access is now strictly public-key based (`authorize-server.sh`). Rebuilt binaries additionally compile password auth out entirely.

### Added
- `SUPPORTED-DEVICES.md`: device matrix covering post-2020 Kindles — Paperwhite 5/6, basic 2022/2024, Scribe 1/3, Colorsoft — with architecture rationale (static soft-float vs hard-float rootfs) and confirmation tracker issues
- CI: binary portability gate (static ARMv5 soft-float ELF attributes) and KUAL manifest cross-reference check (every `menu.json` action must exist and be executable)

### Fixed
- `install.sh` no longer reports success when the kterm PATH patch silently fails; the patch now works with any shebang, preserves file permissions, and is verified before claiming success

### Changed
- Build pipeline pins `-march=armv5t` explicitly for maximum device compatibility

## [1.1.1] - 2026-08-23

### Fixed
- **Security**: `authorize-server.sh` no longer falls back to uploading the Kindle's *private* key to the remote server when no `.pub` file is found. It now extracts the public half locally with `ssh-keygen -y` first
- CI: resolved all ShellCheck failures (`SC2034`, `SC2181`, `SC2317`) so the pipeline passes on `main`

### Added
- Functional test harness (`tests/run-tests.sh`, 20 assertions) wired into CI, covering wrapper argv behavior: host aliases, port expansion, named keys, first-run key generation, screensaver inhibit/restore, Tailscale ProxyCommand construction, and scp delegation
- Reproducible Docker cross-compile for `dropbearmulti` (`build/build-dropbear.sh`) with pinned musl toolchain, QEMU smoke test, and a manual CI validation workflow
- `DROPBEAR_VERSION` pinning the shipped binary's release (2020.81)
- `LICENSE` (MIT) for the project
- `DROPBEAR-LICENSE` — verbatim license notices for the bundled Dropbear 2020.81 binary, now also shipped in release zips

## [1.1] - 2026-08-18

### Added
- **SCP support**: `scp` and `scp-tailscale` wrappers for file transfer (requires SCP-enabled dropbearmulti)
- **Custom port support**: `ssh-tailscale` now accepts `-p port` for non-standard SSH ports
- **Known hosts persistence**: Installer sets up a writable known_hosts directory via symlink from `/root/.ssh` to `/mnt/us/extensions/sshk/.ssh/`, removing the need to auto-accept all host keys
- **Multiple SSH keys**: `genkey.sh` accepts an optional name argument to create multiple named keys (e.g., `genkey.sh work` creates `kindle_work_key`)
- **Host aliases**: `hosts.conf` config file for saving connection shortcuts (e.g., `ssh myserver` expands to `ssh admin@192.168.1.10:2222`)
- **Version tracking**: `VERSION` file and "About sshk" menu item displaying version, Dropbear version, key count, and known hosts status
- **Key listing**: "List SSH Keys" menu item and `listkeys.sh` script showing all keys with fingerprints
- **Fingerprint display**: `showkey.sh` now displays the key fingerprint on the e-ink screen and prints the full public key to stdout
- **Interactive Quick-Connect Menu**: `bin/ssh-menu` and `bin/sshk` CLI command for 1-keypress connection selection
- **WiFi Keepalive & Sleep Inhibitor**: Automated `lipc-set-prop` power management in `ssh` and `ssh-tailscale` to keep WiFi active and prevent Kindle sleeping during SSH sessions
- **Inbound SSH Server (2-in-1)**: `bin/server-start.sh` and `bin/server-stop.sh` scripts for running Dropbear SSH server on port 2222 with KUAL menu integration
- **Landscape Terminal Preset**: `bin/kterm-landscape.sh` for 1-click launch of landscape terminal with auto-launched `ssh-menu`
- **1-Click Desktop Installers**: `install-to-kindle.sh` (macOS/Linux) and `install-to-kindle.bat` (Windows) for zero-friction USB installation and kterm pre-configuration
- **1-Command Server Authorization**: `authorize-server.sh` script to automatically detect Kindle's public key and install it to the remote server's `authorized_keys` with a single command
- **Self-Healing Wrappers**: `ssh` and `ssh-tailscale` auto-generate default `ed25519` keys on first run if not already created
- **1-Tap KUAL Setup**: Revamped `install.sh` and KUAL menu item to provide instant 1-tap installation and multi-line e-ink feedback
- **`QUICKSTART.md`**: 60-second quickstart guide for rapid setup
- `ARCHITECTURE.md` — comprehensive project architecture documentation
- `CONTRIBUTING.md` — contributor guide with cross-compilation and release instructions
- `.gemini/AGENTS.md` — AI agent context file for automated coding assistants

### Changed
- `ssh` wrapper now checks if `/root/.ssh/known_hosts` is writable and only uses `-y` (auto-accept) as a fallback
- `ssh` and `ssh-tailscale` resolve host aliases from `hosts.conf` before connecting
- `ssh` supports `-i <keyname>` to select a specific named key
- `install.sh` displays version during installation and sets up writable known hosts
- `uninstall.sh` cleans up the `/root/.ssh` symlink during removal
- `menu.json` expanded from 4 to 6 items

## [1.0] - 2025-01-01

### Added
- Initial release
- Statically compiled `dropbearmulti` ARM binary (dbclient + dropbearkey)
- `ssh` wrapper with auto host key accept and identity key injection
- `ssh-tailscale` wrapper for Tailscale userspace networking via `tailscale nc`
- KUAL menu integration (Install, Generate Key, Export Key, Uninstall)
- Automated kterm PATH patching
- Ed25519 SSH key generation and public key export
