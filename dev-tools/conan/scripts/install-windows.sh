#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/conan/scripts/install-windows.sh
#
# Extracts and installs the Conan 2.27.0 self-contained bundle on Windows.
# Called by setup.sh after verification.
#
# USAGE:
#   bash scripts/install-windows.sh <admin|user> [prefix_override]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

MODE="${1:-user}"
PREFIX_OVERRIDE="${2:-}"
VERSION="2.27.0"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/conan"
ARCHIVE="${VENDOR_DIR}/conan-${VERSION}-windows-x86_64.zip"

# ---------------------------------------------------------------------------
# Determine install directory
# ---------------------------------------------------------------------------
if [[ -n "${PREFIX_OVERRIDE}" ]]; then
  INSTALL_DIR="${PREFIX_OVERRIDE}/bin"
elif [[ "${MODE}" == "admin" ]]; then
  INSTALL_DIR="/c/Program Files/airgap-cpp-devkit/conan/bin"
else
  LOCALAPPDATA_UNIX="$(cygpath -u "${LOCALAPPDATA:-${HOME}/AppData/Local}" 2>/dev/null || echo "${HOME}/AppData/Local")"
  INSTALL_DIR="${LOCALAPPDATA_UNIX}/airgap-cpp-devkit/conan/bin"
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
if command -v 7z &>/dev/null; then
  7z x "${ARCHIVE}" -o"${INSTALL_DIR}" -y > /dev/null
elif command -v unzip &>/dev/null; then
  unzip -q -o "${ARCHIVE}" -d "${INSTALL_DIR}"
else
  echo "ERROR: Need 7z or unzip. Install dev-tools/7zip first." >&2
  exit 1
fi

# Flatten if bundle extracted into a subdirectory
local_conan="$(find "${INSTALL_DIR}" -maxdepth 3 -name "conan.exe" | head -1)"
if [[ -n "${local_conan}" ]]; then
  bundle_dir="$(dirname "${local_conan}")"
  if [[ "${bundle_dir}" != "${INSTALL_DIR}" ]]; then
    cp -r "${bundle_dir}/." "${INSTALL_DIR}/"
  fi
fi

echo "[conan] Installed : ${INSTALL_DIR}/conan.exe"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
if [[ -f "${INSTALL_DIR}/conan.exe" ]]; then
  VER="$("${INSTALL_DIR}/conan.exe" --version 2>/dev/null | awk '{print $3}' || echo "unknown")"
  echo "[conan] Verified  : ${VER}"
fi

# ---------------------------------------------------------------------------
# Register PATH
# ---------------------------------------------------------------------------
INSTALL_DIR_WIN="$(cygpath -w "${INSTALL_DIR}" 2>/dev/null || echo "${INSTALL_DIR}")"

if [[ "${MODE}" == "admin" ]]; then
  powershell.exe -NoProfile -Command "
    \$path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (\$path -notlike '*${INSTALL_DIR_WIN}*') {
      [System.Environment]::SetEnvironmentVariable('Path', \$path + ';${INSTALL_DIR_WIN}', 'Machine')
      Write-Host '[conan] PATH registered (Machine scope)'
    } else {
      Write-Host '[conan] PATH already registered (Machine scope)'
    }
  " 2>/dev/null || echo "[conan] Could not register PATH -- add manually: ${INSTALL_DIR_WIN}"
else
  powershell.exe -NoProfile -Command "
    \$path = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    if (\$path -notlike '*${INSTALL_DIR_WIN}*') {
      [System.Environment]::SetEnvironmentVariable('Path', \$path + ';${INSTALL_DIR_WIN}', 'User')
      Write-Host '[conan] PATH registered (User scope)'
    } else {
      Write-Host '[conan] PATH already registered (User scope)'
    }
  " 2>/dev/null || echo "[conan] Could not register PATH -- add manually: ${INSTALL_DIR_WIN}"
fi