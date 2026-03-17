#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/verify.sh
#
# PURPOSE: Offline SHA256 verification. No network access required.
#
#   - If the reassembled .7z exists in vendor/: verifies it against the
#     pinned sha256_reassembled value in manifest.json.
#   - If only split parts exist: verifies each part against its pinned hash.
#
# Typical flow on air-gapped machine:
#   1. Clone repo (parts already in vendor/)
#   2. bash scripts/verify.sh          <- verifies parts
#   3. bash scripts/reassemble.sh      <- joins parts, verifies reassembled .7z
#   4. bash scripts/install.sh         <- installs (calls verify internally)
#
# USAGE:
#   bash scripts/verify.sh [x86_64|i686]     # default: x86_64
#
# EXIT CODES:
#   0 - all checks passed
#   1 - any mismatch or missing file
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${MODULE_ROOT}/manifest.json"
VENDOR_DIR="${MODULE_ROOT}/vendor"

ARCH="${1:-x86_64}"
if [[ "${ARCH}" != "x86_64" && "${ARCH}" != "i686" ]]; then
  echo "[ERROR] Unknown architecture '${ARCH}'. Use 'x86_64' or 'i686'." >&2
  exit 1
fi

get_assembled_filename() {
  grep -A 2 "\"${ARCH}\"" "${MANIFEST}" \
    | grep '"filename"' \
    | grep -v 'part-' \
    | head -1 \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

get_reassembled_hash() {
  grep -A 5 '"sha256_reassembled"' "${MANIFEST}" \
    | grep '"value"' \
    | head -1 \
    | sed 's/.*"value": *"\([^"]*\)".*/\1/'
}

get_part_filenames() {
  grep '"filename".*part-' "${MANIFEST}" \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

get_part_hash() {
  local part_filename="$1"
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/'
}

ASSEMBLED_FILENAME=$(get_assembled_filename)
ASSEMBLED_PATH="${VENDOR_DIR}/${ASSEMBLED_FILENAME}"
EXPECTED_ASSEMBLED_SHA256=$(get_reassembled_hash)

echo "============================================================"
echo " WinLibs GCC UCRT -- Offline Verify"
echo " Arch : ${ARCH}"
echo "============================================================"
echo ""

if [[ -f "${ASSEMBLED_PATH}" ]]; then
  echo "[MODE] Reassembled archive found -- verifying .7z..."
  echo "       File: ${ASSEMBLED_PATH}"
  echo ""

  ACTUAL=$(sha256sum "${ASSEMBLED_PATH}" | awk '{print $1}')
  echo "  Expected (manifest): ${EXPECTED_ASSEMBLED_SHA256}"
  echo "  Actual             : ${ACTUAL}"
  echo ""

  if [[ "${ACTUAL}" == "${EXPECTED_ASSEMBLED_SHA256}" ]]; then
    echo "[PASS] Reassembled archive integrity confirmed."
    exit 0
  else
    echo "[FAIL] Hash mismatch on reassembled archive." >&2
    echo "       Delete it and re-run reassemble.sh." >&2
    exit 1
  fi
fi

echo "[MODE] No reassembled archive found -- verifying split parts..."
echo ""

ALL_OK=true
FOUND=0

while IFS= read -r part_filename; do
  part_path="${VENDOR_DIR}/${part_filename}"
  expected_hash=$(get_part_hash "${part_filename}")

  if [[ ! -f "${part_path}" ]]; then
    echo "  [FAIL] Missing: ${part_filename}" >&2
    ALL_OK=false
    continue
  fi

  actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')
  FOUND=$((FOUND + 1))

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    echo "  [PASS] ${part_filename}"
  else
    echo "  [FAIL] ${part_filename}" >&2
    echo "         Expected : ${expected_hash}" >&2
    echo "         Actual   : ${actual_hash}" >&2
    ALL_OK=false
  fi
done < <(get_part_filenames)

echo ""

if [[ "${FOUND}" -eq 0 ]]; then
  echo "[ERROR] No parts found in vendor/. Clone may be incomplete." >&2
  exit 1
fi

if [[ "${ALL_OK}" == "true" ]]; then
  echo "[PASS] All ${FOUND} parts verified."
  echo ""
  echo " Next step: bash scripts/reassemble.sh ${ARCH}"
  exit 0
else
  echo "[FAIL] One or more parts failed verification." >&2
  echo "       Re-clone the repository and try again." >&2
  exit 1
fi