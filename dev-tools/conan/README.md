# Conan 2.27.0 -- Prebuilt Module

Vendors [Conan 2.27.0](https://github.com/conan-io/conan) for air-gapped environments.
Conan is the open-source C/C++ package manager. Self-contained executables for Windows
and Linux -- no Python runtime required.

## Vendored Assets

Both files are stored as single files in `prebuilt-binaries/dev-tools/conan/` (under 100MB):

| File | Size | Platform | Description |
|------|------|----------|-------------|
| `conan-2.27.0-windows-x86_64.zip` | ~15 MB | Windows x64 | Self-contained bundle, no Python needed |
| `conan-2.27.0-linux-x86_64.tgz` | ~27 MB | Linux x86_64 | Self-contained executable, no Python needed |

SHA256 hashes:
- Windows: `9ec5eb2351c187cebcf674c46246e29d09fca4a6f87284a3d3d08b03e4d3fc44`
- Linux:   `2f96e3a820c8558781be38f5c85e7c54e1ab4215c99bc65e2279bd2b41dbb77a`

## Install Matrix

| Mode | Windows | Linux |
|------|---------|-------|
| **Admin** | `C:\Program Files\airgap-cpp-devkit\conan\bin\` | `/opt/airgap-cpp-devkit/conan/bin/` |
| **User** | `%LOCALAPPDATA%\airgap-cpp-devkit\conan\bin\` | `~/.local/share/airgap-cpp-devkit/conan/bin/` |

PATH is registered automatically at the appropriate scope.

## Usage

```bash
# From repo root -- install mode is auto-detected
bash dev-tools/conan/setup.sh

# Force a custom prefix
bash dev-tools/conan/setup.sh --prefix "/opt/my-conan"
```

## Quick Start (after install)

```bash
# Verify
conan --version

# Detect build environment and create default profile
conan profile detect

# Install dependencies declared in conanfile.txt
conan install . --build=missing
```

## Air-Gap Workflow

On a networked machine, save the package cache:

```bash
conan cache save "*" --file conan-cache-bundle.tgz
```

Transfer the bundle to the air-gapped machine, then restore:

```bash
conan cache restore conan-cache-bundle.tgz
conan install . --build=missing
```

## Integration with CMake

```bash
# Generate CMake toolchain and dependency files
conan install . --output-folder=build --build=missing

# Build using Conan-generated toolchain
cmake -B build -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake
cmake --build build --parallel
```

## Upstream

- Version: 2.27.0 (2026-03-25)
- License: MIT
- Source: https://github.com/conan-io/conan
- Release: https://github.com/conan-io/conan/releases/tag/2.27.0
- Docs: https://docs.conan.io/2/