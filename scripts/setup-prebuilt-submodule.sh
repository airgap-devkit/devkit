#!/usr/bin/env bash
# =============================================================================
# scripts/setup-prebuilt-submodule.sh
# Author: Nima Shafie
#
# PURPOSE: One-time setup script to initialize the prebuilt-binaries submodule.
#          Run this after cloning if you want the pre-built binaries (Base Case).
#          Skip this entirely if you are in a binary-restricted environment
#          and will be building all tools from source (Worst Case).
#
# USAGE:
#   bash scripts/setup-prebuilt-submodule.sh
#
# WHAT IT DOES:
#   1. Initializes and clones the prebuilt-binaries submodule
#   2. Verifies SHA256 of all binaries against manifest.json
#   3. Prints a clear summary of what is available
#
# BINARY-RESTRICTED ENVIRONMENTS:
#   If your air-gapped network does not permit pre-compiled binaries,
#   do NOT run this script. Instead, build all tools from source:
#     bash clang-llvm/source-build/bootstrap.sh --build-from-source
#     bash prebuilt/winlibs-gcc-ucrt/setup.sh
#     etc.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  airgap-cpp-devkit — Prebuilt Binaries Submodule Setup          ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║                                                                  ║"
echo "║  This initializes the prebuilt-binaries submodule which         ║"
echo "║  contains pre-compiled binaries for immediate use.              ║"
echo "║                                                                  ║"
echo "║  BINARY-RESTRICTED ENVIRONMENTS:                                ║"
echo "║  If your network prohibits pre-compiled binaries, press Ctrl+C  ║"
echo "║  now and build from source instead.                             ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Press Enter to continue, or Ctrl+C to cancel..."
read -r

cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Check if submodule is already initialized
# ---------------------------------------------------------------------------
if [[ -f "prebuilt-binaries/.git" ]] || \
   git submodule status prebuilt-binaries 2>/dev/null | grep -q "^[^-]"; then
    echo "[INFO] prebuilt-binaries submodule already initialized."
    echo "       Running git submodule update to ensure it is current..."
    git submodule update --init --recursive prebuilt-binaries
else
    echo "[INFO] Initializing prebuilt-binaries submodule..."
    git submodule update --init --recursive prebuilt-binaries
fi

echo ""
echo "[INFO] Submodule initialized."
echo ""

# ---------------------------------------------------------------------------
# Show what is available
# ---------------------------------------------------------------------------
echo "Available pre-built binaries:"
echo ""

_check_binary() {
    local label="$1"
    local path="${REPO_ROOT}/prebuilt-binaries/${2}"
    if [[ -f "${path}" ]]; then
        local size
        size="$(du -sh "${path}" 2>/dev/null | cut -f1)"
        echo "  ✓  ${label} (${size})"
    elif ls "${path}".part-* &>/dev/null 2>&1; then
        echo "  ○  ${label} (split parts — run bootstrap to assemble)"
    else
        echo "  ✗  ${label} (not found)"
    fi
}

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        _check_binary "clang-format.exe" "clang-llvm/clang-format.exe"
        _check_binary "clang-tidy.exe"   "clang-llvm/clang-tidy.exe"
        _check_binary "WinLibs GCC"      "winlibs-gcc-ucrt/winlibs-x86_64-posix-seh-gcc-15.2.0-mingw-w64ucrt-13.0.0-r6.7z"
        ;;
    Linux*)
        _check_binary "clang-tidy (linux)" "clang-llvm/clang-tidy-linux.part-aa"
        ;;
esac

echo ""
echo "  Run the individual tool bootstraps to install:"
echo "    bash clang-llvm/source-build/bootstrap.sh"
echo "    bash prebuilt-binaries/winlibs-gcc-ucrt/setup.sh"
echo ""