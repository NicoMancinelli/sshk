# sshk AI Context Guide

## Quick Summary
`sshk` is a KUAL (Kindle Unified Application Launcher) extension that provides SSH client capabilities for jailbroken Amazon Kindles. It bundles a statically-compiled `dropbearmulti` binary and POSIX shell wrapper scripts to integrate with `kterm`, allowing users to connect to remote servers and Tailnets directly from their Kindle without encountering the library mismatches common on embedded systems.

## Critical Constraints
When assisting with this project, AI agents **MUST** adhere to the following constraints:

*   **POSIX sh only**: The Kindle runs BusyBox `/bin/sh`. Bash features (`[[ ]]`, arrays, `local` outside functions depending on the shell, process substitution) will fail. Always use `#!/bin/sh`.
*   **No Symlinks**: The Kindle's user partition (`/mnt/us`) is FAT32/VFAT. Symlinks are not supported. Do not create symlinks within the extension directory. Use shell script wrappers instead (e.g., a script named `ssh` that calls `dropbearmulti dbclient`).
*   **Read-Only Rootfs**: The root filesystem is read-only. If you must write to `/root/` (e.g., for `known_hosts`) or `/etc/`, you must first run `mntroot rw` and ensure you run `mntroot ro` afterwards.
*   **eips for Display**: When scripts run from KUAL (not within kterm), standard output is hidden. Use the `eips_print()` pattern (clearing the line, then printing) to show feedback on the e-ink screen. Lines must be short (~50 chars).
*   **Absolute Paths on Target**: Assume the extension is installed at `/mnt/us/extensions/sshk/` on the target Kindle.
*   **BusyBox Coreutils**: Standard Linux commands (`grep`, `sed`, `awk`) are the BusyBox variants. Avoid GNU-specific extensions.

## File Index
*   `README.md`: Project documentation and user guide.
*   `extensions/sshk/menu.json`: KUAL menu configuration file defining UI items.
*   `extensions/sshk/bin/dropbearmulti`: Core statically linked multi-call ARM binary.
*   `extensions/sshk/bin/dbclient`: Wrapper to invoke the SSH client applet.
*   `extensions/sshk/bin/dropbearkey`: Wrapper to invoke the key generation applet.
*   `extensions/sshk/bin/ssh`: Main SSH wrapper, injects key paths and handles known_hosts.
*   `extensions/sshk/bin/ssh-tailscale`: SSH wrapper that proxies connections through `tailscale nc`.
*   `extensions/sshk/bin/genkey.sh`: KUAL script to generate an ed25519 key pair.
*   `extensions/sshk/bin/showkey.sh`: KUAL script to display the public key via `eips`.
*   `extensions/sshk/bin/install.sh`: KUAL script to add the bin directory to `kterm` PATH and setup known_hosts.
*   `extensions/sshk/bin/uninstall.sh`: KUAL script to revert `install.sh` changes.

## Common Patterns

*   **Adding a new CLI tool**: Create a new wrapper script in `extensions/sshk/bin/` (e.g., `scp`). Ensure it is executable. It will automatically be in the PATH if `install.sh` was run.
*   **Adding a new KUAL menu action**: Create a new `.sh` script in `extensions/sshk/bin/`. Add a corresponding JSON object to the `items` array in `extensions/sshk/menu.json`.
*   **Displaying output**:
    *   If running inside `kterm`: Standard `echo` or `printf` to stdout.
    *   If running via KUAL menu: Use a function like `eips_print()` to write to the framebuffer.

## Testing Checklist
*   [ ] Run `sh -n script.sh` on all modified shell scripts to check for syntax errors.
*   [ ] Validate JSON: `python3 -c "import json; json.load(open('extensions/sshk/menu.json'))"`
*   [ ] Run `shellcheck --shell=sh script.sh` to ensure POSIX compliance.
*   [ ] Deploy the `extensions/sshk` directory to a physical Kindle and test functionality via KUAL and kterm.

## Release Checklist
1.  Bump the version in `README.md` / `menu.json` / `VERSION` if applicable.
2.  Update `CHANGELOG.md`.
3.  Create the release zip: `zip -r sshk.zip extensions/`
4.  Tag the release: `git tag vX.Y`
5.  Create a GitHub release and attach the `sshk.zip` artifact.
