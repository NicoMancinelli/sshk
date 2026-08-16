# sshk: Kindle KTerm SSH Client Extension

`sshk` is an easily installable KUAL (Kindle Unified Application Launcher) extension that configures and runs a statically-compiled SSH client (`dbclient`) inside `kterm` (the Kindle terminal emulator) on jailbroken Amazon Kindle devices.

Normally, Kindle devices do not have an SSH client installed, and compiling one statically with standard toolchains leads to library conflicts and crashes. `sshk` solves this by bundling a fully static, standalone `dropbearmulti` ARM binary.

## Features

- **Standalone ARM Static Binary**: Statically linked Dropbear client independent of system libraries.
- **kterm Integration**: Automated setup that modifies `kterm.sh` to add the binaries to your terminal's `PATH`.
- **Easy Key Management**: Generate `ed25519` SSH keys on the Kindle and export the public key to your Kindle's USB drive root (`kindle_ssh_key.pub`) for easy copying on your computer.
- **Tailscale Support**: Includes an `ssh-tailscale` wrapper that automatically tunnels outbound connections through Tailscale userspace mode (`tailscale nc`), bypassing the lack of native `tun.ko` routing.
- **VFAT/FAT32 Compatibility**: Uses shell scripts instead of symbolic links to ensure the extension copies flawlessly over USB mass storage.

## Installation

1. **Connect your Kindle** to your computer via USB.
2. **Download the Release**:
   - Download the `sshk.zip` file from the [Releases](https://github.com/nico/sshk/releases) page.
   - Extract it.
3. **Copy to Kindle**:
   - Copy the extracted `extensions` directory into your Kindle's USB root (e.g. `/Volumes/Kindle/` or `E:\` so it merges with the existing `extensions/` directory and creates `extensions/sshk/`).
4. **Safely eject** your Kindle.
5. **Run Setup**:
   - Open KUAL on your Kindle.
   - Tap **sshk: SSH Client** -> **Install SSH into kterm**.
6. **Generate SSH Keys (Recommended)**:
   - In KUAL, tap **Generate SSH Key**. This generates a private key and saves your public key to `/mnt/us/kindle_ssh_key.pub`.
   - Reconnect your Kindle to your computer and add the contents of `kindle_ssh_key.pub` to the remote server's `~/.ssh/authorized_keys` file.

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

---
*Based on the guides and resources compiled in [kindle-ssh-guide](https://github.com/Mounstroya/kindle-ssh-guide).*
