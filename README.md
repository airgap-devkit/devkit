# airgap-cpp-devkit

Air-gapped C++ developer toolkit for network-restricted environments.

Two self-contained tools that work without internet access, without admin
rights, and without pre-installed binaries. All dependencies are vendored
as source tarballs and built locally on first use.

---

## Tools

| Tool | Purpose |
|------|---------|
| [`clang-llvm-style-formatter/`](clang-llvm-style-formatter/README.md) | Enforces LLVM C++ coding standards via Git pre-commit hook |
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
- If not: ask to build it from vendored LLVM source (~30–60 min, one time only)
- Install the pre-commit hook into `.git/hooks/pre-commit`
- Run a smoke test to confirm everything works

From that point on, every `git commit` automatically enforces LLVM C++ style.

---

## Using `clang-llvm-style-formatter` in Your Own Project

When you are ready to use this formatter in a **separate production repository**,
add it as a Git submodule:

### Step 1 — Add the submodule (done once by a maintainer)

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

That is the complete onboarding. The pre-commit hook is now active.

### What the consuming project needs

```
your-cpp-project/
├── .git/
│   └── hooks/
│       └── pre-commit          ← installed by bootstrap.sh, references submodule
├── .gitmodules                 ← registers the submodule
└── clang-llvm-style-formatter/ ← the submodule (checked out)
    ├── bootstrap.sh
    ├── bin/windows/clang-format.exe   (built on first run)
    ├── bin/linux/clang-format         (built on first run)
    ├── config/.clang-format
    ├── hooks/pre-commit
    └── scripts/
```

The consuming project does **not** need to commit `.clang-format` at its root —
the hook references the style rules inside the submodule directly.

### Keeping the submodule up to date

```bash
# Pull latest formatter version
git submodule update --remote clang-llvm-style-formatter
git add clang-llvm-style-formatter
git commit -m "chore: update clang-llvm-style-formatter"
git push
```

---

## Design Principles

| Principle | How it is met |
|-----------|--------------|
| Air-gapped | All dependencies vendored in-repo as source tarballs |
| No pre-built binaries | Tools compile from source on first use |
| No admin rights | Installs to per-user/per-repo paths only |
| Cross-platform | Windows 11 (Git Bash / MINGW64) + RHEL 8 |
| Sysadmin friendly | Single bootstrap command, clear progress output |

---

## Build Requirements

### clang-llvm-style-formatter

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Visual Studio 2017/2019/2022 (C++ workload), CMake 3.14+, Git Bash |
| RHEL 8 | GCC 8+, CMake 3.14+, Python 3.6+ |

### git-bundle

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Python 3.8+, Git 2.20+ |
| RHEL 8 | Python 3.6+, Git 2.20+ |

---

## Repository Structure

```
airgap-cpp-devkit/
├── README.md                         ← you are here
├── clang-llvm-style-formatter/       ← LLVM style enforcement
│   ├── bootstrap.sh                  ← one-command developer setup
│   ├── bin/
│   │   ├── windows/clang-format.exe  ← built on first run (not committed)
│   │   └── linux/clang-format        ← built on first run (not committed)
│   ├── llvm-src/                     ← vendored LLVM 22.1.1 source (split parts)
│   ├── ninja-src/                    ← vendored Ninja 1.13.2 source
│   ├── config/
│   │   ├── .clang-format             ← LLVM style rules
│   │   ├── .clang-tidy               ← static analysis rules
│   │   └── hooks.conf                ← runtime toggles
│   ├── hooks/pre-commit              ← the enforcement hook
│   └── scripts/                      ← build, extract, smoke-test, fix-format
└── git-bundle/                       ← air-gap transfer tool
    ├── bundle.py                     ← export side
    ├── export.py                     ← import side
    └── tests/                        ← test harness
```