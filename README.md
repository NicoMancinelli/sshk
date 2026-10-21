# sshk: Kindle KTerm SSH Client Extension

`sshk` is an easily installable KUAL (Kindle Unified Application Launcher) extension that configures and runs a statically-compiled SSH client (`dbclient`) and SCP inside `kterm` (the Kindle terminal emulator) on jailbroken Amazon Kindle devices.

Normally, Kindle devices do not have an SSH client installed, and compiling one statically with standard toolchains leads to library conflicts and crashes. `sshk` solves this by bundling a fully static, standalone `dropbearmulti` ARM binary.

## Features

- **Interactive Quick-Connect Menu**: Type `ssh` (or `sshk`) in kterm to open a numbered connection menu — connect with 1 keypress without typing long hostnames.
- **WiFi Keepalive & Sleep Inhibitor**: Automatically stops the Kindle from entering sleep/screensaver mode while an SSH session is active, preventing dropped connections.
- **Inbound SSH Server (2-in-1)**: Start or stop a Dropbear SSH server from KUAL on port 2222, check its status, and connect *into* your Kindle from your PC (public-key only).
- **Landscape Terminal Preset**: Open `kterm` pre-rotated into landscape mode with optimized font size from KUAL.
- **SCP File Transfer**: Transfer files to and from remote servers, including over Tailscale (`scp` and `scp-tailscale`).
- **Host Aliases**: Save frequently used connections in `hosts.conf` for quick access (e.g., `ssh myserver` instead of `ssh admin@192.168.1.10:2222`).
- **Tailscale Support**: Includes `ssh-tailscale` and `scp-tailscale` wrappers that automatically tunnel connections through Tailscale userspace mode (`tailscale nc`), bypassing the lack of native `tun.ko` routing. Install a Kindle-compatible Tailscale userspace client and daemon separately. sshk does not bundle, install, authenticate, or start Tailscale. Configure tailscaled with `--tun=userspace-networking` ([userspace guide](https://tailscale.com/docs/concepts/userspace-networking)), log in with your existing Tailscale setup, then use `tailscale nc` through sshk ([CLI reference](https://tailscale.com/docs/reference/tailscale-cli)). Actual Kindle/firmware compatibility depends on the Tailscale build and must be tested on the device.
- **Works across generations**: One static ARMv5 soft-float binary runs on every jailbroken Kindle — from early E-ink models through Paperwhite 5, Scribe, and the 2022/2024 basics. See [SUPPORTED-DEVICES.md](SUPPORTED-DEVICES.md).
- **Easy Key Management**: Generate `ed25519` SSH keys on the Kindle and export the public key to your Kindle's USB drive root (`kindle_ssh_key.pub`).
- **Multiple Keys**: Generate and manage multiple named SSH keys for different hosts or purposes (`listkeys.sh` and `ssh -i <name>`).
- **Custom Port Support**: Connect to SSH servers on non-standard ports (`-p port`), including over Tailscale tunnels.
- **Known Hosts**: Automatic setup of writable known hosts storage, so host keys are verified and remembered.
- **VFAT/FAT32 Compatibility**: Uses shell scripts instead of symbolic links to ensure the extension copies flawlessly over USB mass storage.

## Installation

### Method 1: 1-Click Desktop Installer (Recommended)

1. **Connect your Kindle** to your computer via USB (in drive mode).
2. **Run the installer from your computer**:
   - **macOS / Linux**:
     ```bash
     ./install-to-kindle.sh
     ```
   - **Windows**: Double-click `install-to-kindle.bat`
3. **Safely eject** your Kindle. Open `kterm` and start typing `ssh user@host`!

---

### Method 2: Manual Copy & Setup

1. **Connect your Kindle** to your computer via USB.
2. **Download & Extract** `sshk.zip` from [Releases](https://github.com/NicoMancinelli/sshk/releases).
3. **Copy `extensions` folder** into your Kindle's USB drive root (e.g. `/Volumes/Kindle/` or `E:\`).
4. **Safely eject** your Kindle.
5. **Run setup**:
   - Open KUAL on your Kindle.
   - Tap **sshk: SSH Client** -> **Setup & Maintenance** -> **Install / Repair**.
   - This automatically patches `kterm.sh`, enables known_hosts verification, generates an `ed25519` SSH key, and exports your public key!

---

### 🔑 1-Command Server Authorization

Want to connect to your remote server without typing a password every time?

1. Connect your Kindle to your computer via USB.
2. Run from your computer:
   ```bash
   ./authorize-server.sh user@your-server-ip
   ```
   *(Supports custom ports: `./authorize-server.sh user@your-server-ip -p 2222`)*
3. Done! The script finds your Kindle's public key and adds it to the server's `~/.ssh/authorized_keys` automatically.

## KUAL menu

Open **sshk: SSH Client** in KUAL:

- **Open SSH (Landscape)** opens the quick-connect menu in kterm.
- **Setup & Status** checks kterm, the default client key, its public export, computer access keys, and the server, with next steps for missing setup.
- **SSH Server (Port 2222)** contains **Server Status**, **Start Server**, and **Stop Server** for connections into your Kindle.
- **SSH Keys** contains **Connection Setup Help**, **List Keys**, **Create Default Key**, and **Export Default Public Key**. Export saves `kindle_ssh_key.pub` to the USB drive root; creating the default key keeps an existing key intact. Use kterm to create or export named keys.
- **Setup & Maintenance** contains **Install / Repair**, **About sshk**, and **Uninstall sshk**. Run **Install / Repair** after copying the extension to your Kindle; it also creates and exports the default key.

## Usage inside kterm

Open `kterm` from KUAL and run:

- **Simplest of all — just type `ssh`**: with no arguments it opens the
  quick-connect menu (or prints help when there is no terminal).
- **If you ever get stuck, add `-h`** (e.g. `ssh -h`, `ssh-tailscale -h`,
  `scp-tailscale -h`) for help that also lists your saved aliases.
- **For standard SSH connections**:
  ```bash
  ssh user@host
  ```
- **For Tailscale network connections** (after Tailscale status reports Running):
  ```bash
  ssh-tailscale user@host
  ```
- **For custom port connections**:
  ```bash
  ssh -p 2222 user@host
  ssh-tailscale -p 2222 user@host
  ```
- **For file transfers (SCP)**:
  ```bash
  scp localfile user@host:/remote/path
  scp-tailscale user@host:/remote/file ./local/path
  ```
- **Using host aliases** (see [Host Aliases](#host-aliases) below):
  ```bash
  ssh myserver
  ssh-tailscale tailnet-host
  ```

## Connecting *into* your Kindle (inbound server)

In KUAL, open **sshk: SSH Client** -> **SSH Server (Port 2222)**:

- **Start Server** — starts the Dropbear server (or reports that it is already running).
- **Stop Server** — stops the server; running it again leaves the server stopped.
- **Server Status** — shows whether it is running and the exact command to use.

With the server running, connect from your computer (the device screen shows your
IP and this exact line):

```bash
ssh root@<kindle-ip> -p 2222
```

To authorize your computer, connect the Kindle by USB and run from the extracted
sshk download:

```bash
./authorize-kindle.sh
# Or choose the mount path / computer public key explicitly:
./authorize-kindle.sh /path/to/Kindle ~/.ssh/id_rsa.pub
```

The default is `~/.ssh/id_ed25519.pub`. If you have no computer key, create one
with `ssh-keygen` first. The helper adds only its public key to the mounted
Kindle's `extensions/sshk/.ssh/authorized_keys`, preserving existing entries.
Eject USB, run **Setup & Maintenance > Install / Repair** once to activate
sshk's SSH storage, then **SSH Server > Start Server** and **Server Status**.

The two helpers serve separate directions: `authorize-server.sh user@server`
authorizes the **Kindle on a remote server**; `authorize-kindle.sh [MOUNT]`
authorizes **your computer on the Kindle**. Neither copies private keys.
KUAL's **SSH Keys > Connection Setup Help** includes both workflows.

## Host Aliases

Save frequently used connections in `extensions/sshk/hosts.conf`:

```
# Format: alias user@host[:port] [keyname] [direct|tailscale]
myserver admin@192.168.1.10
work dev@work.example.com:2222
lan pi@192.168.1.10 native direct
tailnet user@mypc work tailscale
```

Then connect with just:
```bash
ssh myserver           # → admin@192.168.1.10 with default key
ssh work               # → dev@work.example.com on port 2222
ssh tailnet            # → user@mypc using kindle_work_key
```

Aliases may include an optional fourth field to choose the transport:

```
lan pi@192.168.1.10 native direct
mesh pi@homeserver.tailnet.ts.net work tailscale
```

The fourth field is `direct` or `tailscale`; older three-column aliases remain
direct. In the TUI, choose a transport when adding/editing an alias. `ssh` and
`scp` dispatch saved Tailscale aliases automatically. Tailscale targets accept
DNS/MagicDNS names and IPv4; IPv6 literals are currently rejected by the Tailscale wrapper.

By default sshk finds `tailscale` in PATH or at
`/mnt/us/extensions/tailscale/bin/tailscale`. To use another executable/socket,
export `SSHK_TAILSCALE_BIN` and `SSHK_TAILSCALE_SOCKET` in kterm, or put the
absolute socket path on the first line of `extensions/sshk/tailscale.socket`.
KUAL > sshk > Tailscale > Status checks whether the daemon is running and logged
in; Setup Help shows the setup steps. sshk never starts Tailscale itself.


In the quick-connect menu, use **[a] Add**, **[e] Edit**, or **[d] Remove**.
Edit and remove prompt for the saved alias name. When editing, Enter keeps the
current target or key; `-` in the key prompt switches to the default key.
Removal requires typing `YES`. Duplicate aliases and invalid fields are rejected;
comments and unrelated hosts are preserved. Key names use letters, digits,
underscores and hyphens. Changes use a temporary file and atomic replacement;
a concurrent edit reports that the file is busy.

## Multiple SSH Keys

Generate additional named keys for different hosts:

```bash
# From KUAL: SSH Keys > Create Default Key (creates default key)
# From kterm: generate a named key
genkey.sh work
genkey.sh home
```

Use a specific key:
```bash
ssh -i work user@host     # Uses kindle_work_key
ssh -i home user@host     # Uses kindle_home_key
```

List all keys via KUAL (**SSH Keys** -> **List Keys**) or from kterm:
```bash
listkeys.sh
```

## Security Notes

- **Known hosts**: When `/root/.ssh` does not already exist, Install / Repair creates a symlink to `/mnt/us/extensions/sshk/.ssh/` for persistent known-host storage. Existing SSH directories and foreign symlinks are preserved. If the known-hosts file cannot be written, the client falls back to accepting host keys (`-y`); the KUAL Setup & Status page reports the active setup.
- **Key storage**: Private keys are stored in `extensions/sshk/bin/` on the Kindle's FAT32 partition. Anyone with physical access to the Kindle can read them. Use passphrase-protected keys on the server side for additional security.

## Project Documentation

- [SUPPORTED-DEVICES.md](SUPPORTED-DEVICES.md) — Device matrix: which Kindles work (2021–2024 included) and why
- [ARCHITECTURE.md](ARCHITECTURE.md) — How the project is structured and why
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to build, test, and contribute
- [CHANGELOG.md](CHANGELOG.md) — Release history

## License

`sshk` is released under the [MIT License](LICENSE). The bundled `dropbearmulti`
binary is Dropbear 2020.81; its license and third-party notices are provided in
[DROPBEAR-LICENSE](DROPBEAR-LICENSE).

---
*Based on the guides and resources compiled in [kindle-ssh-guide](https://github.com/Mounstroya/kindle-ssh-guide).*
