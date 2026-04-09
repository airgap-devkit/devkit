#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/sqlite/scripts/verify.sh
#
# Verifies SHA256 of vendored SQLite 3.53.0 CLI archive.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/sqlite"

OS="linux"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac

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

echo "Verifying SQLite 3.53.0 vendor assets (${OS})..."
echo ""

if [[ "${OS}" == "windows" ]]; then
  verify_file \
    "${VENDOR_DIR}/sqlite-tools-win-x64-3530000.zip" \
    "8ccef1d86a312f4affaa313e0d355b4e8bd7cadcd02d79c9f539cfca50e73ff8" \
    "sqlite-tools-win-x64-3530000.zip (Windows CLI bundle)"
else
  verify_file \
    "${VENDOR_DIR}/sqlite-tools-linux-x64-3530000.zip" \
    "a5f5a164bab3418a6469cc0dff030c1ddc2d05ab795e1b0adc435a089129d401" \
    "sqlite-tools-linux-x64-3530000.zip (Linux CLI bundle)"
fi

echo ""

if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more vendor assets failed verification." >&2
  echo "       Expected files in: prebuilt-binaries/dev-tools/sqlite/" >&2
  exit 1
fi

echo "All assets verified successfully."