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
     sshk
     ```
     *(Opens the interactive connection menu — connect with 1 keypress!)*

---

### Option B: Manual Drag & Drop

1. Extract `sshk.zip`.
2. Drag the `extensions/` folder into your Kindle's USB drive root (e.g. `/Volumes/Kindle/` or `E:\`).
3. Safely eject Kindle.
4. In KUAL, tap **sshk: SSH Client** -> **⚡ 1-Tap Setup (Install & Key)**.
5. Open `kterm` and enjoy!

---

### 🔑 Instant Server Authorization (1-Command)

To log into your remote server without a password:

1. Reconnect your Kindle to your computer via USB.
2. Run from your computer:
   ```bash
   ./authorize-server.sh user@your-server-ip
   ```
3. That's it! Your Kindle's SSH public key is automatically copied and configured on your server. *(It also authorizes your PC to SSH into your Kindle!)*

---

### 💡 Common Commands in kterm

| Action | Command |
|---|---|
| **Quick-Connect Menu** | `sshk` *(or `ssh-menu`)* |
| Connect via SSH | `ssh user@host` |
| Connect via Tailscale | `ssh-tailscale user@host` |
| Connect with custom port | `ssh -p 2222 user@host` |
| Copy file to server | `scp file.txt user@host:/path/` |
| Connect using saved alias | `ssh myserver` *(configured in `hosts.conf` or via `sshk` menu)* |
| Refresh E-Ink Screen | `eips-refresh` *(clears ghosting)* |
