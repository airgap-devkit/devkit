#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# cmake/bootstrap.sh
#
# PURPOSE: Install CMake 4.3.0 from vendored prebuilt binaries (default),
#          or build from vendored source (--build-from-source).
#
# USAGE:
#   bash cmake/bootstrap.sh                   # prebuilt (default)
#   bash cmake/bootstrap.sh --build-from-source
#   bash cmake/bootstrap.sh --rebuild         # force re-install
#
# INSTALL LOCATIONS (via scripts/install-mode.sh):
#   Admin  Linux   : /opt/airgap-cpp-devkit/cmake/
#   Admin  Windows : C:\Program Files\airgap-cpp-devkit\cmake\
#   User   Linux   : ~/.local/share/airgap-cpp-devkit/cmake/
#   User   Windows : %LOCALAPPDATA%\airgap-cpp-devkit\cmake\
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PREBUILT_DIR="${REPO_ROOT}/prebuilt-binaries/cmake"
CMAKE_VERSION="4.3.0"

# ---------------------------------------------------------------------------
# Source install-mode library
# ---------------------------------------------------------------------------
# shellcheck source=../scripts/install-mode.sh
source "${REPO_ROOT}/scripts/install-mode.sh"

INSTALL_DIR="$(get_install_dir cmake)"
INSTALL_MODE="$(get_install_mode)"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
BUILD_FROM_SOURCE=false
REBUILD=false

for arg in "$@"; do
    case "${arg}" in
        --build-from-source) BUILD_FROM_SOURCE=true ;;
        --rebuild)           REBUILD=true ;;
        *) echo "[ERROR] Unknown argument: ${arg}"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    Linux*)                PLATFORM="linux"   ;;
    *) echo "[ERROR] Unsupported platform: $(uname -s)"; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  airgap-cpp-devkit — CMake ${CMAKE_VERSION} Bootstrap                  ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  Platform : ${PLATFORM}                                               ║"
echo "║  Mode     : $(${BUILD_FROM_SOURCE} && echo 'build-from-source' || echo 'prebuilt (default)  ')                          ║"
echo "║  Install  : ${INSTALL_MODE}                                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ---------------------------------------------------------------------------
# Check if already installed
# ---------------------------------------------------------------------------
CMAKE_BIN="${INSTALL_DIR}/bin/cmake"
[[ "${PLATFORM}" == "windows" ]] && CMAKE_BIN="${INSTALL_DIR}/bin/cmake.exe"

if [[ -f "${CMAKE_BIN}" ]] && [[ "${REBUILD}" == "false" ]]; then
    INSTALLED_VER=$("${CMAKE_BIN}" --version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")
    echo "[INFO] CMake already installed at ${CMAKE_BIN} (${INSTALLED_VER})"
    echo "       Use --rebuild to force re-installation."
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Verify prebuilt-binaries submodule is populated
# ---------------------------------------------------------------------------
if [[ ! -d "${PREBUILT_DIR}" ]]; then
    echo "[ERROR] prebuilt-binaries submodule not initialized."
    echo "        Run: bash scripts/setup-prebuilt-submodule.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify SHA256 of parts against manifest.json
# ---------------------------------------------------------------------------
MANIFEST="${REPO_ROOT}/cmake/manifest.json"

_verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual
    actual="$(sha256sum "${file}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "[ERROR] SHA256 mismatch: ${file}"
        echo "        Expected : ${expected}"
        echo "        Got      : ${actual}"
        exit 1
    fi
    echo "[OK]   SHA256 verified: $(basename "${file}")"
}

# ---------------------------------------------------------------------------
# PREBUILT PATH
# ---------------------------------------------------------------------------
if [[ "${BUILD_FROM_SOURCE}" == "false" ]]; then

    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "${WORK_DIR}"' EXIT

    if [[ "${PLATFORM}" == "linux" ]]; then
        PART_AA="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz.part-aa"
        PART_AB="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz.part-ab"
        ASSEMBLED="${WORK_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"

        echo "[INFO] Verifying parts..."
        _verify_sha256 "${PART_AA}" "57d532fe7e398e16c16b07a01313a74cf71b03b9ddb39493f337e3598d7838e5"
        _verify_sha256 "${PART_AB}" "0fe83ca763e44f555794cce952c7a6bc7484841a8ecff4de23a43f2e863dd738"

        echo "[INFO] Reassembling archive..."
        cat "${PART_AA}" "${PART_AB}" > "${ASSEMBLED}"

        echo "[INFO] Extracting to ${INSTALL_DIR}..."
        mkdir -p "${INSTALL_DIR}"
        tar -xzf "${ASSEMBLED}" -C "${WORK_DIR}"
        # The tarball extracts to cmake-4.3.0-linux-x86_64/
        EXTRACTED_DIR="${WORK_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64"
        cp -r "${EXTRACTED_DIR}/." "${INSTALL_DIR}/"

    elif [[ "${PLATFORM}" == "windows" ]]; then
        PART_AA="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64.zip.part-aa"
        PART_AB="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64.zip.part-ab"
        ASSEMBLED="${WORK_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64.zip"

        echo "[INFO] Verifying parts..."
        _verify_sha256 "${PART_AA}" "4ac8f0d10b7d771e28fa5ecba9f5683756b6327ebfdbd66c552f430c3655ba59"
        _verify_sha256 "${PART_AB}" "bf4abc210d2c83ce6542de3158cbd8239e09c24605718095b68d1f1c1094a113"

        echo "[INFO] Reassembling archive..."
        cat "${PART_AA}" "${PART_AB}" > "${ASSEMBLED}"

        echo "[INFO] Extracting to ${INSTALL_DIR}..."
        mkdir -p "${INSTALL_DIR}"
        unzip -q "${ASSEMBLED}" -d "${WORK_DIR}"
        # The zip extracts to cmake-4.3.0-windows-x86_64/
        EXTRACTED_DIR="${WORK_DIR}/cmake-${CMAKE_VERSION}-windows-x86_64"
        cp -r "${EXTRACTED_DIR}/." "${INSTALL_DIR}/"
    fi

# ---------------------------------------------------------------------------
# SOURCE BUILD PATH
# ---------------------------------------------------------------------------
else

    SOURCE_TARBALL="${PREBUILT_DIR}/cmake-${CMAKE_VERSION}.tar.gz"

    echo "[INFO] Verifying source tarball..."
    _verify_sha256 "${SOURCE_TARBALL}" "f51b3c729f85d8dde46a92c071d2826ea6afb77d850f46894125de7cc51baa77"

    # Require a C++ compiler
    if ! command -v g++ &>/dev/null && ! command -v c++ &>/dev/null; then
        echo "[ERROR] No C++ compiler found. Install GCC first:"
        echo "        Linux  : sudo dnf install gcc-c++"
        echo "        Windows: ensure WinLibs GCC is on PATH"
        exit 1
    fi

    BUILD_WORK="$(mktemp -d)"
    trap 'rm -rf "${BUILD_WORK}"' EXIT

    echo "[INFO] Extracting source tarball..."
    tar -xzf "${SOURCE_TARBALL}" -C "${BUILD_WORK}"
    SRC_DIR="${BUILD_WORK}/cmake-${CMAKE_VERSION}"

    echo "[INFO] Bootstrapping CMake from source (this takes ~10-20 min)..."
    mkdir -p "${BUILD_WORK}/cmake-build"
    cd "${BUILD_WORK}/cmake-build"

    "${SRC_DIR}/bootstrap" \
        --prefix="${INSTALL_DIR}" \
        --parallel="$(nproc 2>/dev/null || echo 4)"

    echo "[INFO] Building..."
    make -j"$(nproc 2>/dev/null || echo 4)"

    echo "[INFO] Installing to ${INSTALL_DIR}..."
    make install

    cd "${REPO_ROOT}"
fi

# ---------------------------------------------------------------------------
# Write install receipt
# ---------------------------------------------------------------------------
mkdir -p "${INSTALL_DIR}"
cat > "${INSTALL_DIR}/.airgap-receipt" <<EOF
tool=cmake
version=${CMAKE_VERSION}
installed=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mode=${INSTALL_MODE}
build=$(${BUILD_FROM_SOURCE} && echo "source" || echo "prebuilt")
EOF

# ---------------------------------------------------------------------------
# Verify installed binary
# ---------------------------------------------------------------------------
echo ""
echo "[INFO] Verifying installation..."
if "${CMAKE_BIN}" --version &>/dev/null; then
    INSTALLED_VER=$("${CMAKE_BIN}" --version | head -1)
    echo "[✓] ${INSTALLED_VER}"
    echo "[✓] Installed at: ${INSTALL_DIR}"
else
    echo "[ERROR] cmake binary not functional after install."
    exit 1
fi

echo ""
echo "  Add to PATH if needed:"
if [[ "${PLATFORM}" == "linux" ]]; then
    echo "    export PATH=\"${INSTALL_DIR}/bin:\$PATH\""
else
    echo "    export PATH=\"$(cygpath -u "${INSTALL_DIR}")/bin:\$PATH\""
fi
echo ""