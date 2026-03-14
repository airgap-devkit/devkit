# clang-llvm-style-formatter

> Pre-commit hook enforcement of the [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)
> for C/C++ repositories — designed for air-gapped, multi-repo, multi-platform environments.

---

## Overview

`clang-llvm-style-formatter` is a **self-contained Git submodule** that enforces
LLVM C++ style via a pre-commit hook. Add it to as many repositories as you like;
each host repository carries one copy of the hook configuration and a single
bootstrap command wires everything up.

The submodule includes the LLVM/Clang source tree (tests stripped, ~250 MB)
so that `clang-format` can be **built entirely on air-gapped machines** with no
network access and no external package manager required.

```
your-repo/
├── .git/
│   └── hooks/
│       └── pre-commit          ← installed by bootstrap.sh
├── .llvm-hooks/                ← this submodule
│   ├── bootstrap.sh            ← one-command developer setup
│   ├── hooks/
│   │   └── pre-commit          ← the actual hook logic
│   ├── config/
│   │   ├── hooks.conf          ← runtime toggles
│   │   ├── .clang-format       ← LLVM style rules
│   │   └── .clang-tidy         ← static analysis rules
│   ├── llvm-src/               ← vendored LLVM/Clang source (~250 MB, tests stripped)
│   │   ├── llvm/               ← LLVM core
│   │   │   └── tools/clang/    ← Clang frontend
│   │   ├── cmake/              ← build system modules
│   │   ├── third-party/        ← build system support
│   │   └── SOURCE_INFO.txt     ← LLVM version + original checksums
│   ├── bin/
│   │   ├── linux/clang-format  ← built by build-clang-format.sh (not committed)
│   │   └── windows/clang-format.exe  ← built by build-clang-format.sh (not committed)
│   └── scripts/
│       ├── build-clang-format.sh    ← compile clang-format from llvm-src/
│       ├── fetch-llvm-source.sh     ← (connected machine only) fetch + strip source
│       ├── install-hooks.sh
│       ├── fix-format.sh
│       ├── setup-user-path.sh
│       ├── find-tools.sh
│       ├── verify-tools.sh
│       └── create-test-repo.sh
├── .clang-format               ← symlink → .llvm-hooks/config/.clang-format
└── .clang-tidy                 ← symlink → .llvm-hooks/config/.clang-tidy
```

---

## Requirements

| Tool | Notes |
|------|-------|
| Git 2.13+ | For submodule support |
| Bash 4.x+ | Git Bash on Windows satisfies this |
| CMake 3.14+ | Required to build `clang-format` from source |
| C++ compiler | MSVC (VS 2017/2019/2022) on Windows; GCC 8+ on RHEL 8 |
| Ninja *(recommended)* | Faster builds; falls back to `make` if absent |

**`clang-format` itself does not need to be pre-installed.** If it is not already
present, `bootstrap.sh` will compile it from the vendored source in `llvm-src/`.
This takes 30–60 minutes on first run and requires no network access.

---

## Adding to a New Repository (one-time, per repo)

```bash
# From the host repository root:
git submodule add https://bitbucket.example.com/your-org/clang-llvm-style-formatter.git .llvm-hooks
git submodule update --init --recursive

# Bootstrap: build clang-format if needed, install hook, wire config
bash .llvm-hooks/bootstrap.sh
```

Commit the submodule pointer and config symlinks:

```bash
git add .gitmodules .llvm-hooks .clang-format .clang-tidy
git commit -m "chore: add LLVM style enforcement via clang-llvm-style-formatter"
```

---

## Developer Onboarding (after cloning a host repo)

When a developer clones a repository that already has this submodule, they run
**one command**:

```bash
bash .llvm-hooks/bootstrap.sh
```

This will:
1. Initialise and update all submodules
2. Check whether `clang-format` is already present (system install or a previous
   build in `bin/linux/` or `bin/windows/`)
3. If not found, offer to build it from the vendored source in `llvm-src/`
   (30–60 minutes; requires CMake and a C++ compiler — both typically present
   if LLVM is installed as the project compiler)
4. Install the pre-commit hook into `.git/hooks/pre-commit`

---

## How the Hook Works

On every `git commit`, the hook:

1. Collects all **staged** C/C++ files (`.cpp`, `.cxx`, `.cc`, `.c`, `.h`, `.hpp`, `.hxx`, `.hh`)
2. Runs `clang-format --style=file` against the **staged content** (not working-tree)
3. If any file would be reformatted → **commit is rejected** with a clear message
4. Optionally runs `clang-tidy` if `ENABLE_TIDY=true` and `compile_commands.json` exists

When the commit is rejected:

```
╔══════════════════════════════════════════════════════════════════╗
║  clang-format: LLVM style violations found — commit REJECTED    ║
╚══════════════════════════════════════════════════════════════════╝
    ✗  src/bad_indent.cpp
    ✗  src/bad_style.cpp

  Fix options:
    Auto-fix staged files:  .llvm-hooks/scripts/fix-format.sh
    Manual inspection:      clang-format --style=file -i <file>
```

### Auto-fixing violations

```bash
# Format all staged files in-place and re-stage them:
bash .llvm-hooks/scripts/fix-format.sh

# Preview what would change without modifying anything:
bash .llvm-hooks/scripts/fix-format.sh --dry-run

# Then commit normally:
git commit -m "your message"
```

### Bypassing the hook (emergency only)

```bash
git commit --no-verify -m "emergency: bypass style check"
```

---

## Configuration

### Per-repo overrides (`hooks.conf`)

`bootstrap.sh` copies a `hooks.conf` to `.llvm-hooks-local/hooks.conf` for
per-repository customisation. Edit this file to override defaults:

```bash
# Enable clang-tidy (requires compile_commands.json)
ENABLE_TIDY="true"

# Point to a specific binary if the vendored build is not used
CLANG_FORMAT_BIN="/usr/local/bin/clang-format"

# Increase verbosity (shows per-file diffs on failure)
VERBOSE="true"
```

### Updating the style configuration

The canonical style rules live in:

```
.llvm-hooks/config/.clang-format   ← clang-format rules
.llvm-hooks/config/.clang-tidy     ← clang-tidy checks
```

To change rules for **all repos**, update the files in this submodule and push.
Each host repo picks up the changes on the next `git submodule update --remote .llvm-hooks`.

---

## Updating the Submodule in Host Repositories

```bash
# From the host repo root:
git submodule update --remote .llvm-hooks
git add .llvm-hooks
git commit -m "chore: update clang-llvm-style-formatter submodule"
```

---

## Building clang-format from Source

`clang-format` is compiled from the vendored source in `llvm-src/` when not
already present. `bootstrap.sh` handles this automatically, but you can also
trigger it manually:

```bash
bash .llvm-hooks/scripts/build-clang-format.sh

# Force a clean rebuild:
bash .llvm-hooks/scripts/build-clang-format.sh --rebuild

# Control parallel jobs:
bash .llvm-hooks/scripts/build-clang-format.sh --jobs 8
```

The compiled binary is placed at `bin/linux/clang-format` or
`bin/windows/clang-format.exe`. The build directory (`llvm-src/build/`) can
be deleted after building to reclaim ~420 MB of disk space — the binary is
all that is kept.

### Build prerequisites

**Windows (Git Bash / MINGW64):**
- Visual Studio 2017, 2019, or 2022 with the C++ workload
- CMake 3.14+ (bundled with VS 2019+)
- Ninja (bundled with VS, or from `ninja-build.org`)
- Run from an **x64 Native Tools Command Prompt** or ensure MSVC is on PATH

**RHEL 8:**
- GCC 8+ (`gcc-c++` package, part of Development Tools group)
- CMake 3.14+ (`cmake` package)
- Ninja (`ninja-build` package, recommended) or GNU make

---

## Updating the Vendored LLVM Source

The vendored source in `llvm-src/` is pinned to a specific LLVM version
(recorded in `llvm-src/SOURCE_INFO.txt`). To update to a new version:

1. On a machine with network access, run:
   ```bash
   bash .llvm-hooks/scripts/fetch-llvm-source.sh --version X.Y.Z
   ```
2. This fetches, verifies, extracts, and strips the new source tree into `llvm-src/`.
3. Commit the updated `llvm-src/` directory:
   ```bash
   git add llvm-src/
   git commit -m "vendor: update LLVM source to X.Y.Z"
   ```
4. Distribute the updated submodule to air-gapped machines via your normal
   transfer process. Developers run `build-clang-format.sh` once to rebuild.

---

## Running the End-to-End Test

Verify the hook works correctly in a fully isolated scratch environment:

```bash
bash .llvm-hooks/scripts/create-test-repo.sh

# Keep the test directory afterwards for manual inspection:
bash .llvm-hooks/scripts/create-test-repo.sh --keep
```

Expected output:

```
  A (clean commit accepted)  : ✓ PASS
  B (bad commit rejected)    : ✓ PASS
  C (fixed commit accepted)  : ✓ PASS
```

---

## Air-Gapped Environments

This project is designed for air-gapped use. **No network access is required
at any point on developer machines.**

The `llvm-src/` directory contains the complete LLVM/Clang source needed to
build `clang-format`, pre-stripped of tests and documentation to keep the
committed size to ~250 MB. Everything builds locally from this source using
only the tools already present on a developer's machine (CMake + C++ compiler).

The only step that requires a network connection is the one-time source fetch
when updating the LLVM version (`fetch-llvm-source.sh`), which is run by a
maintainer on a connected machine before committing and distributing.

---

## Super-Project / Nested Submodule Repositories

For host repositories that are themselves super-projects, no special handling
is required. The `.llvm-hooks` submodule sits at the host repo root and
operates on all C/C++ files staged in that repo. The hook uses
`git diff --cached --name-only` which is scoped to the currently committed
repository and will not accidentally reach into nested submodule working trees.

---

## Supported Environments

| Environment | Status |
|-------------|--------|
| Windows 11 + Git Bash (MINGW64) | ✓ Supported |
| RHEL 8 + Bash 4.x | ✓ Supported |
| VxWorks Workbench (Eclipse) | Hook runs on host OS shell; VxWorks target unaffected |
| Visual Studio 2017 / 2019 / 2022 | IDE-independent; hook runs via Git |
| C++11 / C++14 / C++17 code | ✓ `.clang-format` uses `Standard: Auto` |

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | One-command developer setup |
| `hooks/pre-commit` | The pre-commit hook (gate logic) |
| `config/hooks.conf` | Runtime configuration |
| `config/.clang-format` | LLVM clang-format rules |
| `config/.clang-tidy` | LLVM clang-tidy checks |
| `llvm-src/` | Vendored LLVM/Clang source (~250 MB, tests stripped) |
| `llvm-src/SOURCE_INFO.txt` | LLVM version, fetch date, original checksums |
| `bin/linux/clang-format` | Built binary (generated, not committed) |
| `bin/windows/clang-format.exe` | Built binary (generated, not committed) |
| `scripts/build-clang-format.sh` | Compile clang-format from llvm-src/ |
| `scripts/fetch-llvm-source.sh` | Fetch + strip LLVM source (connected machine only) |
| `scripts/install-hooks.sh` | Wire hook into a host repo's `.git/hooks/` |
| `scripts/fix-format.sh` | Auto-format + re-stage failing files |
| `scripts/verify-tools.sh` | Tool diagnostic with build guidance |
| `scripts/setup-user-path.sh` | Add a bin directory to user PATH (no admin) |
| `scripts/find-tools.sh` | Sourced helper: discover clang-format/tidy |
| `scripts/create-test-repo.sh` | End-to-end isolated test harness |
| `docs/llvm-install-guide.md` | LLVM build prerequisites by platform |
