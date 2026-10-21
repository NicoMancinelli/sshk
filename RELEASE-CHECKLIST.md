# Release validation

Run from the repository root:

```sh
./tests/run-tests.sh
python3 tests/run-integration.py
python3 tests/package-release.py
```

The archive builder verifies version agreement, menu targets and permissions,
and excludes device state (`.ssh`, keys, logs and backups). It creates
`out/release/sshk.zip` and `SHA256SUMS`. Release tags must match `VERSION`.

## Isolated ARM smoke test

`tests/kindle-sim/run-sim.sh` exercises installation, key generation, KUAL
launching and the bundled ARM server. Run it with qemu-arm installed. The
simulator uses a temporary Kindle root, root home and server runtime. It must
never modify the host's `/root/.ssh` or terminate unrelated daemons.

## Windows acceptance

- On Windows PowerShell, run both the `.ps1` installer and the `.bat` launcher
  against a test Kindle volume with existing keys, `.ssh`, `hosts.conf`, and
  tailscaled state. Confirm each preserves data and reports copy failures.
- Verify quoting for drive roots with spaces and that `.bat` returns the
  PowerShell exit code. PowerShell/Windows runtime verification is still required.

## Physical Kindle acceptance (required before publishing)

- Copy the candidate archive to a spare/test Kindle; preserve a backup first.
- Fresh setup and repeated Install / Repair retain existing keys and hosts.
- Upgrade from v1.6 retains named keys, known hosts and authorized computer keys.
- Read every KUAL status/help page on a small e-ink screen. Check clipping,
  ghosting, missing prerequisites and whether the return path is clear.
- Open SSH; add, edit, connect and remove a saved host. Cancel removal.
- Test direct SSH and SCP, custom ports, named keys and sleep prevention.
- With Tailscale userspace networking configured, test a saved Tailscale host,
  custom socket, MagicDNS target and transfer in both directions.
- Check missing Tailscale, daemon stopped and logged-out messages.
- Start twice, inspect status/address, connect using a computer public key,
  stop twice, and confirm an unrelated SSH server remains running.
- Uninstall from KUAL: cancel once, then confirm. Verify other kterm changes,
  SSH data and saved hosts remain. Reinstall successfully.

Record Kindle model/firmware, kterm/Tailscale versions and archive checksum.
Host stubs and QEMU do not establish e-ink rendering or live tailnet behavior.
Do not label a release device-tested without this evidence.
