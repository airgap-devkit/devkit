# Manual Installation Guide

Use this guide when the devkit-ui web application cannot complete an installation
due to an OS integration error (permission issue, bash not found, process fork
failure, etc.).  All steps work completely offline.

---

## Quick start

Open a terminal (**Git Bash on Windows**, plain bash on Linux), navigate to the
devkit root, and run:

```bash
# List available tools
bash scripts/manual-install.sh --list

# Install a specific tool
bash scripts/manual-install.sh --tool cmake
bash scripts/manual-install.sh --tool toolchains/llvm

# Install to a custom location
bash scripts/manual-install.sh --tool cmake --prefix /c/custom/cmake

# Verify split-archive parts are present without installing
bash scripts/manual-install.sh --tool toolchains/llvm --verify-only
```

The script finds the correct `setup.sh` for the tool, sets up the required
environment variables, and delegates to it — handling split archives automatically.

---

## Step-by-step (any tool)

### Windows — Git Bash (MINGW64)

> **Important**: all commands must run in **Git Bash**, not PowerShell or
> Command Prompt.  Open it via Start → *Git Bash* or right-click a folder →
> *Git Bash Here*.

```bash
# 1. Navigate to the devkit root
cd /c/Users/YourName/Desktop/airgap-devkit   # adjust to your path

# 2. Set environment variables
export AIRGAP_OS=windows
export PREBUILT_DIR="$(pwd)/prebuilt"
export INSTALL_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/<receipt-name>"
#   Replace <receipt-name> with the tool's receipt_name (see devkit.json)
#   e.g. for llvm: clang-llvm   for cmake: cmake

# 3. Run the tool's setup script
bash tools/<category>/<tool>/setup.sh

# 3b. Or with a custom install prefix
bash tools/<category>/<tool>/setup.sh --prefix /c/my-tools/<tool>
```

After installation, restart Git Bash (or run `source ~/.bashrc`) so the new
PATH entries take effect.

### Linux — bash

```bash
# 1. Navigate to the devkit root
cd ~/airgap-devkit   # adjust to your path

# 2. Set environment variables
export AIRGAP_OS=linux
export PREBUILT_DIR="$(pwd)/prebuilt"
export INSTALL_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/<receipt-name>"

# 3. Run the tool's setup script
bash tools/<category>/<tool>/setup.sh

# 3b. System-wide install (requires root)
sudo bash tools/<category>/<tool>/setup.sh
# Root installs default to /opt/airgap-cpp-devkit/<tool>/
```

After installation, restart your shell or run `source ~/.bashrc`.

---

## Tool-specific examples

### CMake

```bash
# Windows
export AIRGAP_OS=windows
export PREBUILT_DIR="$(pwd)/prebuilt"
export INSTALL_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/cmake"
bash tools/build-tools/cmake/setup.sh

# Linux
export AIRGAP_OS=linux
export PREBUILT_DIR="$(pwd)/prebuilt"
export INSTALL_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/cmake"
bash tools/build-tools/cmake/setup.sh
```

### LLVM / Clang (split archive)

LLVM is split into multiple `.part-*` files because the archive exceeds GitHub's
50 MB file-size limit.  `setup.sh` handles the reassembly — just run it normally:

```bash
# Windows
export AIRGAP_OS=windows
export PREBUILT_DIR="$(pwd)/prebuilt"
export INSTALL_PREFIX="${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm"
bash tools/toolchains/llvm/setup.sh

# Linux
export AIRGAP_OS=linux
export PREBUILT_DIR="$(pwd)/prebuilt"
export INSTALL_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/clang-llvm"
bash tools/toolchains/llvm/setup.sh
```

---

## Manual reassembly of split archives

If you want to extract the archive yourself (bypassing `setup.sh`), use the
commands below.  Part files live under `prebuilt/<category>/<tool>/<version>/`.

### Reassemble and extract (Windows — Git Bash)

```bash
# Navigate to the devkit root first
cd /c/Users/YourName/Desktop/airgap-devkit

# Reassemble all parts and pipe directly into tar
cat prebuilt/toolchains/llvm/22.1.4/clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz.part-* \
  | tar -xJ --strip-components=1 -C "${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm"
```

### Reassemble and extract (Linux)

```bash
cat prebuilt/toolchains/llvm/22.1.4/LLVM-22.1.4-Linux-X64.tar.xz.part-* \
  | tar -xJ --strip-components=1 -C "${HOME}/.local/share/airgap-cpp-devkit/clang-llvm"
```

### Reassemble to a file first (optional)

```bash
# Create the full archive from parts
cat prebuilt/toolchains/llvm/22.1.4/clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz.part-* \
  > /tmp/clang-llvm.tar.xz

# Then extract
mkdir -p "${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm"
tar -xJf /tmp/clang-llvm.tar.xz --strip-components=1 \
  -C "${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm"

# Clean up
rm /tmp/clang-llvm.tar.xz
```

### Finding part files for any tool

```bash
# List all part files for a tool (adjust the path)
ls prebuilt/toolchains/llvm/22.1.4/*.part-*

# Count parts
ls prebuilt/toolchains/llvm/22.1.4/*.part-* | wc -l
```

---

## Writing an install receipt manually

Each `setup.sh` writes an `INSTALL_RECEIPT.txt` to the install prefix so the
web UI knows the tool is installed.  If you extracted manually, create it yourself:

```bash
# Adjust values to match your install
cat > "${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm/INSTALL_RECEIPT.txt" <<EOF
tool=llvm
version=22.1.4
platform=windows
install_prefix=${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm
installed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
```

After writing the receipt, refresh the devkit-ui dashboard — the tool will
appear as Installed.

---

## Registering the tool in your PATH

Each setup script appends a `source` line to `~/.bashrc` so the tool is
available in future Git Bash / bash sessions.  If you bypassed the script,
add the line manually:

```bash
# Add to ~/.bashrc
echo 'export PATH="${LOCALAPPDATA}/airgap-cpp-devkit/clang-llvm/bin:$PATH"' >> ~/.bashrc

# Apply immediately
source ~/.bashrc
```

On Linux replace `${LOCALAPPDATA}/airgap-cpp-devkit` with
`${HOME}/.local/share/airgap-cpp-devkit` (or `/opt/airgap-cpp-devkit` for
root installs).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No parts found matching …` | The prebuilt submodule may not be initialised. Run `git submodule update --init prebuilt` from the devkit root. |
| `bash: tar: command not found` (Windows) | Git Bash includes `tar`; make sure you are in Git Bash, not PowerShell. |
| `Permission denied` writing to `C:\Program Files\` | Run Git Bash as Administrator, or use a user-local prefix with `--prefix`. |
| `cat: …part-*: No such file or directory` | The glob did not expand — verify the files exist with `ls prebuilt/<path>/*.part-*`. |
| Web UI still shows tool as not installed after manual install | Ensure `INSTALL_RECEIPT.txt` was written to `<prefix>/<receipt-name>/` and the path exactly matches the prefix shown in Settings → Install Prefix. |
| `tar: Error opening archive: Failed to open …` | The pipe was interrupted.  Verify all part files are present and not truncated (`ls -lh prebuilt/<path>/*.part-*`). |

---

## Using the web UI to generate commands

When an install fails in the devkit-ui, a **"Show manual install commands"**
button appears in the Terminal drawer at the bottom of the page.  Click it to
open a dialog with pre-filled, copy-ready shell commands for your platform
(Windows or Linux) including split-archive reassembly instructions if applicable.
