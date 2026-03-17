#!/usr/bin/env bash
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/install.sh
#
# PURPOSE: Extract the WinLibs .7z to a chosen install directory and emit
#          environment setup instructions.  Runs verify.sh first — will not
#          install if the hash check fails.
#
# USAGE:
#   bash scripts/install.sh [x86_64|i686] [install_dir]
#
#   install_dir defaults to: <module_root>/toolchain/<arch>
#
# EXAMPLE:
#   bash scripts/install.sh x86_64
#   bash scripts/install.sh x86_64 /opt/winlibs-gcc-ucrt
#   bash scripts/install.sh x86_64 "C:/devtools/winlibs-gcc-ucrt"
#
# REQUIREMENTS:
#   7z (7-Zip) must be on PATH. On Windows Git Bash, install 7-Zip and add
#   "C:/Program Files/7-Zip" to PATH, or place 7z.exe in a PATH directory.
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

INSTALL_DIR="${2:-${MODULE_ROOT}/toolchain/${ARCH}}"

# ---------------------------------------------------------------------------
# Parse manifest
# ---------------------------------------------------------------------------
parse_manifest_field() {
  local block="$1"
  local field="$2"
  grep -A 30 "\"${block}\"" "${MANIFEST}" \
    | grep "\"${field}\"" \
    | head -1 \
    | sed 's/.*"'"${field}"'": *"\([^"]*\)".*/\1/'
}

FILENAME=$(grep -A 2 "\"${ARCH}\"" "${MANIFEST}" \
  | grep '"filename"' \
  | grep -v 'part-' \
  | head -1 \
  | sed 's/.*"filename": *"\([^"]*\)".*/\1/')
EXTRACT_ROOT=$(parse_manifest_field "${ARCH}" "extract_root")
ARCHIVE="${VENDOR_DIR}/${FILENAME}"

echo "============================================================"
echo " WinLibs GCC UCRT — Install"
echo " Arch        : ${ARCH}"
echo " Archive     : ${ARCHIVE}"
echo " Install dir : ${INSTALL_DIR}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Pre-install: reassemble from parts if .7z not yet present
# ---------------------------------------------------------------------------
ARCHIVE_CHECK="${VENDOR_DIR}/${FILENAME}"
if [[ ! -f "${ARCHIVE_CHECK}" ]]; then
  echo "[STEP 0] Reassembled archive not found — running reassemble.sh first..."
  echo ""
  if ! bash "${SCRIPT_DIR}/reassemble.sh" "${ARCH}"; then
    echo "" >&2
    echo "[ABORT] Reassembly failed. Installation cancelled." >&2
    exit 1
  fi
  echo ""
fi

# ---------------------------------------------------------------------------
# Pre-install integrity check (always — not optional)
# ---------------------------------------------------------------------------
echo "[STEP 1/3] Running integrity check..."
if ! bash "${SCRIPT_DIR}/verify.sh" "${ARCH}"; then
  echo "" >&2
  echo "[ABORT] Integrity check failed. Installation cancelled." >&2
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Check for 7z
# ---------------------------------------------------------------------------
if ! command -v 7z &>/dev/null; then
  echo "[ERROR] 7z not found on PATH." >&2
  echo "        Install 7-Zip (https://7-zip.org/) and add it to PATH." >&2
  echo "        On MINGW64: add 'C:/Program Files/7-Zip' to your PATH." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
echo "[STEP 2/3] Extracting archive..."
mkdir -p "${INSTALL_DIR}"

# Extract to a temp staging dir under install root, then move to final path.
# This avoids a partial install if extraction fails halfway.
STAGING="${INSTALL_DIR}/.winlibs-staging-$$"
mkdir -p "${STAGING}"

cleanup_staging() {
  rm -rf "${STAGING}"
}
trap cleanup_staging EXIT

7z x "${ARCHIVE}" -o"${STAGING}" -y > /dev/null

# The .7z extracts to a single root dir (mingw64/ or mingw32/).
# Move that into the install dir directly.
EXTRACTED="${STAGING}/${EXTRACT_ROOT}"
if [[ ! -d "${EXTRACTED}" ]]; then
  echo "[ERROR] Expected extraction root '${EXTRACT_ROOT}' not found in archive." >&2
  echo "        Check manifest extract_root for arch '${ARCH}'." >&2
  exit 1
fi

# Move into place (replaces any previous install)
FINAL_PATH="${INSTALL_DIR}/${EXTRACT_ROOT}"
if [[ -d "${FINAL_PATH}" ]]; then
  echo "[INFO] Removing previous install at ${FINAL_PATH}..."
  rm -rf "${FINAL_PATH}"
fi
mv "${EXTRACTED}" "${FINAL_PATH}"

echo "[INFO] Extraction complete: ${FINAL_PATH}"

# ---------------------------------------------------------------------------
# Smoke test
# ---------------------------------------------------------------------------
echo ""
echo "[STEP 3/3] Smoke test..."
GCC_BIN="${FINAL_PATH}/bin/gcc.exe"
if [[ ! -f "${GCC_BIN}" ]]; then
  echo "[WARN] gcc.exe not found at expected location: ${GCC_BIN}" >&2
  echo "       Extraction may have produced a different layout." >&2
else
  GCC_VER=$("${GCC_BIN}" --version 2>&1 | head -1)
  echo "[PASS] ${GCC_VER}"
fi

# ---------------------------------------------------------------------------
# Print env-setup instructions
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " [SUCCESS] Installation complete."
echo ""
echo " To activate this toolchain in your current shell:"
echo "   source '${MODULE_ROOT}/scripts/env-setup.sh' ${ARCH} '${INSTALL_DIR}'"
echo ""
echo " Or add permanently to ~/.bashrc:"
echo "   echo \"source '${MODULE_ROOT}/scripts/env-setup.sh' ${ARCH} '${INSTALL_DIR}'\" >> ~/.bashrc"
echo ""
echo " Binary path: ${FINAL_PATH}/bin"
echo "============================================================"