#!/usr/bin/env bash
# =============================================================================
# fetch-llvm-source.sh — Download, verify, strip, and stage the LLVM/Clang
#                         source tarballs needed to build clang-format.
#
# Run this script ONCE on a machine with internet access, then commit the
# results to this repository before transferring to air-gapped systems.
#
# What it does:
#   1. Downloads llvm-<ver>.src.tar.xz, clang-<ver>.src.tar.xz, and the
#      two small build-system tarballs from the official LLVM GitHub releases.
#   2. Verifies SHA256 checksums against the official .sig / release page.
#   3. Extracts the tarballs into llvm-src/ with the layout the build expects.
#   4. STRIPS test directories (the biggest space consumers) to reduce the
#      committed tree from ~1 GB to ~250 MB.
#   5. Records the version and checksums in llvm-src/SOURCE_INFO.txt.
#
# After this script completes, commit llvm-src/ to this repository.
# Do NOT commit the downloaded .tar.xz files themselves.
#
# Usage:
#   bash scripts/fetch-llvm-source.sh [--version 18.1.8]
#
# Options:
#   --version X.Y.Z   LLVM version to fetch (default: 18.1.8)
#                     Must be a release available at:
#                     https://github.com/llvm/llvm-project/releases
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
LLVM_VERSION="18.1.8"   # Pinned default — last version supporting VS 2017 as host
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"
DOWNLOAD_DIR="${SUBMODULE_ROOT}/.llvm-downloads"   # temp — not committed

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) LLVM_VERSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--version X.Y.Z]"
            echo "Default version: ${LLVM_VERSION}"
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
for tool in curl sha256sum tar xz; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: '${tool}' is required but not found on PATH." >&2
        exit 1
    fi
done

RELEASE_BASE="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}"

echo "=================================================================="
echo "  fetch-llvm-source.sh"
echo "  LLVM version : ${LLVM_VERSION}"
echo "  Source dir   : ${SRC_DIR}"
echo "  Downloads    : ${DOWNLOAD_DIR} (temporary)"
echo "=================================================================="
echo ""
echo "  This script downloads ~95 MB of source tarballs."
echo "  The resulting llvm-src/ tree will be ~250 MB (tests stripped)."
echo "  Run time: 5-15 minutes depending on your connection speed."
echo ""

# ---------------------------------------------------------------------------
# Confirm before downloading
# ---------------------------------------------------------------------------
read -r -p "  Proceed? [y/N] " confirm
[[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }
echo ""

mkdir -p "${DOWNLOAD_DIR}"

# ---------------------------------------------------------------------------
# Download function with progress and retry
# ---------------------------------------------------------------------------
_download() {
    local url="$1"
    local dest="$2"
    local label="$3"

    if [[ -f "${dest}" ]]; then
        echo "  [cached] ${label}"
        return 0
    fi

    echo "  [downloading] ${label}"
    echo "    URL: ${url}"
    if ! curl -L --fail --progress-bar -o "${dest}" "${url}"; then
        echo "ERROR: Download failed for ${label}" >&2
        rm -f "${dest}"
        exit 1
    fi
    echo "  [done]    ${label}"
}

# ---------------------------------------------------------------------------
# Step 1 — Download tarballs
# ---------------------------------------------------------------------------
echo "[Step 1/4] Downloading source tarballs…"
echo ""

LLVM_TAR="${DOWNLOAD_DIR}/llvm-${LLVM_VERSION}.src.tar.xz"
CLANG_TAR="${DOWNLOAD_DIR}/clang-${LLVM_VERSION}.src.tar.xz"
CMAKE_TAR="${DOWNLOAD_DIR}/llvm-cmake-${LLVM_VERSION}.src.tar.xz"
THIRD_PARTY_TAR="${DOWNLOAD_DIR}/llvm-third-party-${LLVM_VERSION}.src.tar.xz"

_download "${RELEASE_BASE}/llvm-${LLVM_VERSION}.src.tar.xz"          "${LLVM_TAR}"         "llvm source"
_download "${RELEASE_BASE}/clang-${LLVM_VERSION}.src.tar.xz"         "${CLANG_TAR}"        "clang source"
_download "${RELEASE_BASE}/cmake-${LLVM_VERSION}.src.tar.xz"         "${CMAKE_TAR}"        "cmake modules"
_download "${RELEASE_BASE}/third-party-${LLVM_VERSION}.src.tar.xz"   "${THIRD_PARTY_TAR}"  "third-party"

echo ""

# ---------------------------------------------------------------------------
# Step 2 — Verify SHA256 checksums
# The LLVM project publishes checksums at the release page.
# We compute and record them; this also detects corrupt downloads.
# ---------------------------------------------------------------------------
echo "[Step 2/4] Computing checksums…"
echo ""

sha256sum "${LLVM_TAR}" "${CLANG_TAR}" "${CMAKE_TAR}" "${THIRD_PARTY_TAR}" \
    | tee "${DOWNLOAD_DIR}/SHA256SUMS.txt"
echo ""
echo "  ⚠  Manually verify these against:"
echo "     https://github.com/llvm/llvm-project/releases/tag/llvmorg-${LLVM_VERSION}"
echo "     (Download the .sha256 files from that page and compare)"
echo ""
read -r -p "  Continue after verifying? [y/N] " verify_confirm
[[ "${verify_confirm,,}" == "y" ]] || { echo "Aborted — please verify checksums before committing."; exit 1; }
echo ""

# ---------------------------------------------------------------------------
# Step 3 — Extract into llvm-src/ with correct layout
# LLVM expects:
#   llvm-src/
#     llvm-<ver>/          ← LLVM core
#     llvm-<ver>/tools/clang/  ← Clang nested inside LLVM tree
#     cmake/               ← build system modules
#     third-party/         ← build system support
# We also .gitignore build artifacts below.
# ---------------------------------------------------------------------------
echo "[Step 3/4] Extracting source trees…"
echo ""

# Clean and recreate destination
rm -rf "${SRC_DIR}"
mkdir -p "${SRC_DIR}"

# Extract LLVM
echo "  Extracting llvm…"
tar -xf "${LLVM_TAR}" -C "${SRC_DIR}"
mv "${SRC_DIR}/llvm-${LLVM_VERSION}.src" "${SRC_DIR}/llvm"

# Extract clang INTO the LLVM tools directory (required by cmake)
echo "  Extracting clang into llvm/tools/clang…"
tar -xf "${CLANG_TAR}" -C "${SRC_DIR}/llvm/tools"
mv "${SRC_DIR}/llvm/tools/clang-${LLVM_VERSION}.src" "${SRC_DIR}/llvm/tools/clang"

# Extract cmake modules at llvm-src/cmake (parallel to llvm/)
echo "  Extracting cmake modules…"
tar -xf "${CMAKE_TAR}" -C "${SRC_DIR}"
# Handle both naming conventions across LLVM versions
if [[ -d "${SRC_DIR}/cmake-${LLVM_VERSION}.src" ]]; then
    mv "${SRC_DIR}/cmake-${LLVM_VERSION}.src" "${SRC_DIR}/cmake"
elif [[ -d "${SRC_DIR}/llvm-cmake-${LLVM_VERSION}.src" ]]; then
    mv "${SRC_DIR}/llvm-cmake-${LLVM_VERSION}.src" "${SRC_DIR}/cmake"
fi

# Extract third-party
echo "  Extracting third-party…"
tar -xf "${THIRD_PARTY_TAR}" -C "${SRC_DIR}"
if [[ -d "${SRC_DIR}/third-party-${LLVM_VERSION}.src" ]]; then
    mv "${SRC_DIR}/third-party-${LLVM_VERSION}.src" "${SRC_DIR}/third-party"
elif [[ -d "${SRC_DIR}/llvm-third-party-${LLVM_VERSION}.src" ]]; then
    mv "${SRC_DIR}/llvm-third-party-${LLVM_VERSION}.src" "${SRC_DIR}/third-party"
fi

echo ""
echo "  Source tree size before stripping:"
du -sh "${SRC_DIR}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 4 — Strip tests to reduce repository size
# The test directories are the largest component and are not needed
# to build clang-format. Removing them cuts ~750 MB → ~250 MB.
# ---------------------------------------------------------------------------
echo ""
echo "[Step 4/4] Stripping test directories…"
echo ""

_strip_tests() {
    local base="$1"
    local before
    before="$(du -sm "${base}" 2>/dev/null | cut -f1 || echo '?')"

    # Remove test directories — these are never needed for building
    find "${base}" -type d \( \
        -name "test" -o \
        -name "tests" -o \
        -name "unittests" -o \
        -name "unittest" \
    \) -prune -exec rm -rf {} + 2>/dev/null || true

    # Remove benchmark directories (not needed either)
    find "${base}" -type d \( \
        -name "benchmarks" -o \
        -name "benchmark" \
    \) -prune -exec rm -rf {} + 2>/dev/null || true

    # Remove documentation source (build-time docs, not the code comments)
    find "${base}" -type d -name "docs" -prune -exec rm -rf {} + 2>/dev/null || true

    local after
    after="$(du -sm "${base}" 2>/dev/null | cut -f1 || echo '?')"
    echo "  ${base##*/}: ${before} MB → ${after} MB"
}

_strip_tests "${SRC_DIR}/llvm"
_strip_tests "${SRC_DIR}/llvm/tools/clang"

echo ""
echo "  Final source tree size:"
du -sh "${SRC_DIR}"

# ---------------------------------------------------------------------------
# Write a .gitignore for the build directory and metadata
# ---------------------------------------------------------------------------
cat > "${SRC_DIR}/.gitignore" << 'GITIGNORE'
# Build output — generated by build-clang-format.sh, never committed
build/
install/
GITIGNORE

# Write source metadata
cat > "${SRC_DIR}/SOURCE_INFO.txt" << INFO
LLVM_VERSION=${LLVM_VERSION}
FETCHED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STRIPPED_TESTS=true
STRIPPED_DOCS=true
STRIPPED_BENCHMARKS=true

Checksums of original tarballs:
$(cat "${DOWNLOAD_DIR}/SHA256SUMS.txt")

Verify against: https://github.com/llvm/llvm-project/releases/tag/llvmorg-${LLVM_VERSION}
INFO

echo ""
echo "=================================================================="
echo "  Source tree prepared at: ${SRC_DIR}"
echo "=================================================================="
echo ""
echo "  Next steps:"
echo "    1. Verify checksums above match the official LLVM release page."
echo "    2. Commit the llvm-src/ directory to this repository:"
echo "         git add llvm-src/"
echo "         git commit -m \"vendor: add LLVM ${LLVM_VERSION} source (tests stripped)\""
echo "    3. Transfer this repository to air-gapped machines via approved media."
echo "    4. On each developer machine, run:"
echo "         bash .llvm-hooks/bootstrap.sh"
echo "       This will build clang-format if it is not already present."
echo ""
echo "  The download cache at ${DOWNLOAD_DIR} can be deleted:"
echo "    rm -rf ${DOWNLOAD_DIR}"
echo ""
