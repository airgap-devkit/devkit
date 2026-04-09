# Tools Inventory

**Author: Nima Shafie**

Complete list of everything included in `airgap-cpp-devkit`.
All tools work without internet access. All dependencies are vendored.

> **Prebuilt available?** - If yes, no compiler or build tools required.
> Just extract and use. See each tool's README for details.

---

## Toolchains

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **clang-format** | 22.1.2 | Windows + Linux | Yes | `toolchains/clang/source-build/` |
| **clang-tidy** | 22.1.2 | Windows + Linux | Yes | `toolchains/clang/source-build/` |
| **LLVM source** | 22.1.2 | Windows + Linux | - (source only) | `toolchains/clang/source-build/llvm-src/` |
| **llvm-mingw** | 20260324 | Windows + Linux | Yes | `prebuilt-binaries/toolchains/clang/mingw/` |
| **Clang RPMs** | 20.1.8 | RHEL 8 | Yes | `prebuilt-binaries/toolchains/clang/rhel8/` |
| **GCC + MinGW-w64** | 15.2.0 + 13.0.0 UCRT | Windows | Yes | `toolchains/gcc/windows/` |
| **gcc-toolset** | 15 | RHEL 8 | Yes | `prebuilt-binaries/toolchains/gcc/linux/` |
| **GCC cross (x86_64-bionic)** | 15 | Linux | Yes | `toolchains/gcc/linux/cross/` |
| **GCC native (RHEL 8)** | 15 | RHEL 8 | Yes | `toolchains/gcc/linux/native/` |

---

## Build Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **CMake** | 4.3.1 | Windows + Linux | Yes | `build-tools/cmake/` |
| **Ninja** | 1.13.2 | Windows + Linux | Yes | `prebuilt-binaries/toolchains/clang/source-build/` |
| **lcov** | 2.4 | Linux / RHEL 8 | Yes (vendored tarball) | `build-tools/lcov/` |

---

## Frameworks

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **gRPC** | 1.78.1 | Windows | Yes (.7z 69MB) | `frameworks/grpc/` |
| **gRPC source bundle** | 1.78.1 | Windows | - (source build ~40 min) | `frameworks/grpc/vendor/` |

gRPC prebuilt includes: `bin/` (protoc, grpc_cpp_plugin, all plugins), `include/`, `lib/` (static), `share/` (cmake config).

---

## Languages

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **Python** | 3.14.4 | Windows (embeddable) | Yes (single file ~12 MB) | `languages/python/` |
| **Python** | 3.14.4 | Linux x86_64 | Yes (tar.gz, 2 parts) | `languages/python/` |
| **.NET SDK** | 10.0.201 | Windows x64 | Yes (.7z 148MB) | `languages/dotnet/` |
| **.NET SDK** | 10.0.201 | Linux x64 | Yes (.tar.gz 231MB) | `languages/dotnet/` |

---

## Developer Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **7-Zip** | 26.00 | Windows + Linux | Yes | `dev-tools/7zip/` |
| **Servy** | 7.8 | Windows | Yes (single file ~80 MB) | `dev-tools/servy/` |
| **Conan** | 2.27.0 | Windows + Linux | Yes (self-contained) | `dev-tools/conan/` |
| **VS Code extensions** | Various | Windows + Linux | Yes (.vsix) | `dev-tools/vscode-extensions/` |
| **git-bundle transfer tool** | - | Windows + Linux | - (Python scripts) | `dev-tools/git-bundle/` |
| **LLVM style formatter** | 22.1.2 | Windows + Linux | Yes (via pip wheel) | `toolchains/clang/style-formatter/` |

---

## VS Code Extensions

| Extension | Version | Platform |
|-----------|---------|----------|
| ms-vscode.cpptools-extension-pack | 1.5.1 | Any |
| ms-vscode.cpptools | 1.30.4 | win32-x64 + linux-x64 |
| matepek.vscode-catch2-test-adapter | 4.22.3 | Any |
| ms-python.python | 2026.5.x | win32-x64 + linux-x64 |

---

## Python Pip Packages

All packages are vendored as `.whl` files in `languages/python/pip-packages/`
and installed offline by `languages/python/setup.sh`. No internet access required.

| Package | Version | License | Purpose |
|---------|---------|---------|---------|
| **numpy** | 2.4.4 | BSD-3-Clause | Numerical computing -- arrays, linear algebra, FFT |
| **pandas** | 3.0.2 | BSD-3-Clause | Data analysis -- DataFrames, CSV/Excel/SQL I/O |
| **plotly** | 6.6.0 | MIT | Interactive visualizations -- charts, dashboards |
| **streamlit** | 1.56.0 | Apache-2.0 | Data app framework -- web UIs in pure Python |
| **requests** | 2.32.3 | Apache-2.0 | HTTP client -- REST APIs, file downloads |
| **PyYAML** | 6.0.2 | MIT | YAML parsing -- config files, CI definitions |
| **Jinja2** | 3.1.5 | BSD-3-Clause | Templating -- used by Conan, CMake, code gen tools |
| **click** | 8.1.8 | BSD-3-Clause | CLI framework -- write devkit helper scripts |
| **rich** | 14.0.0 | MIT | Terminal output -- colored tables, progress bars |
| **pytest** | 8.3.5 | MIT | Test runner -- for Python scripts in the devkit |

---

## Prebuilt Binary Formats

Files above 100MB are split into parts for git compatibility.
Files under 100MB are stored as single files.

| Archive | Size | Parts | Notes |
|---------|------|-------|-------|
| gRPC 1.78.1 Windows x64 (.7z) | 69MB | 2 | split at 50MB (legacy) |
| gRPC 1.78.1 Windows x64 (.zip) | 162MB | 4 | split at 50MB (legacy) |
| WinLibs GCC 15.2.0 (.7z) | 107MB | 3 | split at 50MB (legacy) |
| WinLibs GCC 15.2.0 (.zip) | 254MB | 5 | split at 50MB (legacy) |
| llvm-mingw 20260324 (.zip) | 187MB | 4 | split at 50MB (legacy) |
| CMake 4.3.1 Linux tar.gz | 61MB | 1 | under 100MB -- no split |
| CMake 4.3.1 Windows zip | 51MB | 1 | under 100MB -- no split |
| Servy 7.8 portable .7z | 80MB | 1 | under 100MB -- no split |
| Conan 2.27.0 Windows zip | 15MB | 1 | under 100MB -- no split |
| Conan 2.27.0 Linux tgz | 27MB | 1 | under 100MB -- no split |
| Python 3.14.4 Windows embed | 12MB | 1 | under 100MB -- no split |
| Python 3.14.4 Linux standalone | 120MB | 2 | split at 99MB |

---

## Platform Support Matrix

| Tool | Windows 11 | RHEL 8 | Notes |
|------|-----------|--------|-------|
| clang-format / clang-tidy | Yes | Yes | Prebuilt for both |
| llvm-mingw | Yes | Yes | Cross-compile toolchain |
| GCC + MinGW-w64 | Yes | - | Windows native toolchain |
| gcc-toolset 15 | - | Yes | RHEL 8 RPMs |
| GCC cross/native | - | Yes | Linux only |
| CMake 4.3.1 | Yes | Yes | Prebuilt for both |
| Ninja | Yes | Yes | Prebuilt for both |
| gRPC 1.78.1 | Yes | - | Windows MSVC build only |
| Python 3.14.4 | Yes | Yes | Different packages per platform |
| .NET SDK 10.0.201 | Yes | Yes | Portable, no installer |
| 7-Zip 26.00 | Yes | Yes | Admin + user install |
| Servy 7.8 | Yes | - | Windows only, graceful no-op on Linux |
| Conan 2.27.0 | Yes | Yes | Self-contained, no Python required |
| VS Code extensions | Yes | Yes | Per-platform .vsix files |
| git-bundle tool | Yes | Yes | Pure Python, no deps |
| LLVM style formatter | Yes | Yes | Git pre-commit hook |
| lcov 2.4 | - | Yes | Linux/RHEL 8 only |

---

## Quick Install Reference

```bash
# Formatter + style enforcement (fastest, ~5 seconds)
bash toolchains/clang/style-formatter/setup.sh

# clang-format + clang-tidy prebuilt
bash toolchains/clang/source-build/setup.sh

# CMake 4.3.1
bash build-tools/cmake/setup.sh

# Python 3.14.4 + vendored pip packages
bash languages/python/setup.sh

# Conan 2.27.0
bash dev-tools/conan/setup.sh

# GCC 15.2.0 for Windows
bash toolchains/gcc/windows/setup.sh

# 7-Zip 26.00
bash dev-tools/7zip/setup.sh

# Servy 7.8 (Windows only)
bash dev-tools/servy/setup.sh

# gRPC 1.78.1 - prebuilt (Developer PowerShell)
cd frameworks\grpc && .\install-prebuilt.ps1 -version 1.78.1

# gRPC 1.78.1 - source build (~40 min, Developer PowerShell)
cd frameworks\grpc && .\setup.ps1 -version 1.78.1

# lcov 2.4 (Linux/RHEL 8 only)
bash build-tools/lcov/setup.sh
```

---

## Binary Policy

The **main repo contains no compiled binaries** (no `.exe`, `.dll`, `.msi`, or
pre-compiled object files). All binaries live exclusively in the
`prebuilt-binaries/` submodule, which can be skipped entirely in
binary-restricted environments.

Everything in the main repo is source code, shell scripts, PowerShell scripts,
vendored source archives (`.tar.gz`, `.tar.xz`), and split archive parts of
those source archives.