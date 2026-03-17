#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/reassemble.sh
#
# PURPOSE: Verify each split part against its pinned SHA256, reassemble them
#          into the original .7z, then verify the reassembled archive against
#          its pinned SHA256 (cross-referenced from two upstream sources).
#
#          Run this on the air-gapped machine after cloning, before install.
#          The reassembled .7z is written to vendor/ and is gitignored.
#
# USAGE:
#   bash scripts/reassemble.sh [x86_64|i686]     # default: x86_64
#
# EXIT CODES:
#   0 — reassembly succeeded, all hashes match
#   1 — any hash mismatch or missing part; do NOT proceed with install
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

# ---------------------------------------------------------------------------
# Parse manifest — no jq, pure grep/sed/awk
# ---------------------------------------------------------------------------
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
  # Find the sha256 on the line immediately after this filename in the manifest
  grep -A 1 "\"${part_filename}\"" "${MANIFEST}" \
    | grep '"sha256"' \
    | sed 's/.*"sha256": *"\([^"]*\)".*/\1/'
}

get_assembled_filename() {
  # x86_64 block: first "filename" that does NOT contain "part-"
  grep -A 2 "\"${ARCH}\"" "${MANIFEST}" \
    | grep '"filename"' \
    | grep -v 'part-' \
    | head -1 \
    | sed 's/.*"filename": *"\([^"]*\)".*/\1/'
}

ASSEMBLED_FILENAME=$(get_assembled_filename)
ASSEMBLED_PATH="${VENDOR_DIR}/${ASSEMBLED_FILENAME}"
EXPECTED_ASSEMBLED_SHA256=$(get_reassembled_hash)

echo "============================================================"
echo " WinLibs GCC UCRT — Reassemble"
echo " Arch   : ${ARCH}"
echo " Output : ${ASSEMBLED_PATH}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Verify each part
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Verifying split parts..."

PARTS=()
ALL_PARTS_OK=true

while IFS= read -r part_filename; do
  part_path="${VENDOR_DIR}/${part_filename}"
  expected_hash=$(get_part_hash "${part_filename}")

  if [[ ! -f "${part_path}" ]]; then
    echo "  [FAIL] Missing: ${part_filename}" >&2
    ALL_PARTS_OK=false
    continue
  fi

  actual_hash=$(sha256sum "${part_path}" | awk '{print $1}')

  if [[ "${actual_hash}" == "${expected_hash}" ]]; then
    echo "  [PASS] ${part_filename}"
    PARTS+=("${part_path}")
  else
    echo "  [FAIL] Hash mismatch: ${part_filename}" >&2
    echo "         Expected : ${expected_hash}" >&2
    echo "         Actual   : ${actual_hash}" >&2
    ALL_PARTS_OK=false
  fi
done < <(get_part_filenames)

if [[ "${ALL_PARTS_OK}" == "false" ]]; then
  echo "" >&2
  echo "[ABORT] One or more parts failed verification. Do not proceed." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Step 2: Reassemble
# ---------------------------------------------------------------------------
echo "[STEP 2/3] Reassembling ${#PARTS[@]} parts into ${ASSEMBLED_FILENAME}..."

# Remove any stale previous reassembly
rm -f "${ASSEMBLED_PATH}"

cat "${PARTS[@]}" > "${ASSEMBLED_PATH}"

echo "[INFO] Reassembly complete. Size: $(du -h "${ASSEMBLED_PATH}" | awk '{print $1}')"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Verify reassembled archive
# ---------------------------------------------------------------------------
echo "[STEP 3/3] Verifying reassembled archive SHA256..."
ACTUAL_ASSEMBLED_SHA256=$(sha256sum "${ASSEMBLED_PATH}" | awk '{print $1}')

echo "  Expected (manifest, dual-source): ${EXPECTED_ASSEMBLED_SHA256}"
echo "  Actual                          : ${ACTUAL_ASSEMBLED_SHA256}"
echo ""

if [[ "${ACTUAL_ASSEMBLED_SHA256}" == "${EXPECTED_ASSEMBLED_SHA256}" ]]; then
  echo "[PASS] Reassembled archive integrity confirmed."
  echo ""
  echo "============================================================"
  echo " [SUCCESS] Ready to install."
  echo " Run: bash scripts/install.sh ${ARCH}"
  echo "============================================================"
else
  echo "[FAIL] Reassembled archive hash MISMATCH." >&2
  echo "       Parts passed individually but the joined file is wrong." >&2
  echo "       This should not happen — investigate before proceeding." >&2
  rm -f "${ASSEMBLED_PATH}"
  exit 1
fi