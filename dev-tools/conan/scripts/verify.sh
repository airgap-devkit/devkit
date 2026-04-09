#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/conan/scripts/verify.sh
#
# Verifies SHA256 checksums of vendored Conan assets.
# Checks only the file relevant to the current platform.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

VENDOR_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/conan"

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

echo "Verifying Conan 2.27.0 vendor assets (${OS})..."
echo ""

if [[ "${OS}" == "windows" ]]; then
  verify_file \
    "${VENDOR_DIR}/conan-2.27.0-windows-x86_64.zip" \
    "9ec5eb2351c187cebcf674c46246e29d09fca4a6f87284a3d3d08b03e4d3fc44" \
    "conan-2.27.0-windows-x86_64.zip"
else
  verify_file \
    "${VENDOR_DIR}/conan-2.27.0-linux-x86_64.tgz" \
    "2f96e3a820c8558781be38f5c85e7c54e1ab4215c99bc65e2279bd2b41dbb77a" \
    "conan-2.27.0-linux-x86_64.tgz"
fi

echo ""

if [[ "${fail}" -ne 0 ]]; then
  echo "ERROR: One or more vendor assets failed verification." >&2
  echo "       Expected files in: prebuilt-binaries/dev-tools/conan/" >&2
  exit 1
fi

echo "All assets verified successfully."