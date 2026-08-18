# sshk: Kindle KTerm SSH Client Extension

`sshk` is an easily installable KUAL (Kindle Unified Application Launcher) extension that configures and runs a statically-compiled SSH client (`dbclient`) and SCP inside `kterm` (the Kindle terminal emulator) on jailbroken Amazon Kindle devices.

Normally, Kindle devices do not have an SSH client installed, and compiling one statically with standard toolchains leads to library conflicts and crashes. `sshk` solves this by bundling a fully static, standalone `dropbearmulti` ARM binary.

## Features

- **Standalone ARM Static Binary**: Statically linked Dropbear client independent of system libraries.
- **kterm Integration**: Automated setup that modifies `kterm.sh` to add the binaries to your terminal's `PATH`.
- **Easy Key Management**: Generate `ed25519` SSH keys on the Kindle and export the public key to your Kindle's USB drive root (`kindle_ssh_key.pub`) for easy copying on your computer.
- **Multiple Keys**: Generate and manage multiple named SSH keys for different hosts or purposes.
- **SCP File Transfer**: Transfer files to and from remote servers, including over Tailscale.
- **Host Aliases**: Save frequently used connections in `hosts.conf` for quick access (e.g., `ssh myserver` instead of `ssh admin@192.168.1.10:2222`).
- **Tailscale Support**: Includes `ssh-tailscale` and `scp-tailscale` wrappers that automatically tunnel connections through Tailscale userspace mode (`tailscale nc`), bypassing the lack of native `tun.ko` routing.
- **Custom Port Support**: Connect to SSH servers on non-standard ports, including over Tailscale tunnels.
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

### Method 2: Manual Copy & 1-Tap Setup

1. **Connect your Kindle** to your computer via USB.
2. **Download & Extract** `sshk.zip` from [Releases](https://github.com/NicoMancinelli/sshk/releases).
3. **Copy `extensions` folder** into your Kindle's USB drive root (e.g. `/Volumes/Kindle/` or `E:\`).
4. **Safely eject** your Kindle.
5. **Run 1-Tap Setup**:
   - Open KUAL on your Kindle.
   - Tap **sshk: SSH Client** -> **⚡ 1-Tap Setup (Install & Key)**.
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

## Usage inside kterm

Open `kterm` from KUAL and run:

- **For standard SSH connections**:
  ```bash
  ssh user@host
  ```
- **For Tailscale network connections**:
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

## Host Aliases

Save frequently used connections in `extensions/sshk/hosts.conf`:

```
# Format: alias user@host[:port] [keyname]
myserver admin@192.168.1.10
work dev@work.example.com:2222
tailnet user@mypc work
```

Then connect with just:
```bash
ssh myserver           # → admin@192.168.1.10 with default key
ssh work               # → dev@work.example.com on port 2222
ssh tailnet            # → user@mypc using kindle_work_key
```

The alias also works with `ssh-tailscale`.

## Multiple SSH Keys

Generate additional named keys for different hosts:

```bash
# From KUAL: tap "Generate SSH Key" (creates default key)
# From kterm: generate a named key
genkey.sh work
genkey.sh home
```

Use a specific key:
```bash
ssh -i work user@host     # Uses kindle_work_key
ssh -i home user@host     # Uses kindle_home_key
```

List all keys via KUAL (**List SSH Keys**) or from kterm:
```bash
listkeys.sh
```

## Security Notes

- **Known hosts**: On install, `sshk` sets up a writable `known_hosts` file by symlinking `/root/.ssh` to `/mnt/us/extensions/sshk/.ssh/`. This allows SSH to verify and remember host keys. If the symlink setup fails (e.g., `mntroot` not available), the wrapper falls back to auto-accepting host keys (`-y` flag).
- **Key storage**: Private keys are stored in `extensions/sshk/bin/` on the Kindle's FAT32 partition. Anyone with physical access to the Kindle can read them. Use passphrase-protected keys on the server side for additional security.

## Project Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — How the project is structured and why
- [CONTRIBUTING.md](CONTRIBUTING.md) — How to build, test, and contribute
- [CHANGELOG.md](CHANGELOG.md) — Release history

---
*Based on the guides and resources compiled in [kindle-ssh-guide](https://github.com/Mounstroya/kindle-ssh-guide).*
