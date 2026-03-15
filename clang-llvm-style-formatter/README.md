# clang-llvm-style-formatter

> Pre-commit hook enforcement of [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)
> for C/C++ repositories — designed for air-gapped, multi-repo, multi-platform environments.

---

## Overview

`clang-llvm-style-formatter` is a self-contained tool that enforces LLVM C++
style via a Git pre-commit hook. It ships everything needed to build
`clang-format` from source with no network access required on developer machines.

---

## Developer Onboarding (run once after cloning)

```bash
bash clang-llvm-style-formatter/bootstrap.sh
```

Bootstrap handles everything:

| Step | What happens |
|------|-------------|
| 1 | Git submodules initialised |
| 2 | Scans for `clang-format` and `ninja` on PATH and in `bin/` |
| 3 | If missing: shows what will be built, asks **"Install from vendored source? [y/N]"** |
| → Yes | Builds from committed tarballs — no network needed |
| → No | Exits with error; hook is NOT installed |
| 4 | Pre-commit hook installed into `.git/hooks/pre-commit` |
| 5 | Smoke test runs to verify everything works |

**No network access is required at any point on developer machines.**

---

## Adding to a New Repository (maintainer, done once)

When deploying this formatter to a separate production repository on Bitbucket:

```bash
# From inside your target C++ project:
git submodule add https://bitbucket.your-org.com/your-team/clang-llvm-style-formatter.git clang-llvm-style-formatter
git submodule update --init --recursive
git add .gitmodules clang-llvm-style-formatter
git commit -m "chore: add LLVM style enforcement"
git push
```

Developers then run:
```bash
git submodule update --init --recursive
bash clang-llvm-style-formatter/bootstrap.sh
```

---

## Build Prerequisites

### Windows 11 (Git Bash / MINGW64)

| Tool | Minimum | Notes |
|------|---------|-------|
| Visual Studio | 2017 / 2019 / 2022 | With "Desktop development with C++" workload |
| CMake | 3.14+ | Bundled with VS 2019+ |
| Python 3 | 3.6+ | Bundled with VS 2019+ |

### RHEL 8

| Package | Command |
|---------|---------|
| GCC/G++ 8+ | `sudo dnf install gcc-c++` |
| CMake 3.14+ | `sudo dnf install cmake` |
| Python 3.6+ | Pre-installed on RHEL 8 |

See **[docs/llvm-install-guide.md](docs/llvm-install-guide.md)** for detailed
prerequisites, troubleshooting, and known issues per platform.

---

## How the Pre-Commit Hook Works

On every `git commit`, the hook:

1. Collects all staged C/C++ files (`.cpp`, `.cxx`, `.cc`, `.c`, `.h`, `.hpp`, `.hxx`, `.hh`)
2. Runs `clang-format --style=file` against the staged content
3. **Rejects** the commit if any file would be reformatted

When a commit is rejected:

```
╔══════════════════════════════════════════════════════════════════╗
║  clang-format: LLVM style violations found — commit REJECTED    ║
╚══════════════════════════════════════════════════════════════════╝
    ✗  src/bad_indent.cpp

  Fix options:
    Auto-fix staged files:  bash clang-llvm-style-formatter/scripts/fix-format.sh
    Manual:                 clang-format --style=file -i <file>
```

### Auto-fixing violations

```bash
bash clang-llvm-style-formatter/scripts/fix-format.sh        # fix and re-stage
bash clang-llvm-style-formatter/scripts/fix-format.sh --dry-run  # preview only
git commit -m "your message"
```

### Emergency bypass

```bash
git commit --no-verify -m "emergency: skip formatting check"
```

---

## Smoke Test

Verify the full pipeline is working at any time:

```bash
bash clang-llvm-style-formatter/scripts/smoke-test.sh
```

Expected output:
```
  [PASS]  Found: .../bin/windows/clang-format.exe
  [PASS]  Version: clang-format version 22.1.1
  [PASS]  Config: .../config/.clang-format
  [PASS]  Hook installed
  [PASS]  Badly formatted code correctly flagged
  [PASS]  Well-formatted code accepted with no changes
  [PASS]  In-place formatting produced correct output
  Results: 8 passed | 0 failed | 0 skipped
```

---

## Configuration

### Per-developer overrides

`bootstrap.sh` creates `clang-llvm-style-formatter/.llvm-hooks-local/hooks.conf`:

```bash
# Enable clang-tidy (requires compile_commands.json from CMake)
ENABLE_TIDY="true"

# Use a system-installed clang-format instead of the vendored build
CLANG_FORMAT_BIN="/usr/bin/clang-format-17"

# Show per-file diffs when a commit is rejected
VERBOSE="true"
```

### Style rules

Edit `config/.clang-format` and `config/.clang-tidy` in this directory.
Host repos pick up changes on the next `git submodule update --remote`.

---

## Keeping the Formatter Up to Date

```bash
# In the consuming project — pull latest formatter
git submodule update --remote clang-llvm-style-formatter
git add clang-llvm-style-formatter
git commit -m "chore: update clang-llvm-style-formatter"
git push
```

---

## Updating the Vendored LLVM Version (Maintainers Only)

```bash
# On a machine with internet access:
bash clang-llvm-style-formatter/scripts/fetch-llvm-source.sh --version 23.x.x

# Split if needed for git hosting file size limits:
bash clang-llvm-style-formatter/scripts/split-llvm-tarball.sh

git add clang-llvm-style-formatter/llvm-src/
git commit -m "vendor: update LLVM to 23.x.x"
git push
```

Developers get the update on next `git pull` and rebuild via:
```bash
bash clang-llvm-style-formatter/scripts/build-clang-format.sh --rebuild
```

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | **Start here** — one-command developer setup |
| `hooks/pre-commit` | Pre-commit gate logic |
| `config/.clang-format` | LLVM style rules |
| `config/.clang-tidy` | Static analysis rules |
| `config/hooks.conf` | Runtime configuration defaults |
| `bin/windows/clang-format.exe` | Built binary — generated, not committed |
| `bin/linux/clang-format` | Built binary — generated, not committed |
| `llvm-src/*.part-*` | Vendored LLVM 22.1.1 source (split, committed) |
| `ninja-src/ninja-1.13.2.tar.gz` | Vendored Ninja source (committed) |
| `scripts/build-clang-format.sh` | Compile clang-format from vendored source |
| `scripts/extract-llvm-source.sh` | Extract and restructure the LLVM tarball |
| `scripts/build-ninja.sh` | Compile Ninja from vendored source |
| `scripts/smoke-test.sh` | Verify the full pipeline end-to-end |
| `scripts/fix-format.sh` | Auto-format and re-stage failing files |
| `scripts/install-hooks.sh` | Wire the hook into a host repo |
| `scripts/verify-tools.sh` | Diagnostic: show tool locations and versions |
| `scripts/split-llvm-tarball.sh` | **[Maintainer]** Split tarball for git hosting limits |
| `scripts/fetch-llvm-source.sh` | **[Maintainer]** Update vendored LLVM tarball |
| [`docs/llvm-install-guide.md`](docs/llvm-install-guide.md) | Build prerequisites and troubleshooting per platform |

---

## Supported Environments

| Environment | Status |
|-------------|--------|
| Windows 11 + Git Bash (MINGW64) | Supported |
| RHEL 8 + Bash 4.x | Supported |
| Visual Studio 2017 / 2019 / 2022 / Insider | Supported |
| VxWorks Workbench | Hook runs on host OS shell; target unaffected |