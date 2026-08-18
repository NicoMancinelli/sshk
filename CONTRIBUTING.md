# Contributing to sshk

Thank you for your interest in contributing to `sshk`! This guide outlines the development process, constraints, and best practices for this project.

## Prerequisites
To develop and test `sshk`, you will need:
*   A jailbroken Amazon Kindle.
*   **KUAL** (Kindle Unified Application Launcher) installed.
*   **kterm** installed via KUAL.
*   A cross-compilation environment for ARM (if modifying `dropbearmulti`).

## Cross-Compiling Dropbear
`dropbearmulti` must be statically compiled to run on the Kindle without library conflicts.

1.  **Toolchain**: You need an ARM cross-compiler. The official Kindle toolchain (`arm-kindle-linux-gnueabi`) or a `musl-cross` toolchain for ARM soft-float/hard-float depending on the target Kindle architecture is required.
2.  **Configure Flags**: When configuring the Dropbear source, use the following flags to ensure a static build suitable for the Kindle:
    ```bash
    ./configure --enable-static --disable-syslog --enable-bundled-libtom
    ```
3.  **Build**: Compile the multi-call binary and strip it to reduce size:
    ```bash
    make MULTI=1 STATIC=1 strip
    ```
4.  **Result**: You will get a single `dropbearmulti` binary. Copy this to `extensions/sshk/bin/`.

## Shell Script Conventions
The Kindle runs an embedded Linux environment with BusyBox. Strict adherence to POSIX standards is required.

*   **Shebang**: Always use `#!/bin/sh`. Do not use `#!/bin/bash` or rely on bash-specific features (e.g., `[[ ... ]]`, arrays, process substitution).
*   **Path Resolution**: At the top of every script, include this line to robustly determine the script's directory:
    ```sh
    BINDIR="$(cd "$(dirname "$0")" && pwd)"
    ```
*   **Display Output (`eips`)**: For scripts intended to run from the KUAL menu (where standard output is not visible), use the `eips_print()` pattern to print text to the e-ink screen. Note that `eips` lines should be short (~50 characters) to avoid wrapping poorly on the display.
*   **BusyBox Utilities**: Assume only BusyBox versions of standard tools (`grep`, `sed`, `awk`) are available. Avoid GNU-specific flags.

## Adding a New Menu Item
To add a new feature to the KUAL interface:
1.  Create a shell script in `extensions/sshk/bin/` implementing the feature.
2.  Modify `extensions/sshk/menu.json` to include the new entry. Pay attention to the `priority` field to control its order in the menu.

## Testing on Kindle
1.  Connect your Kindle via USB.
2.  Copy your modified `extensions/sshk` directory to the Kindle's USB root (`/mnt/us/extensions/sshk`).
3.  Eject the Kindle safely.
4.  Launch KUAL and test the menu items.
5.  Launch `kterm` to test command-line wrappers.
6.  **Logs**: Check standard output in `kterm` or look for errors if a KUAL script fails. KUAL sometimes logs to `/mnt/us/mkk/` or `/var/log/messages` depending on the system setup.

## Building the Release ZIP
When preparing a release, the directory structure must be packaged correctly so users can extract it directly to the root of their USB drive.

```bash
cd /path/to/sshk
zip -r sshk.zip extensions/
```
Ensure no `.DS_Store` or other hidden OS files are included in the zip.

## Release Process
1.  Bump the version number in any relevant files (e.g., `VERSION` file if present, or `menu.json`).
2.  Update `CHANGELOG.md` with a summary of changes.
3.  Commit the changes.
4.  Create a git tag for the version (e.g., `git tag v1.1.0`).
5.  Push the tag: `git push origin v1.1.0`.
6.  Create a new Release on GitHub.
7.  Attach the generated `sshk.zip` to the GitHub release.

## Code Review Checklist
Before submitting a Pull Request, please ensure:
*   [ ] All shell scripts use `#!/bin/sh` and are fully POSIX compliant.
*   [ ] Scripts have been checked with `shellcheck --shell=sh` (if possible).
*   [ ] KUAL menu scripts use `eips` for user feedback.
*   [ ] Error handling is robust (e.g., checking if `mntroot` succeeds).
*   [ ] No symbolic links are used within the `extensions/sshk` directory (FAT32 compatibility).
