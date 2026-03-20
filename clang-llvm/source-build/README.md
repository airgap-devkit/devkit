# clang-llvm-source-build

### Author: Nima Shafie

> **Optional** — builds `clang-format` from LLVM source (~30-60 minutes) and
> installs a pre-built `clang-tidy` binary (reassemble + verify, Linux only).
>
> Most developers should use the faster pip method for clang-format instead:
> ```bash
> bash clang-llvm-style-formatter/bootstrap.sh   # ~5 seconds
> ```

---

## When to Use This

| Scenario | Recommended method |
|----------|-------------------|
| Python 3.8+ available | `clang-llvm-style-formatter/bootstrap.sh` (pip) |
| Python unavailable | `clang-llvm-source-build/bootstrap.sh` (this) |
| Policy requires source builds | `clang-llvm-source-build/bootstrap.sh` (this) |
| Need clang-tidy on Linux | `clang-llvm-source-build/bootstrap.sh` (this) |

---

## Usage

```bash
bash clang-llvm-source-build/bootstrap.sh
```

On Linux, this does two things:

1. **Builds `clang-format`** from the vendored LLVM 22.1.1 source (~30-60 min)
2. **Installs `clang-tidy`** from the vendored pre-built binary — reassembles
   the split parts and verifies the SHA256 against `manifest.json` (seconds)

On Windows, only `clang-format` is produced. No pre-built `clang-tidy` binary
is currently vendored for Windows.

The binaries are placed at:
- `bin/linux/clang-format`
- `bin/linux/clang-tidy`
- `bin/windows/clang-format.exe`

`clang-llvm-style-formatter/bootstrap.sh` detects these binaries automatically.
After this script completes, run the formatter bootstrap to install the hook:

```bash
bash clang-llvm-style-formatter/bootstrap.sh
```

To force a full rebuild and re-verification:

```bash
bash clang-llvm-source-build/bootstrap.sh --rebuild
```

---

## Build Prerequisites

### Windows 11

| Tool | Minimum | Notes |
|------|---------|-------|
| Visual Studio | 2017 / 2019 / 2022 / Insider | With "Desktop development with C++" workload |
| CMake | 3.14+ | Bundled with VS 2019+ |
| Git Bash | Any | Run bootstrap from Git Bash, not cmd.exe |

### RHEL 8

```bash
sudo dnf install gcc-c++ cmake python3
```

See [`docs/llvm-install-guide.md`](docs/llvm-install-guide.md) for detailed
instructions, troubleshooting, and known platform issues.

---

## How It Works

### clang-format (source build, both platforms)

1. Checks for an existing binary — skips rebuild if found (use `--rebuild` to override)
2. Runs `scripts/build-ninja.sh` — builds Ninja from `ninja-src/` (~30 sec)
3. Runs `scripts/extract-llvm-source.sh` — reassembles the split tarball and extracts (~5-15 min)
4. Runs `scripts/build-clang-format.sh` — compiles clang-format with CMake + Ninja (~30-60 min)
5. Binary placed in `bin/<platform>/clang-format[.exe]`

### clang-tidy (pre-built, Linux only)

1. Checks for an existing binary — skips if found (use `--rebuild` to override)
2. Runs `scripts/reassemble-clang-tidy.sh`:
   - Verifies each split part against SHA256 in `manifest.json`
   - Reassembles `clang-tidy.part-aa` + `clang-tidy.part-ab` → `clang-tidy`
   - Verifies the assembled binary SHA256 against `manifest.json`
   - Sets executable bit
3. Binary placed in `bin/linux/clang-tidy`

The clang-tidy binary was built from the same LLVM 22.1.1 source on RHEL 8
x86_64, stripped, and committed as split parts to stay under git hosting
file size limits.

---

## Using clang-tidy

After bootstrapping, the binary is at `bin/linux/clang-tidy`. A minimal usage
example and a C++ file with intentional issues are in `demo/`:

```bash
bash clang-llvm-source-build/demo/run-demo.sh
```

This compiles a sample file, runs `clang-tidy` against it, and shows the
diagnostics output. See [`demo/README.md`](demo/README.md) for details.

---

## Updating the Vendored LLVM Version (Maintainers Only)

On a machine with internet access:

```bash
# Download new tarball
bash clang-llvm-source-build/scripts/fetch-llvm-source.sh --version 23.x.x

# Split for git hosting file size limits (GitHub: 100 MB max)
bash clang-llvm-source-build/scripts/split-llvm-tarball.sh

git add clang-llvm-source-build/llvm-src/
git commit -m "vendor: update LLVM to 23.x.x"
git push
```

Developers rebuild with:
```bash
bash clang-llvm-source-build/bootstrap.sh --rebuild
```

## Updating the Vendored clang-tidy Binary (Maintainers Only)

Build `clang-tidy` from LLVM source on a RHEL 8 x86_64 machine, then split
and update the manifest:

```bash
# After a successful source build, strip and split the binary
strip bin/linux/clang-tidy
split -b 52428800 bin/linux/clang-tidy bin/linux/clang-tidy.part-

# Compute hashes for manifest.json
sha256sum bin/linux/clang-tidy
sha256sum bin/linux/clang-tidy.part-aa bin/linux/clang-tidy.part-ab

# Update manifest.json clang_tidy block with new hashes, then commit
git add bin/linux/clang-tidy.part-* manifest.json
git commit -m "vendor: update clang-tidy to LLVM 23.x.x (linux-x86_64)"
git push
```

---

## File Reference

| Path | Purpose |
|------|---------|
| `bootstrap.sh` | **Start here** — orchestrates the full build and install |
| `manifest.json` | SHA256 pins for all vendored archives and binaries |
| `llvm-src/*.part-*` | Vendored LLVM 22.1.1 source (split, committed) |
| `ninja-src/ninja-1.13.2.tar.gz` | Vendored Ninja source (committed) |
| `bin/linux/clang-format` | Built output — generated, not committed |
| `bin/linux/clang-tidy` | Assembled from parts — generated, not committed |
| `bin/linux/clang-tidy.part-aa` | Pre-built binary split part 1 (committed, ~52 MB) |
| `bin/linux/clang-tidy.part-ab` | Pre-built binary split part 2 (committed, ~31 MB) |
| `bin/linux/ninja` | Built output — generated, not committed |
| `bin/windows/clang-format.exe` | Built output — generated, not committed |
| `demo/` | clang-tidy demonstration — sample C++ file and runner |
| `docs/llvm-install-guide.md` | Prerequisites and troubleshooting |
| `scripts/build-clang-format.sh` | Compile clang-format from vendored source |
| `scripts/build-ninja.sh` | Compile Ninja from vendored source |
| `scripts/extract-llvm-source.sh` | Extract and restructure the LLVM tarball |
| `scripts/reassemble-clang-tidy.sh` | Verify parts + assemble clang-tidy binary |
| `scripts/verify-sources.sh` | SHA256 check all vendored archives and binaries |
| `scripts/fetch-llvm-source.sh` | **[Maintainer]** Update vendored LLVM tarball |
| `scripts/split-llvm-tarball.sh` | **[Maintainer]** Split tarball for git hosting limits |