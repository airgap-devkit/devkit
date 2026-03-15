# clang-llvm-style-formatter

> Pre-commit hook enforcement of [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)
> for C/C++ repositories — designed for air-gapped, multi-repo, multi-platform environments.

---

## Overview

Installs `clang-format` from a vendored Python wheel and wires a pre-commit
hook that rejects commits violating LLVM C++ style.

**Fast path: ~5 seconds. No compiler. No Visual Studio. No CMake.**

If Python is unavailable, see [`../clang-llvm-source-build/`](../clang-llvm-source-build/README.md)
for the LLVM source build option.

---

## Developer Onboarding (run once after cloning)

```bash
bash clang-llvm-style-formatter/bootstrap.sh
```

| Step | What happens |
|------|-------------|
| 1 | Git submodules initialised |
| 2 | Checks for `clang-format` in venv, source-build bin/, or PATH |
| 3 | If not found: installs from vendored `.whl` file via pip/venv (~5 sec) |
| 4 | Pre-commit hook installed into `.git/hooks/pre-commit` |

**No network access required. No admin rights required.**

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git Bash |
| RHEL 8 | Python 3.8+, Bash 4.x |

---

## Adding to a New Repository (maintainer, done once)

```bash
cd your-cpp-project/
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

```bash
bash clang-llvm-style-formatter/scripts/smoke-test.sh
```

Expected:
```
  Results: 8 passed | 0 failed | 0 skipped
  All tests passed. The formatter is working correctly.
```

---

## Configuration

`bootstrap.sh` creates `.llvm-hooks-local/hooks.conf` inside this directory:

```bash
# Enable clang-tidy (requires compile_commands.json from CMake)
ENABLE_TIDY="true"

# Override clang-format binary path
CLANG_FORMAT_BIN="/usr/bin/clang-format-17"

# Show per-file diffs when a commit is rejected
VERBOSE="true"
```

Style rules live in `config/.clang-format` and `config/.clang-tidy`.
Consuming repos pick up changes on the next `git submodule update --remote`.

---

## Updating Wheels (Maintainers Only)

On a machine with internet access:

```bash
bash clang-llvm-style-formatter/scripts/fetch-wheels.sh --version 23.x.x
git add python-packages/
git commit -m "vendor: update clang-format wheels to 23.x.x"
git push
```

Developers get the update on next `git pull` — `bootstrap.sh` reinstalls
automatically on next run.

---

## clang-format Not Available via pip?

If Python is unavailable on developer machines, build from LLVM source:

```bash
bash clang-llvm-source-build/bootstrap.sh
```

See [`../clang-llvm-source-build/README.md`](../clang-llvm-source-build/README.md).
After the build completes, run `bootstrap.sh` here — it detects the binary automatically.

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | **Start here** — pip/venv install + hook setup |
| `python-packages/` | Vendored `.whl` files for offline install |
| `hooks/pre-commit` | Pre-commit gate logic |
| `config/.clang-format` | LLVM style rules |
| `config/.clang-tidy` | Static analysis rules |
| `config/hooks.conf` | Runtime configuration defaults |
| `scripts/install-venv.sh` | Creates venv, installs from wheel |
| `scripts/fetch-wheels.sh` | **[Maintainer]** Download wheels for new version |
| `scripts/smoke-test.sh` | Verify full pipeline end-to-end |
| `scripts/fix-format.sh` | Auto-format and re-stage failing files |
| `scripts/install-hooks.sh` | Wire hook into a host repo |
| `scripts/verify-tools.sh` | Diagnostic: show tool locations and versions |

---

## Supported Environments

| Environment | Status |
|-------------|--------|
| Windows 11 + Git Bash (MINGW64) | Supported |
| RHEL 8 + Bash 4.x | Supported |
| Visual Studio 2017 / 2019 / 2022 / Insider | Supported (hook runs via Git) |
| VxWorks Workbench | Hook runs on host OS shell; target unaffected |