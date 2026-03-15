# clang-llvm-source-build

> **Optional** — builds clang-format from LLVM source (~30-60 min).
> Most developers should use the faster pip method instead.

## When to use this

Use this only if:
- Python is not available on developer machines
- Policy requires all tools to be built from source

For everyone else:
```bash
bash clang-llvm-style-formatter/bootstrap.sh   # ~5 seconds
```

## Usage
```bash
bash clang-llvm-source-build/bootstrap.sh
```

The compiled binary is placed at `bin/windows/clang-format.exe` or `bin/linux/clang-format`. `clang-llvm-style-formatter/bootstrap.sh` detects it automatically on its next run.

## Build Prerequisites

| Platform | Requirements |
|----------|-------------|
| Windows 11 | Visual Studio 2017/2019/2022 (C++ workload), CMake 3.14+ |
| RHEL 8 | `sudo dnf install gcc-c++ cmake python3` |

See `docs/llvm-install-guide.md` for detailed instructions.

## Structure
```
clang-llvm-source-build/
├── bootstrap.sh              ← start here
├── llvm-src/                 ← vendored LLVM 22.1.1 source (split parts)
├── ninja-src/                ← vendored Ninja 1.13.2 source
├── bin/
│   ├── windows/clang-format.exe   ← built output (not committed)
│   └── linux/clang-format         ← built output (not committed)
├── docs/llvm-install-guide.md
└── scripts/
    ├── build-clang-format.sh
    ├── build-ninja.sh
    ├── extract-llvm-source.sh
    ├── fetch-llvm-source.sh      ← [Maintainer] update LLVM tarball
    └── split-llvm-tarball.sh     ← [Maintainer] split for git hosting
```
