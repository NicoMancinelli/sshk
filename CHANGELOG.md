# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

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
