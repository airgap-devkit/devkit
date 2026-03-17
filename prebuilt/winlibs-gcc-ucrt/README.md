# prebuilt/winlibs-gcc-ucrt

Pre-built binary package manager for the WinLibs GCC UCRT toolchain.
Part of the `airgap-cpp-devkit` suite.

## Pinned Release

| Component      | Version                       |
|----------------|-------------------------------|
| GCC            | 15.2.0 (POSIX threads)        |
| MinGW-w64      | 13.0.0 (UCRT)                 |
| GDB            | 17.1                          |
| Binutils       | 2.46.0                        |
| CMake          | 4.2.3                         |
| Ninja          | 1.13.2                        |
| Release tag    | `15.2.0posix-13.0.0-ucrt-r6`  |
| Upstream       | [brechtsanders/winlibs_mingw] |

[brechtsanders/winlibs_mingw]: https://github.com/brechtsanders/winlibs_mingw/releases/tag/15.2.0posix-13.0.0-ucrt-r6

SHA256 checksums are pinned in `manifest.json` and were cross-referenced from
two independent sources: the official GitHub release sidecar and the
ScoopInstaller/Main package registry.

---

## Layout

```
prebuilt/winlibs-gcc-ucrt/
├── manifest.json          # version pin, URLs, dual-source SHA256 checksums
├── scripts/
│   ├── download.sh        # online machine: fetch + dual-source verify
│   ├── verify.sh          # offline: SHA256 check against manifest only
│   ├── install.sh         # air-gapped target: extract + smoke test
│   └── env-setup.sh       # source to activate toolchain in current shell
├── vendor/                # .7z lands here (gitignored)
│   └── .gitkeep
└── docs/
    └── offline-transfer.md  # air-gap sneakernet instructions
```

---

## Quickstart — Networked Machine

```bash
cd prebuilt/winlibs-gcc-ucrt
bash scripts/download.sh x86_64     # downloads, verifies dual-source SHA256
```

Then transfer `vendor/*.7z` to the air-gapped host via USB/media.

---

## Quickstart — Air-Gapped Machine

```bash
# Place the .7z in vendor/, then:
cd prebuilt/winlibs-gcc-ucrt
bash scripts/verify.sh x86_64       # offline integrity check
bash scripts/install.sh x86_64      # verify + extract + smoke test
source scripts/env-setup.sh x86_64  # activate in current shell
gcc --version
```

---

## Architecture Support

| Arch    | Exception Model | CRT  |
|---------|-----------------|------|
| x86_64  | SEH             | UCRT |
| i686    | DWARF           | UCRT |

Default is `x86_64`. Pass `i686` as the first argument to any script for 32-bit.

---

## Notes

- **No system install.** WinLibs is fully relocatable — extraction to
  `toolchain/<arch>/` is all that's needed. No registry writes, no installers.
- **Parallel toolchains.** `env-setup.sh` prepends to PATH for the current
  shell only. Other shells are unaffected. This coexists cleanly with the
  `clang-llvm-source-build` LLVM toolchain.
- **UCRT runtime requirement.** Binaries compiled with this toolchain require
  UCRT (built into Windows 10+, or installable on Windows 7 SP1+).
- **`vendor/` is gitignored.** The `.7z` is large (~200 MB) and must not be
  committed. Only `vendor/.gitkeep` is tracked.
