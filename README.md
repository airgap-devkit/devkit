# airgap-cpp-devkit

### Author: Nima Shafie

Air-gapped C++ developer toolkit for network-restricted environments.

All tools work without internet access. All dependencies are vendored.
Tools install to system-wide or per-user paths depending on available privileges.

---

## Deployment Scenarios

This devkit supports two deployment scenarios depending on what your
air-gapped network permits.

### Base Case — Pre-built binaries allowed

The fastest path. Pre-built binaries are available via the
`prebuilt-binaries` submodule. No compiler, no Visual Studio, no CMake
required for most tools.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
git submodule update --init --recursive   # includes prebuilt-binaries
bash clang-llvm/source-build/bootstrap.sh
bash clang-llvm/style-formatter/bootstrap.sh
```

### Worst Case — Binaries not permitted, source only

If your network prohibits pre-compiled binaries, skip the submodule and
build everything from the vendored source archives.

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
# Do NOT run: git submodule update --init --recursive
bash clang-llvm/source-build/bootstrap.sh --build-from-source
bash clang-llvm/style-formatter/bootstrap.sh
```

Each tool's bootstrap script detects which scenario applies and responds
accordingly. See [scripts/setup-prebuilt-submodule.sh](scripts/setup-prebuilt-submodule.sh)
for the interactive submodule setup helper.

---

## Install Modes

All bootstrap scripts detect whether the current user has admin/root
privileges and install to the appropriate path automatically.

| Mode | Windows | Linux |
|------|---------|-------|
| Admin (system-wide) | `C:\Program Files\airgap-cpp-devkit\<tool>\` | `/opt/airgap-cpp-devkit/<tool>/` |
| User (per-user) | `%LOCALAPPDATA%\airgap-cpp-devkit\<tool>\` | `~/.local/share/airgap-cpp-devkit/<tool>/` |

Admin mode is attempted first. If the current user cannot write to the
system path, user mode is used automatically with a clear warning printed
to the screen. An install receipt (`INSTALL_RECEIPT.txt`) and a timestamped
log file are always written regardless of install mode.

To install system-wide on Windows, right-click Git Bash and select
"Run as administrator" before running any bootstrap script.

---

## Tools

| Directory | Purpose | Required? |
|-----------|---------|-----------|
| [`clang-llvm/style-formatter/`](clang-llvm/style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook | Yes |
| [`clang-llvm/source-build/`](clang-llvm/source-build/README.md) | Builds clang-format + clang-tidy from LLVM 22.1.1 source; installs pre-built binaries (Windows: instant, Linux: ~30-60 min) | No |
| [`git-bundle/`](git-bundle/README.md) | Transfers Git repositories with nested submodules across air-gapped boundaries | Yes |
| [`lcov-source-build/`](lcov-source-build/README.md) | Code coverage reporting via lcov 2.4 + gcov, vendored Perl deps included | No |
| [`prebuilt/winlibs-gcc-ucrt/`](prebuilt/winlibs-gcc-ucrt/README.md) | GCC 15.2.0 + MinGW-w64 13.0.0 UCRT toolchain for Windows | **No — standalone** |
| [`grpc-source-build/`](grpc-source-build/README.md) | Vendored gRPC source build for Windows (v1.76.0 production-tested, v1.78.1 candidate) | **No — standalone** |
| [`prebuilt-binaries/`](https://github.com/NimaShafie/airgap-cpp-devkit-prebuilt) | Pre-built binary submodule (clang-format, clang-tidy, winlibs GCC) | **No — base case only** |

---

## Can I skip optional tools?

**Yes. All optional tools are fully independent.**

`prebuilt/winlibs-gcc-ucrt/` is a standalone GCC 15.2.0 toolchain for
developers who need to *compile C++ projects* in an air-gapped Windows
environment. It has no relationship to any other tool in this devkit.

`grpc-source-build/` is a standalone gRPC source tree for teams that need
gRPC in their air-gapped C++ projects. The bash entry point `setup_grpc.sh`
handles admin detection and install path selection; it delegates VS
environment initialization to the companion `setup_grpc.bat`.

`lcov-source-build/` provides code coverage reporting for C++ projects
compiled with GCC's `-fprofile-arcs -ftest-coverage` flags. It vendors
lcov 2.4 and all required Perl dependencies — no internet access, no CPAN,
no EPEL required.

`prebuilt-binaries/` is a git submodule containing pre-compiled binaries.
In binary-restricted environments, skip `git submodule update` entirely and
use `--build-from-source` instead.

If you only need the formatter and git transfer tool, ignore everything else.

---

## Who Reads What

### I am a developer on a production C++ repository

Your repo already has the formatter set up. Run one command after cloning:

```bash
bash setup.sh
```

See your repo's `setup.sh` or [clang-llvm/style-formatter/README.md](clang-llvm/style-formatter/README.md)
for the full developer reference.

### I am a maintainer adding the formatter to a new production repo

See [Deploying to Production Repositories](#deploying-to-production-repositories) below.

### I am working on the devkit itself

See [Development Setup](#development-setup) below.

---

## Deploying to Production Repositories

The formatter lives as a submodule under `tools/` in each production repo.
Developers only ever run `bash setup.sh`.

**What lands in each production repo:**
```
your-cpp-project/
├── setup.sh                              <- ~50 lines, the only new root file
├── .gitmodules                           <- 3-line auto-generated pointer
└── tools/
    └── style-formatter/                  <- submodule (a commit pointer, not a copy)
```

### Step 1 — Add the submodule (once per repo)

```bash
cd your-cpp-project/

git submodule add \
    https://bitbucket.your-org.com/your-team/airgap-cpp-devkit.git \
    tools/style-formatter

git submodule update --init --recursive
```

### Step 2 — Copy setup.sh into the repo root

```bash
cp tools/style-formatter/clang-llvm/style-formatter/docs/production-repo-template/setup.sh ./setup.sh
```

### Step 3 — Append .gitignore entries

```bash
cat tools/style-formatter/clang-llvm/style-formatter/docs/gitignore-snippet.txt >> .gitignore
```

### Step 4 — Commit and push

```bash
git add .gitmodules tools/style-formatter setup.sh .gitignore
git commit -m "chore: add LLVM C++ style enforcement"
git push
```

### What developers do after this (once per machine)

```bash
git clone <your-cpp-project-url>
cd your-cpp-project
bash setup.sh
```

Done. The hook is installed. Every subsequent `git commit` enforces LLVM style.

---

## Development Setup

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit

# Base case — initialize prebuilt-binaries submodule (if binaries are permitted)
bash scripts/setup-prebuilt-submodule.sh

# Install the formatter (fast, ~5 seconds)
bash clang-llvm/style-formatter/bootstrap.sh
```

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git Bash (MINGW64) |
| RHEL 8 | Python 3.8+, Bash 4.x |

No compiler, no Visual Studio, no CMake required for the standard install.
See each tool's README for source-build prerequisites.

### Install methods

**Method 1 — pip/venv for clang-format (recommended, ~5 seconds)**
```bash
bash clang-llvm/style-formatter/bootstrap.sh
```
Installs `clang-format` from a vendored `.whl` file into a local Python venv.
No network access. No compiler. No admin rights required (installs in-repo).

**Method 2 — clang-format + clang-tidy from vendored binaries (base case)**
```bash
# Initialize prebuilt-binaries submodule first
bash scripts/setup-prebuilt-submodule.sh
bash clang-llvm/source-build/bootstrap.sh
```
Verifies and installs pre-built binaries from the `prebuilt-binaries`
submodule. Windows: instant. Linux: reassembles clang-tidy from split parts.
Installs to system-wide or per-user path based on available privileges.

**Method 3 — Build from LLVM source (worst case / policy requirement)**
```bash
bash clang-llvm/source-build/bootstrap.sh --build-from-source
```
Compiles `clang-format` and `clang-tidy` from the vendored LLVM 22.1.1
source tarball (~30-120 minutes). Use when pre-built binaries are not
permitted or Python is unavailable.
Requires: Visual Studio 2022 (Windows, tested: VS Insiders 18, MSVC 14.50.35717)
or GCC 8+ (Linux). CMake 3.14+ on both platforms.

**Method 4 — GCC toolchain for Windows**
```bash
cd prebuilt/winlibs-gcc-ucrt
bash setup.sh x86_64
source scripts/env-setup.sh x86_64
```
Installs GCC 15.2.0 + MinGW-w64 13.0.0 UCRT from the `prebuilt-binaries`
submodule. Only needed if you require GCC to compile C++ projects on Windows.
Installs to system-wide or per-user path based on available privileges.

**Method 5 — gRPC for Windows**
```bash
cd grpc-source-build
bash setup_grpc.sh
```
Detects admin/user privileges, then builds gRPC from vendored source using
MSVC + CMake. Prompts for version selection (v1.76.0 or v1.78.1).
Requires: Visual Studio 2022 (any edition) with Desktop C++ workload, Git Bash.
Linux: not supported by this script (requires MSVC/Windows SDK).

**Method 6 — lcov code coverage (RHEL 8 / Linux)**
```bash
bash lcov-source-build/bootstrap.sh
source lcov-source-build/scripts/env-setup.sh
```
Installs lcov 2.4 and all Perl dependencies from vendored tarballs.
Installs to `/opt/airgap-cpp-devkit/lcov/` (admin) or
`~/.local/share/airgap-cpp-devkit/lcov/` (user).
No internet access, no CPAN, no EPEL required.

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo or in prebuilt-binaries submodule |
| Binary-restricted environments | Skip prebuilt-binaries submodule; build all tools from vendored source |
| Admin + user install support | Admin detection at runtime; system-wide or per-user install paths |
| Install transparency | Install receipt + timestamped log file written on every bootstrap |
| Minimal production footprint | One `setup.sh` + one submodule pointer per production repo |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Single entry point per tool | `bash bootstrap.sh` or `bash setup_grpc.sh` — nothing else required |
| Integrity verification | SHA256 pinned in `manifest.json` for all vendored archives and binaries |

---

## Repository Structure

```
airgap-cpp-devkit/
├── README.md                              <- you are here
├── sbom.spdx.json                         <- root aggregate SBOM (SPDX 2.3)
├── .gitmodules                            <- prebuilt-binaries submodule pointer
│
├── scripts/
│   ├── install-mode.sh                    <- shared admin/user detection library
│   ├── setup-prebuilt-submodule.sh        <- initialize prebuilt-binaries submodule
│   └── generate-sbom.sh                   <- regenerates all SBOM timestamps
│
├── prebuilt-binaries/                     <- SUBMODULE (separate repo, optional)
│   │                                         Skip entirely in binary-restricted envs
│   ├── clang-llvm/
│   │   ├── clang-format.exe               <- Windows pre-built (3.1 MB)
│   │   ├── clang-tidy.exe                 <- Windows pre-built (46 MB)
│   │   ├── clang-tidy.part-aa             <- Linux pre-built split part (~52 MB)
│   │   └── clang-tidy.part-ab             <- Linux pre-built split part (~31 MB)
│   └── winlibs-gcc-ucrt/
│       └── *.7z.part-*                    <- GCC toolchain split parts
│
├── clang-llvm/                            <- LLVM/Clang tooling group
│   ├── style-formatter/                   <- LLVM style enforcement tool
│   │   ├── bootstrap.sh                   <- core install (called by setup.sh)
│   │   ├── sbom.spdx.json                 <- SPDX 2.3 SBOM
│   │   ├── python-packages/               <- vendored .whl files (committed)
│   │   ├── config/
│   │   │   ├── .clang-format              <- LLVM style rules
│   │   │   ├── .clang-tidy                <- static analysis rules
│   │   │   └── hooks.conf                 <- runtime defaults
│   │   ├── hooks/pre-commit               <- the enforcement hook
│   │   ├── scripts/                       <- install, verify, fix helpers
│   │   └── docs/
│   │       ├── gitignore-snippet.txt      <- append to production repo .gitignore
│   │       └── production-repo-template/
│   │           ├── setup.sh               <- copy to production repo root
│   │           └── README.md              <- maintainer checklist
│   │
│   └── source-build/                      <- clang-format + clang-tidy build/install
│       ├── bootstrap.sh                   <- entry point (base case + worst case)
│       ├── manifest.json                  <- SHA256 pins for LLVM + Ninja + binaries
│       ├── sbom.spdx.json                 <- SPDX 2.3 SBOM
│       ├── demo/                          <- clang-tidy demo with intentional issues
│       ├── llvm-src/                      <- vendored LLVM 22.1.1 (split parts)
│       │   ├── llvm-project-22.1.1.src.tar.xz.part-aa
│       │   └── llvm-project-22.1.1.src.tar.xz.part-ab
│       ├── ninja-src/                     <- vendored Ninja 1.13.2 source
│       │   └── ninja-1.13.2.tar.gz
│       ├── bin/
│       │   ├── windows/                   <- local build output (not committed)
│       │   └── linux/                     <- local build output (not committed)
│       └── scripts/
│           ├── build-clang-format.sh      <- compile clang-format from source
│           ├── build-clang-tidy.sh        <- compile clang-tidy from source
│           ├── build-ninja.sh             <- compile Ninja from source
│           ├── extract-llvm-source.sh     <- extract LLVM tarball
│           ├── reassemble-clang-tidy.sh   <- assemble Linux clang-tidy from parts
│           ├── reassemble-llvm.sh         <- join LLVM parts into tarball
│           ├── verify-clang-format-windows.sh <- verify pre-built clang-format.exe
│           ├── verify-clang-tidy-windows.sh   <- verify pre-built clang-tidy.exe
│           └── verify-sources.sh          <- SHA256 check all vendored archives
│
├── git-bundle/                            <- air-gap git transfer tool
│   ├── bundle.py
│   ├── export.py
│   ├── sbom.spdx.json                     <- SPDX 2.3 SBOM
│   └── tests/
│
├── lcov-source-build/                     <- code coverage reporting (Linux)
│   ├── bootstrap.sh                       <- extracts, installs, writes receipt
│   ├── manifest.json                      <- SHA256 pins for lcov + perl-libs
│   ├── sbom.spdx.json                     <- SPDX 2.3 SBOM
│   ├── scripts/
│   │   ├── download.sh                    <- internet machine: populate vendor/
│   │   ├── verify.sh                      <- SHA256 + version check
│   │   └── env-setup.sh                   <- source to activate lcov in shell
│   └── vendor/
│       ├── lcov-2.4.tar.gz                <- vendored lcov 2.4 (committed, 1.1 MB)
│       └── perl-libs.tar.gz               <- vendored Perl deps (committed, 4.6 MB)
│
├── prebuilt/                              <- source entry points for prebuilt tools
│   └── winlibs-gcc-ucrt/                  <- GCC 15.2.0 + MinGW-w64 13.0.0 UCRT
│       ├── setup.sh                       <- entry point: verify + reassemble + install
│       ├── manifest.json                  <- SHA256 pins (dual-source verified)
│       ├── sbom.spdx.json                 <- SPDX 2.3 SBOM
│       ├── scripts/
│       │   ├── verify.sh                  <- offline integrity check
│       │   ├── reassemble.sh              <- joins split parts into .7z
│       │   ├── install.sh                 <- extracts toolchain to install path
│       │   └── env-setup.sh               <- source to activate in current shell
│       └── vendor/                        <- assembled .7z (generated, gitignored)
│
└── grpc-source-build/                     <- gRPC source build (Windows only)
    ├── setup_grpc.sh                      <- bash entry point: admin detection + logging
    ├── setup_grpc.bat                     <- VS init + CMake build (called by .sh)
    ├── manifest.json                      <- SHA256 pins for all vendored versions
    ├── sbom.spdx.json                     <- SPDX 2.3 SBOM (pending)
    ├── README.md
    ├── scripts/
    │   ├── verify.sh                      <- offline integrity check (accepts version arg)
    │   └── reassemble.sh                  <- joins parts into tarball (accepts version arg)
    └── vendor/                            <- split .tar.gz parts committed to git
        ├── grpc-1.76.0.tar.gz.part-aa     <- ~89MB (production-tested)
        └── grpc-1.78.1.tar.gz.part-aa     <- ~15MB (candidate-testing)
```