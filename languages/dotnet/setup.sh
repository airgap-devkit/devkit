#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# languages/dotnet/setup.sh
#
# Installs .NET 10 SDK from prebuilt-binaries submodule on Linux.
# No internet access, no package manager, no elevation required for user install.
#
# USAGE:
#   bash languages/dotnet/setup.sh [--prefix <path>]
#
# OPTIONS:
#   --prefix <path>   Install to a custom path (default: auto-detected)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SDK_VERSION="10.0.201"
ARCHIVE="dotnet-sdk-${SDK_VERSION}-linux-x64.tar.gz"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/languages/dotnet/${SDK_VERSION}"
PREFIX_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX_OVERRIDE="$2"; shift 2 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Determine install prefix
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
    INSTALL_PREFIX="${PREFIX_OVERRIDE}"
elif [[ $EUID -eq 0 ]]; then
    INSTALL_PREFIX="/opt/airgap-cpp-devkit/dotnet"
    echo "[INFO] Running as root. Installing system-wide."
else
    INSTALL_PREFIX="${HOME}/.local/share/airgap-cpp-devkit/dotnet"
    echo "[WARNING] Not root. Installing for current user only."
fi

echo "[INFO] Install destination: ${INSTALL_PREFIX}"

# Check prebuilt dir
if [[ ! -d "${PREBUILT_DIR}" ]]; then
    echo "ERROR: Prebuilt directory not found: ${PREBUILT_DIR}" >&2
    echo "       Run: git submodule update --init prebuilt-binaries" >&2
    exit 1
fi

# Check parts exist
PARTS=("${PREBUILT_DIR}/${ARCHIVE}.part-"*)
if [[ ! -e "${PARTS[0]}" ]]; then
    echo "ERROR: No parts found for ${ARCHIVE} in ${PREBUILT_DIR}" >&2
    exit 1
fi

echo "[INFO] Found ${#PARTS[@]} part(s). Reassembling..."

# Reassemble
TMP_DIR="$(mktemp -d)"
TMP_ARCHIVE="${TMP_DIR}/${ARCHIVE}"

cat "${PREBUILT_DIR}/${ARCHIVE}.part-"* > "${TMP_ARCHIVE}"
echo "[OK] Reassembled: $(du -sh "${TMP_ARCHIVE}" | cut -f1)"

# Verify SHA256
MANIFEST="${PREBUILT_DIR}/manifest.json"
if [[ -f "${MANIFEST}" ]] && command -v python3 &>/dev/null; then
    EXPECTED=$(python3 -c "
import json, sys
with open('${MANIFEST}') as f:
    m = json.load(f)
print(m['archives']['linux-x64']['tar.gz']['sha256'])
" 2>/dev/null || echo "")
    if [[ -n "${EXPECTED}" ]]; then
        ACTUAL=$(sha256sum "${TMP_ARCHIVE}" | cut -d' ' -f1)
        if [[ "${ACTUAL}" == "${EXPECTED}" ]]; then
            echo "[OK] SHA256 verified."
        else
            echo "ERROR: SHA256 mismatch!" >&2
            echo "  Expected: ${EXPECTED}" >&2
            echo "  Actual:   ${ACTUAL}" >&2
            rm -rf "${TMP_DIR}"
            exit 1
        fi
    else
        echo "[WARNING] Could not read SHA256 from manifest -- skipping verification."
    fi
else
    echo "[WARNING] manifest.json or python3 not found -- skipping integrity check."
fi

# Extract
if [[ -d "${INSTALL_PREFIX}" ]]; then
    echo "[INFO] Destination exists. Removing and reinstalling..."
    rm -rf "${INSTALL_PREFIX}"
fi
mkdir -p "${INSTALL_PREFIX}"

echo "[INFO] Extracting..."
tar -xzf "${TMP_ARCHIVE}" -C "${INSTALL_PREFIX}"
rm -rf "${TMP_DIR}"

# Verify
if [[ ! -f "${INSTALL_PREFIX}/dotnet" ]]; then
    echo "ERROR: dotnet binary not found after extraction." >&2
    exit 1
fi

VERSION_OUT=$("${INSTALL_PREFIX}/dotnet" --version 2>&1 || echo "unknown")
echo "[OK] dotnet: ${VERSION_OUT}"

echo ""
echo "============================================================"
echo " .NET SDK ${SDK_VERSION} installed"
echo " Location : ${INSTALL_PREFIX}"
echo " dotnet   : ${INSTALL_PREFIX}/dotnet"
echo "============================================================"
echo ""
echo "Add to PATH for this session:"
echo "  export PATH=\"${INSTALL_PREFIX}:\$PATH\""
echo ""
echo "Add to ~/.bashrc for permanent use:"
echo "  echo 'export PATH=\"${INSTALL_PREFIX}:\$PATH\"' >> ~/.bashrc"
echo ""
echo "Verify:"
echo "  dotnet --version"
echo "  dotnet new console -n HelloWorld"
echo "  cd HelloWorld && dotnet run"