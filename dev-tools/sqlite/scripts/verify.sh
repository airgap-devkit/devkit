#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/sqlite/scripts/verify.sh
#
# Verifies SHA256 of vendored SQLite assets.
# On RHEL/Rocky 8: verifies the RPM.
# On all other Linux / Windows: verifies the CLI zip.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/sqlite"

OS="linux"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac

_is_rhel8() {
  if [[ -f /etc/os-release ]]; then
    local id ver
    id="$(. /etc/os-release && echo "${ID:-}")"
    ver="$(. /etc/os-release && echo "${VERSION_ID:-}" | cut -d. -f1)"
    if [[ "${id}" =~ ^(rhel|rocky|centos|almalinux)$ && "${ver}" == "8" ]]; then
      return 0
    fi
  fi
  return 1
}

fail=0

verify_file() {
  local filepath="$1"
  local expected="$2"
  local label="$3"

  if [[ ! -f "${filepath}" ]]; then
    echo "  MISSING  ${label}"
    echo "           Expected at: ${filepath}" >&2
    fail=1
    return
  fi

  local actual
  actual="$(sha256sum "${filepath}" | awk '{print $1}')"

  if [[ "${actual}" == "${expected}" ]]; then
    echo "  OK       ${label}"
  else
    echo "  MISMATCH ${label}"
    echo "           Expected : ${expected}" >&2
    echo "           Got      : ${actual}" >&2
    fail=1
  fi
}

echo "Verifying SQLite vendor assets..."
echo ""

if [[ "${OS}" == "windows" ]]; then
  verify_file \
    "${VENDOR_DIR}/sqlite-tools-win-x64-3530000.zip" \
    "8ccef1d86a312f4affaa313e0d355b4e8bd7cadcd02d79c9f539cfca50e73ff8" \
    "sqlite-tools-win-x64-3530000.zip (Windows CLI 3.53.0)"
elif _is_rhel8; then
  verify_file \
    "${VENDOR_DIR}/sqlite-3.26.0-20.el8_10.x86_64.rpm" \
    "0ad7d10fe613415fb056a16f0699e39cb4182271300a0c353137b744671b3c78" \
    "sqlite-3.26.0-20.el8_10.x86_64.rpm (RHEL 8 RPM)"
else
  verify_file \
    "${VENDOR_DIR}/sqlite-tools-linux-x64-3530000.zip" \
    "a5f5a164bab3418a6469cc0dff030c1ddc2d05ab795e1b0adc435a089129d401" \
    "sqlite-tools-linux-x64-3530000.zip (Linux CLI 3.53.0)"
fi

echo ""

if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more vendor assets failed verification." >&2
  echo "       Expected files in: prebuilt-binaries/dev-tools/sqlite/" >&2
  exit 1
fi

echo "All assets verified successfully."