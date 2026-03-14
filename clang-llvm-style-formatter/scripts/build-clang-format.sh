#!/usr/bin/env bash
# =============================================================================
# build-clang-format.sh — Build clang-format from the vendored LLVM source
#                          in llvm-src/ and install it into bin/<platform>/.
#
# This script is called automatically by bootstrap.sh when clang-format is
# not found on the system. Developers can also run it directly.
#
# Prerequisites (must already be on the machine — LLVM is not required):
#   Windows : Visual Studio 2017/2019/2022 (MSVC), CMake 3.14+, Ninja
#   RHEL 8  : GCC 8+, CMake 3.14+, Ninja (or GNU make)
#
# The compiled binary is installed to:
#   <submodule>/bin/windows/clang-format.exe   (Windows)
#   <submodule>/bin/linux/clang-format          (Linux)
#
# The pre-commit hook and find-tools.sh will automatically discover binaries
# at these paths, so no PATH modification is needed after building.
#
# Usage:
#   bash scripts/build-clang-format.sh [--jobs N] [--rebuild] [--no-ninja]
#
# Options:
#   --jobs N       Parallel compile jobs (default: number of CPU cores)
#   --rebuild      Delete any existing build directory and rebuild from scratch
#   --no-ninja     Force use of make instead of Ninja (slower)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
JOBS=""
REBUILD=false
NO_NINJA=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jobs)    JOBS="$2";     shift 2 ;;
        --rebuild) REBUILD=true;  shift ;;
        --no-ninja) NO_NINJA=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--jobs N] [--rebuild] [--no-ninja]"
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SUBMODULE_ROOT}/llvm-src"
BUILD_DIR="${SRC_DIR}/build"
INSTALL_DIR="${SRC_DIR}/install"

# ---------------------------------------------------------------------------
# OS/platform detection
# ---------------------------------------------------------------------------
_detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)                echo "linux"   ;;
        Darwin*)               echo "macos"   ;;
        *)                     echo "unknown" ;;
    esac
}
OS="$(_detect_os)"

case "${OS}" in
    windows)
        BIN_DIR="${SUBMODULE_ROOT}/bin/windows"
        OUTPUT_BIN="${BIN_DIR}/clang-format.exe"
        BUILT_BIN="${INSTALL_DIR}/bin/clang-format.exe"
        ;;
    *)
        BIN_DIR="${SUBMODULE_ROOT}/bin/linux"
        OUTPUT_BIN="${BIN_DIR}/clang-format"
        BUILT_BIN="${INSTALL_DIR}/bin/clang-format"
        ;;
esac

# ---------------------------------------------------------------------------
# Check source tree exists
# ---------------------------------------------------------------------------
if [[ ! -f "${SRC_DIR}/SOURCE_INFO.txt" ]]; then
    echo "" >&2
    echo "ERROR: LLVM source tree not found at ${SRC_DIR}" >&2
    echo "" >&2
    echo "  The vendored source has not been fetched yet." >&2
    echo "  Run fetch-llvm-source.sh to populate the source tree:" >&2
    echo "    bash ${SCRIPT_DIR}/fetch-llvm-source.sh" >&2
    echo "  Then commit llvm-src/ and transfer this repo to the air-gapped machine." >&2
    echo "" >&2
    exit 1
fi

LLVM_VERSION="$(grep '^LLVM_VERSION=' "${SRC_DIR}/SOURCE_INFO.txt" | cut -d= -f2)"

echo "=================================================================="
echo "  build-clang-format.sh"
echo "  LLVM version : ${LLVM_VERSION}"
echo "  Platform     : ${OS}"
echo "  Source       : ${SRC_DIR}"
echo "  Build dir    : ${BUILD_DIR}"
echo "  Install to   : ${OUTPUT_BIN}"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Already built?
# ---------------------------------------------------------------------------
if [[ -x "${OUTPUT_BIN}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1 || echo "unknown")"
    echo "  clang-format already built: ${VER}"
    echo "  Location: ${OUTPUT_BIN}"
    echo "  Use --rebuild to force a rebuild."
    echo ""
    exit 0
fi

if [[ "${REBUILD}" == "true" && -d "${BUILD_DIR}" ]]; then
    echo "  --rebuild: removing ${BUILD_DIR}…"
    rm -rf "${BUILD_DIR}" "${INSTALL_DIR}"
fi

# ---------------------------------------------------------------------------
# Detect build tools
# ---------------------------------------------------------------------------
_require_tool() {
    local tool="$1" label="$2"
    if ! command -v "${tool}" &>/dev/null; then
        echo "" >&2
        echo "ERROR: '${tool}' (${label}) is required but not found on PATH." >&2
        echo "" >&2
        _print_prereq_guidance
        exit 1
    fi
    echo "  Found: ${tool} → $(command -v "${tool}")"
}

_print_prereq_guidance() {
    echo "  Prerequisites for building clang-format from source:" >&2
    echo "" >&2
    case "${OS}" in
        windows)
            echo "  Windows requires:" >&2
            echo "    • Visual Studio 2017/2019/2022 with C++ workload" >&2
            echo "    • CMake 3.14+  (bundled with VS 2019+, or cmake.org)" >&2
            echo "    • Ninja        (bundled with VS, or github.com/ninja-build/ninja/releases)" >&2
            echo "" >&2
            echo "  Open this script from an x64 Native Tools Command Prompt for VS 20xx." >&2
            ;;
        linux|rhel)
            echo "  RHEL 8 / Linux requires:" >&2
            echo "    • GCC 8+ or Clang 14+   (sudo dnf groupinstall 'Development Tools')" >&2
            echo "    • CMake 3.14+            (sudo dnf install cmake)" >&2
            echo "    • Ninja (recommended)    (sudo dnf install ninja-build)" >&2
            echo "    • Python 3.6+            (usually pre-installed)" >&2
            ;;
        *)
            echo "  Install: cmake, ninja (or make), gcc/g++ or clang/clang++" >&2
            ;;
    esac
    echo "" >&2
}

echo "  Checking build prerequisites…"

_require_tool cmake "CMake build system"

# Ninja vs make
CMAKE_GENERATOR=""
BUILD_TOOL=""
if [[ "${NO_NINJA}" == "false" ]] && command -v ninja &>/dev/null; then
    CMAKE_GENERATOR="-G Ninja"
    BUILD_TOOL="ninja"
    echo "  Found: ninja → $(command -v ninja)"
elif command -v make &>/dev/null; then
    CMAKE_GENERATOR=""
    BUILD_TOOL="make"
    echo "  Found: make → $(command -v make) (Ninja not found; using make — slower)"
else
    echo "ERROR: Neither ninja nor make found on PATH." >&2
    _print_prereq_guidance
    exit 1
fi

# C++ compiler check
if [[ "${OS}" == "windows" ]]; then
    # On Windows, cmake will find MSVC automatically when run from a VS command prompt.
    # We just check cmake is present (already done above).
    echo "  Assuming MSVC available via VS environment (vcvarsall or VS Command Prompt)"
else
    if command -v g++ &>/dev/null; then
        echo "  Found: g++ → $(g++ --version | head -1)"
    elif command -v c++ &>/dev/null; then
        echo "  Found: c++ → $(c++ --version | head -1)"
    else
        echo "ERROR: No C++ compiler (g++/c++) found." >&2
        _print_prereq_guidance
        exit 1
    fi
fi

# Parallel jobs
if [[ -z "${JOBS}" ]]; then
    if command -v nproc &>/dev/null; then
        JOBS="$(nproc)"
    elif [[ "${OS}" == "windows" ]] && [[ -n "${NUMBER_OF_PROCESSORS:-}" ]]; then
        JOBS="${NUMBER_OF_PROCESSORS}"
    else
        JOBS="4"
    fi
fi
echo "  Parallel jobs: ${JOBS}"
echo ""

# ---------------------------------------------------------------------------
# CMake configure
# ---------------------------------------------------------------------------
echo "[Step 1/3] CMake configure…"
echo ""

mkdir -p "${BUILD_DIR}"

# Key flags:
#   LLVM_ENABLE_PROJECTS=clang  — build clang alongside LLVM (required for clang-format)
#   LLVM_TARGETS_TO_BUILD=host  — only the current machine's target arch (not all 20+)
#   CMAKE_BUILD_TYPE=Release    — optimised, no debug symbols → smaller, faster
#   LLVM_INCLUDE_TESTS=OFF      — skip test infrastructure entirely
#   LLVM_INCLUDE_BENCHMARKS=OFF — skip benchmarks
#   LLVM_INCLUDE_DOCS=OFF       — skip documentation generation
#   LLVM_INCLUDE_EXAMPLES=OFF   — skip examples
#   CLANG_INCLUDE_TESTS=OFF     — skip clang test infrastructure
#   CLANG_BUILD_TOOLS=ON        — ensures clang-format target is present

# Fix paths that CMake needs for the cmake/third-party sibling dirs
# (LLVM expects these parallel to the llvm/ source directory)
CMAKE_SRC="${SRC_DIR}/llvm"

CMAKE_ARGS=(
    ${CMAKE_GENERATOR}
    -S "${CMAKE_SRC}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_ENABLE_PROJECTS="clang"
    -DLLVM_TARGETS_TO_BUILD="host"
    -DLLVM_INCLUDE_TESTS=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_BUILD_TOOLS=ON
    -DLLVM_ENABLE_ASSERTIONS=OFF
    -DCLANG_INCLUDE_TESTS=OFF
    -DCLANG_BUILD_TOOLS=ON
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_ENABLE_LIBXML2=OFF
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"
)

# On Windows, help CMake find the cmake/ and third-party/ sibling dirs
if [[ "${OS}" == "windows" ]]; then
    CMAKE_ARGS+=(
        -DLLVM_COMMON_CMAKE_UTILS="${SRC_DIR}/cmake"
        -DLLVM_THIRD_PARTY_DIR="${SRC_DIR}/third-party"
    )
fi

cmake "${CMAKE_ARGS[@]}"
echo ""

# ---------------------------------------------------------------------------
# Build — only the clang-format target
# ---------------------------------------------------------------------------
echo "[Step 2/3] Building clang-format (${JOBS} jobs)…"
echo "  This will take 30–60 minutes on first build."
echo ""

if [[ "${BUILD_TOOL}" == "ninja" ]]; then
    ninja -C "${BUILD_DIR}" -j "${JOBS}" clang-format
else
    make -C "${BUILD_DIR}" -j "${JOBS}" clang-format
fi
echo ""

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
echo "[Step 3/3] Installing clang-format…"
echo ""

mkdir -p "${BIN_DIR}"

# Copy just the clang-format binary — we don't need the full install
if [[ "${OS}" == "windows" ]]; then
    cp "${BUILD_DIR}/bin/clang-format.exe" "${OUTPUT_BIN}"
else
    cp "${BUILD_DIR}/bin/clang-format" "${OUTPUT_BIN}"
    chmod +x "${OUTPUT_BIN}"
fi

echo ""
echo "=================================================================="
echo "  Build complete"
echo "=================================================================="
echo ""
VER="$("${OUTPUT_BIN}" --version 2>/dev/null | head -1)"
echo "  Binary  : ${OUTPUT_BIN}"
echo "  Version : ${VER}"
echo ""
echo "  The pre-commit hook will automatically use this binary."
echo "  No PATH changes are required."
echo ""
echo "  You can safely delete the build directory to reclaim disk space:"
echo "    rm -rf ${BUILD_DIR}"
echo "  The binary at ${OUTPUT_BIN} is all that's kept."
echo ""
