#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/conan/scripts/install-linux.sh
#
# Extracts and installs the Conan 2.27.0 self-contained executable on Linux.
# Called by setup.sh after verification.
#
# USAGE:
#   bash scripts/install-linux.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"
VERSION="2.27.0"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/conan"
ARCHIVE="${VENDOR_DIR}/conan-${VERSION}-linux-x86_64.tgz"

# ---------------------------------------------------------------------------
# Determine install directory
# ---------------------------------------------------------------------------
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}/bin"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_DIR="/opt/airgap-cpp-devkit/conan/bin"
else
  INSTALL_DIR="${HOME}/.local/share/airgap-cpp-devkit/conan/bin"
fi

echo "[conan] Install mode : ${MODE}"
echo "[conan] Install dir  : ${INSTALL_DIR}"
echo "[conan] Source       : ${ARCHIVE}"
echo ""

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "ERROR: Archive not found: ${ARCHIVE}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
tar -xzf "${ARCHIVE}" -C "${INSTALL_DIR}"
chmod +x "${INSTALL_DIR}/conan" 2>/dev/null || true

echo "[conan] Installed : ${INSTALL_DIR}/conan"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if [[ -f "${INSTALL_DIR}/conan" ]]; then
  VER="$("${INSTALL_DIR}/conan" --version 2>/dev/null | awk '{print $3}' || echo "unknown")"
  echo "[conan] Verified  : ${VER}"
fi

# ---------------------------------------------------------------------------
# PATH hint
# ---------------------------------------------------------------------------
if [[ "${MODE}" == "user" ]]; then
  echo ""
  echo "[conan] NOTE: Ensure ${INSTALL_DIR} is in your PATH."
  echo "       Add to ~/.bashrc if needed:"
  echo "         export PATH=\"${INSTALL_DIR}:\${PATH}\""
fi