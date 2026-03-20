#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# bootstrap.sh — Build clang-format and install clang-tidy from LLVM source
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  This is the SLOW path (~30-60 minutes) for clang-format.               │
# │                                                                         │
# │  Most developers should use the fast pip/venv method for clang-format:  │
# │    bash clang-llvm-style-formatter/bootstrap.sh   # ~5 seconds          │
# │                                                                         │
# │  Use this script if:                                                    │
# │    • Python is not available on developer machines                      │
# │    • Policy requires building all tools from source                     │
# │    • You need clang-tidy (this is the only way to get it)               │
# └─────────────────────────────────────────────────────────────────────────┘
#
# This script handles two binaries:
#
#   clang-format  — built from the vendored LLVM 22.1.1 source tarball
#                   (~30-60 min compile time on first build)
#
#   clang-tidy    — Linux  : reassembled from vendored pre-built split parts
#                            (verify SHA256 + reassemble, seconds)
#                   Windows: vendored pre-built binary (46 MB, verify SHA256)
#                            Pass --build-from-source to compile instead.
#
# Build prerequisites (clang-format source build, both platforms):
#   Windows : Visual Studio 2017/2019/2022/Insiders with C++ workload
#             Tested: VS Insiders 18 | MSVC toolchain 14.50.35717 | CMake 4.1.2
#             Minimum: CMake 3.14, any VS edition with VC++ tools
#             Run from Git Bash — VS environment is set up automatically.
#   RHEL 8  : GCC 8+ (gcc-c++), CMake 3.14+, Python 3.6+
#
# Output binaries:
#   bin/linux/clang-format
#   bin/linux/clang-tidy       (reassembled from vendored parts)
#   bin/windows/clang-format.exe
#   bin/windows/clang-tidy.exe (vendored pre-built, or --build-from-source)
#
# Usage:
#   bash clang-llvm-source-build/bootstrap.sh [--rebuild] [--build-from-source]
#
# Options:
#   --rebuild            Force rebuild/re-verify of all binaries
#   --build-from-source  Windows only: build clang-tidy from LLVM source
#                        instead of using the vendored pre-built binary
#
# See docs/llvm-install-guide.md for full prerequisites and troubleshooting.
# =============================================================================

set -euo pipefail

REBUILD=false
BUILD_FROM_SOURCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild)           REBUILD=true; shift ;;
        --build-from-source) BUILD_FROM_SOURCE=true; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMATTER_DIR="$(cd "${SCRIPT_DIR}/../clang-llvm-style-formatter" 2>/dev/null && pwd)" || \
    FORMATTER_DIR="${SCRIPT_DIR}/../clang-llvm-style-formatter"

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)                OS="linux"   ;;
    *)  echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

OUTPUT_FMT_WIN="${SCRIPT_DIR}/bin/windows/clang-format.exe"
OUTPUT_FMT_LIN="${SCRIPT_DIR}/bin/linux/clang-format"
OUTPUT_TIDY_WIN="${SCRIPT_DIR}/bin/windows/clang-tidy.exe"
OUTPUT_TIDY_LIN="${SCRIPT_DIR}/bin/linux/clang-tidy"

case "${OS}" in
    windows) OUTPUT_FMT="${OUTPUT_FMT_WIN}"; OUTPUT_TIDY="${OUTPUT_TIDY_WIN}" ;;
    linux)   OUTPUT_FMT="${OUTPUT_FMT_LIN}"; OUTPUT_TIDY="${OUTPUT_TIDY_LIN}" ;;
esac

echo "=================================================================="
echo "  clang-llvm-source-build"
echo "  Platform     : ${OS}"
echo "  clang-format : ${OUTPUT_FMT}"
echo "  clang-tidy   : ${OUTPUT_TIDY}"
echo "=================================================================="
echo ""

# ==========================================================================
# PART 1 — clang-format (source build, both platforms)
# ==========================================================================
echo "------------------------------------------------------------------"
echo "  [1/2] clang-format"
echo "------------------------------------------------------------------"
echo ""

if [[ -x "${OUTPUT_FMT}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_FMT}" --version 2>/dev/null | head -1)"
    echo "  Already built: ${VER}"
    echo "  Use --rebuild to force a rebuild."
else
    echo "  This build takes 30-60 minutes."
    echo "  For a 5-second install, use the pip method instead:"
    echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
    echo ""
    export REBUILD
    bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"

    [[ -x "${OUTPUT_FMT}" ]] || {
        echo "ERROR: Build completed but clang-format not found at ${OUTPUT_FMT}" >&2
        exit 1
    }
    VER="$("${OUTPUT_FMT}" --version 2>/dev/null | head -1)"
    echo ""
    echo "  Built: ${VER}"
fi

echo ""

# ==========================================================================
# PART 2 — clang-tidy
#   Linux  : reassemble pre-built vendored binary from split parts
#   Windows: verify vendored pre-built binary (or build from source)
# ==========================================================================
echo "------------------------------------------------------------------"
echo "  [2/2] clang-tidy"
echo "------------------------------------------------------------------"
echo ""

if [[ -x "${OUTPUT_TIDY}" && "${REBUILD}" == "false" ]]; then
    VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | grep "LLVM version" | head -1)"
    echo "  Already present: ${VER}"
    echo "  Use --rebuild to force re-verification."
else
    case "${OS}" in
        linux)
            echo "  Linux: reassembling from vendored pre-built parts..."
            echo ""
            bash "${SCRIPT_DIR}/scripts/reassemble-clang-tidy.sh"

            [[ -x "${OUTPUT_TIDY}" ]] || {
                echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY} after reassembly." >&2
                exit 1
            }
            ;;
        windows)
            if [[ "${BUILD_FROM_SOURCE}" == "true" ]]; then
                echo "  Windows: building from source (--build-from-source)."
                echo "  Expected time: ~60-120 min first build."
                echo ""
                bash "${SCRIPT_DIR}/scripts/build-clang-tidy.sh" \
                    $([[ "${REBUILD}" == "true" ]] && echo "--rebuild" || true)
            else
                echo "  Windows: verifying vendored pre-built binary..."
                echo ""
                bash "${SCRIPT_DIR}/scripts/verify-clang-tidy-windows.sh"
            fi

            [[ -x "${OUTPUT_TIDY}" ]] || {
                echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY}." >&2
                exit 1
            }
            ;;
    esac

    VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | grep "LLVM version" | head -1)"
    echo ""
    echo "  Ready: ${VER}"
fi

echo ""

# ==========================================================================
# Summary
# ==========================================================================
echo "=================================================================="
echo "  All done."
echo "  clang-format : ${OUTPUT_FMT}"
echo "  clang-tidy   : ${OUTPUT_TIDY}"
echo "=================================================================="
echo ""
echo "  Now activate the pre-commit hook:"
echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
echo ""