# 🚀 Quick Start Guide (60-Second Install)

Get SSH running on your jailbroken Kindle in 3 easy steps!

---

### Option A: 1-Click Desktop Installer (Easiest)

1. **Connect your Kindle** to your computer via USB (in drive mode).
2. **Run the installer**:
   - **macOS / Linux**: Open Terminal and run:
     ```bash
     ./install-to-kindle.sh
     ```
   - **Windows (PowerShell)**: Right-click `install-to-kindle.ps1` -> *Run with PowerShell* (or double-click `install-to-kindle.bat`).
3. **Eject Kindle & Open kterm**:
   - Open `kterm` from KUAL and type:
     ```bash
     ssh
     ```
     *(No arguments needed — `ssh` opens the interactive connection menu; connect with 1 keypress! `sshk` does the same.)*

---

### Option B: Manual Drag & Drop

1. Extract `sshk.zip`.
2. Drag the `extensions/` folder into your Kindle's USB drive root (e.g. `/Volumes/Kindle/` or `E:\`).
3. Safely eject Kindle.
4. In KUAL, tap **sshk: SSH Client** -> **Setup & Maintenance** -> **Install / Repair**.
5. Open `kterm` and enjoy!

---

### 🔑 Instant Server Authorization (1-Command)

To log into your remote server without a password:

1. Reconnect your Kindle to your computer via USB.
2. Run from your computer:
   ```bash
   ./authorize-server.sh user@your-server-ip
   ```
3. That's it! Your Kindle's SSH public key is automatically copied and configured on your server.

---

### Connect to a Tailscale host

Tailscale must be installed and running separately in userspace mode on the
Kindle (`tailscaled --tun=userspace-networking`). After login, choose **Tailscale
> Status** in KUAL or run `ssh-tailscale user@host`. The saved-host editor can
mark a host as `tailscale`; ordinary `ssh` and `scp` then route it through
Tailscale automatically. sshk does not install, log in, or start the daemon.

### Connect from your computer into the Kindle

With the Kindle mounted by USB, run `./authorize-kindle.sh /path/to/Kindle`.
This uses your computer's `~/.ssh/id_ed25519.pub`; supply another `.pub` file as
a second argument if needed. Eject USB, run **Setup & Maintenance > Install / Repair**
once, then **SSH Server > Start Server**. **Server Status** shows the address.

For troubleshooting, open **Setup & Status** in KUAL. For a reminder of which
public key goes where, open **SSH Keys > Connection Setup Help**.

### 💡 Common Commands in kterm

| Action | Command |
|---|---|
| **Quick-Connect Menu** | `ssh` *(no arguments — or `sshk` / `ssh-menu`)* |
| Get help (lists saved hosts) | `ssh -h` *(also `ssh-tailscale -h`, `scp-tailscale -h`)* |
| Connect via SSH | `ssh user@host` |
| Connect via Tailscale | `ssh-tailscale user@host` |
| Connect with custom port | `ssh -p 2222 user@host` |
| Copy file to server | `scp file.txt user@host:/path/` |
| Connect using saved alias | `ssh myserver` *(configured in `hosts.conf` or via `sshk` menu)* |
| Connect **into** Kindle from a PC | `ssh root@<kindle-ip> -p 2222` *(start server in KUAL)* |
| Refresh E-Ink Screen | `eips-refresh` *(clears ghosting)* |
