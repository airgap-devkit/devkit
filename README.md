# airgap-cpp-devkit

Air-gapped C++ developer toolkit for network-restricted environments.

Tools that work without internet access, without admin rights, and without
pre-installed binaries. All dependencies are vendored and installed locally.

---

## Tools

| Directory | Purpose |
|-----------|---------|
| [`clang-llvm-style-formatter/`](clang-llvm-style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook |
| [`clang-llvm-source-build/`](clang-llvm-source-build/README.md) | Optional: builds clang-format from LLVM source (~30-60 min) |
| [`git-bundle/`](git-bundle/README.md) | Transfers Git repositories with nested submodules across air-gapped boundaries |

---

## Quick Start — New Developer Setup

Run this once after cloning:

```bash
git clone <this-repo-url>
cd airgap-cpp-devkit
bash clang-llvm-style-formatter/bootstrap.sh
```

Bootstrap will:
- Check if `clang-format` is already available
- If not: install it from vendored Python wheels in `python-packages/` (~5 seconds)
- Install the pre-commit hook into `.git/hooks/pre-commit`

From that point on, every `git commit` automatically enforces LLVM C++ style.

### Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git Bash |
| RHEL 8 | Python 3.8+, Bash 4.x |

No compiler, no Visual Studio, no CMake required for the standard install.

---

## Install Methods

### Method 1 — pip/venv (recommended, ~5 seconds)

```bash
bash clang-llvm-style-formatter/bootstrap.sh
```

Installs `clang-format` from a vendored `.whl` file into a local Python venv.
No network access. No compiler. No admin rights.

### Method 2 — Build from LLVM source (optional, ~30-60 minutes)

```bash
bash clang-llvm-source-build/bootstrap.sh
```

Compiles `clang-format` from the vendored LLVM 22.1.1 source tarball.
Use this only if Python is unavailable or policy requires source builds.
Requires: Visual Studio (Windows) or GCC (Linux), CMake 3.14+.

After the source build completes, run `clang-llvm-style-formatter/bootstrap.sh`
to install the pre-commit hook — it detects the compiled binary automatically.

---

## Using the Formatter in Your Own Project

When deploying to a separate production repository on Bitbucket:

### Step 1 — Add as a submodule (maintainer, done once)

```bash
cd your-cpp-project/
git submodule add https://bitbucket.your-org.com/your-team/clang-llvm-style-formatter.git clang-llvm-style-formatter
git submodule update --init --recursive
git add .gitmodules clang-llvm-style-formatter
git commit -m "chore: add LLVM style enforcement submodule"
git push
```

### Step 2 — Each developer runs once after cloning

```bash
git clone <your-cpp-project-url>
cd your-cpp-project
git submodule update --init --recursive
bash clang-llvm-style-formatter/bootstrap.sh
```

The consuming project needs nothing else — no `.clang-format` at the root,
no extra config. The hook references all rules inside the submodule directly.

### Keeping the submodule up to date

```bash
git submodule update --remote clang-llvm-style-formatter
git add clang-llvm-style-formatter
git commit -m "chore: update clang-llvm-style-formatter"
git push
```

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo (wheels + source tarballs) |
| No pre-built binaries committed | pip wheel installs at bootstrap time; source build is optional |
| No admin rights | Installs to per-user/per-repo paths only |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Sysadmin friendly | Single bootstrap command, clear progress output |

---

## Repository Structure

```
airgap-cpp-devkit/
├── README.md                              ← you are here
│
├── clang-llvm-style-formatter/            ← LLVM style enforcement (pip method)
│   ├── bootstrap.sh                       ← start here — installs via pip/venv
│   ├── python-packages/                   ← vendored .whl files (committed)
│   │   ├── clang_format-22.1.1-*-win_amd64.whl
│   │   ├── clang_format-22.1.1-*-manylinux*.whl
│   │   └── pip-*.whl
│   ├── .venv/                             ← created by bootstrap, not committed
│   ├── config/
│   │   ├── .clang-format                  ← LLVM style rules
│   │   ├── .clang-tidy                    ← static analysis rules
│   │   └── hooks.conf                     ← runtime toggles
│   ├── hooks/pre-commit                   ← the enforcement hook
│   └── scripts/
│       ├── install-venv.sh                ← creates venv, installs wheel
│       ├── fetch-wheels.sh                ← [Maintainer] update wheels
│       ├── smoke-test.sh                  ← verify full pipeline
│       ├── fix-format.sh                  ← auto-format staged files
│       └── install-hooks.sh              ← wire hook into host repo
│
├── clang-llvm-source-build/               ← optional LLVM source build
│   ├── bootstrap.sh                       ← builds clang-format from source
│   ├── llvm-src/                          ← vendored LLVM 22.1.1 (split parts)
│   ├── ninja-src/                         ← vendored Ninja 1.13.2
│   ├── bin/
│   │   ├── windows/clang-format.exe       ← built output, not committed
│   │   └── linux/clang-format             ← built output, not committed
│   ├── docs/llvm-install-guide.md
│   └── scripts/
│       ├── build-clang-format.sh
│       ├── build-ninja.sh
│       ├── extract-llvm-source.sh
│       ├── fetch-llvm-source.sh           ← [Maintainer] update LLVM tarball
│       └── split-llvm-tarball.sh          ← [Maintainer] split for git hosting
│
└── git-bundle/                            ← air-gap transfer tool
    ├── bundle.py                          ← export side
    ├── export.py                          ← import side
    └── tests/                             ← test harness
```