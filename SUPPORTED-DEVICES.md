# Supported Devices

`sshk` targets jailbroken Amazon Kindle e-readers. This page records which
hardware is expected to work, why, and what is still awaiting on-device
confirmation.

## Why one binary covers (almost) everything

`extensions/sshk/bin/dropbearmulti` is a fully static, **32-bit ARM (EABI5),
soft-float, ARMv5TE-baseline** executable:

```
$ readelf -A extensions/sshk/bin/dropbearmulti | grep -E 'Tag_CPU_arch|VFP'
  Tag_CPU_name: "5TE"
  Tag_CPU_arch: v5TE
```

*   **Soft-float ABI** means the binary never touches an FPU, so it behaves
    identically on old soft-float-only cores and on modern cores executing in
    hard-float mode.
*   **ARMv5TE baseline** means any ARMv5TE-or-newer core can execute it — every
    Kindle ever shipped qualifies (original Kindle through the 2021–2024
    generations; all of them run 32-bit ARM userland, none ship aarch64
    userland to date).
*   **Fully static** means no dependency on the device's libc version.

Amazon's post-2020 devices (Paperwhite 5, Scribe, the 2022/2024 basic Kindles)
continue to run 32-bit ARM userland, so the same single binary applies.

The reproducible rebuild pipeline (`build/build-dropbear.sh`) preserves these
properties: it targets `arm-linux-musleabi` (musl defaults to ARMv5T,
soft-float) with `-march=armv5t` pinned explicitly, and CI refuses any
artifact that is not statically linked.

## Device matrix

| Device | Generation | Year | Userland | Jailbreak route | sshk status |
| --- | --- | --- | --- | --- | --- |
| Kindle (basic) | 11th gen | 2022 | 32-bit ARM | LanguageBreak ≤ 5.16.2.x / WatchThis-era methods | Binary-compatible ✅ · on-device test pending ⏳ |
| Kindle (basic) | 12th gen | 2024 | 32-bit ARM | see MobileRead exploit tracker | Binary-compatible ✅ · on-device test pending ⏳ |
| Kindle Paperwhite 5 / Signature Ed. | 11th gen | 2021 | 32-bit ARM | LanguageBreak ≤ 5.16.2.x | Binary-compatible ✅ · on-device test pending ⏳ |
| Kindle Scribe | 1st gen | 2022 | 32-bit ARM | LanguageBreak ≤ 5.16.2.x | Binary-compatible ✅ · on-device test pending ⏳ |
| Kindle Scribe | 2nd gen | 2024 | 32-bit ARM | see MobileRead exploit tracker | Binary-compatible ✅ · on-device test pending ⏳ |
| Pre-2020 Kindles (KPW4, Oasis 2/3, Kindle 10th gen, …) | various | ≤ 2019 | 32-bit ARM (soft-float capable) | existing jailbreaks (MRPI/KUAL era) | Works — this was the original target ✅ |

Legend: ✅ = supported by design/evidence · ⏳ = expected to work, needs a
confirmed on-device report.

## Requirements on modern firmware (5.14+)

1.  **A jailbreak.** Recent firmware uses [LanguageBreak](https://github.com/notmarek/LanguageBreak)
    (firmware ≤ 5.16.2.1.1) or successor exploits — follow the current guidance
    on the [MobileRead Kindle forums](https://www.mobileread.com/forums/forumdisplay.php?f=150).
2.  **KUAL** installed as a booklet (modern KUAL packages include the
    `config.xml` mechanism sshk already ships).
3.  **kterm** installed via KUAL — sshk injects its `bin/` directory into
    kterm's `PATH`; the layout is identical on modern firmware.
4.  Standard Lab126 helpers used by sshk (`eips`, `lipc-set-prop`, `mntroot`)
    exist across all 5.x firmware generations.

## Verification method

Binary-level compatibility is asserted automatically: CI checks the ELF
architecture attributes of the bundled binary (see `.github/workflows/ci.yml`,
"Verify binary portability"). On-device confirmation still requires human
testing — if sshk works on your post-2020 Kindle, please open an issue or PR
moving your row from ⏳ to ✅.

## Known non-goals

*   **aarch64 (64-bit) userland** — no Amazon firmware ships it yet; when one
    does, add a second build target in `build/container-build.sh`.
*   **Non-jailbroken devices** — sshk requires KUAL by design.
