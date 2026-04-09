#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/servy/scripts/verify.sh
#
# Verifies the SHA256 of the vendored Servy 7.8 portable archive.
# Called by setup.sh before extraction.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

VERSION="7.8"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/dev-tools/servy"
ARCHIVE="${PREBUILT_DIR}/servy-7.8-x64-portable.7z"
EXPECTED_SHA256="e0133ed93f9c4ba44dc2731777a27be1385ca1e0cc626ce5d600a39e2d632613"

echo "  Verifying Servy ${VERSION} archive..."

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "ERROR: Archive not found: ${ARCHIVE}" >&2
  echo "       Expected: prebuilt-binaries/dev-tools/servy/servy-7.8-x64-portable.7z" >&2
  exit 1
fi

actual_sha="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"

if [[ "${actual_sha}" != "${EXPECTED_SHA256}" ]]; then
  echo "ERROR: SHA256 mismatch for servy-7.8-x64-portable.7z" >&2
  echo "  Expected: ${EXPECTED_SHA256}" >&2
  echo "  Actual  : ${actual_sha}" >&2
  exit 1
fi

echo "  [OK]  servy-7.8-x64-portable.7z  ${actual_sha}"