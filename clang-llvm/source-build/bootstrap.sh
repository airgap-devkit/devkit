#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# bootstrap.sh — Build clang-format and install clang-tidy from LLVM source
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  This is the SLOW path (~30-60 minutes) for clang-format.               │
# │                                                                         │
# │  Most developers should use the fast pip/venv method instead:           │
# │    bash clang-llvm-style-formatter/bootstrap.sh                         │
# │                                                                         │
# │  Use this only if:                                                      │
# │    • Python is not available on developer machines                      │
# │    • Policy requires building all tools from source                     │
# └─────────────────────────────────────────────────────────────────────────┘
#
# This script handles two binaries:
#
#   clang-format  — built from the vendored LLVM 22.1.1 source tarball
#                   (~30-60 min compile time)
#
#   clang-tidy    — pre-built binary vendored as split parts in bin/linux/
#                   (reassemble + SHA256 verify, no compile required)
#                   Linux only. Windows binary is not currently vendored.
#
# Compiled / reassembled binaries are placed at:
#   bin/linux/clang-format
#   bin/linux/clang-tidy
#   bin/windows/clang-format.exe
#
# clang-llvm-style-formatter/bootstrap.sh detects these automatically.
#
# Usage:
#   bash clang-llvm-source-build/bootstrap.sh [--rebuild]
#
# Build prerequisites (clang-format source build):
#   Windows : Visual Studio 2017/2019/2022 (C++ workload), CMake 3.14+
#   RHEL 8  : GCC 8+, CMake 3.14+, Python 3.6+
#
# See docs/llvm-install-guide.md for detailed instructions.
# =============================================================================

set -euo pipefail

REBUILD=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --rebuild) REBUILD=true; shift ;;
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
    MINGW*|MSYS*|CYGWIN*) OS="windows"; OUTPUT_FMT="${SCRIPT_DIR}/bin/windows/clang-format.exe" ;;
    Linux*)                OS="linux";   OUTPUT_FMT="${SCRIPT_DIR}/bin/linux/clang-format" ;;
    *)  echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

OUTPUT_TIDY="${SCRIPT_DIR}/bin/linux/clang-tidy"

echo "=================================================================="
echo "  clang-llvm-source-build"
echo "  Platform : ${OS}"
echo "  clang-format output : ${OUTPUT_FMT}"
if [[ "${OS}" == "linux" ]]; then
echo "  clang-tidy output   : ${OUTPUT_TIDY}"
fi
echo "=================================================================="
echo ""

# ==========================================================================
# PART 1 — clang-format (source build)
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
# PART 2 — clang-tidy (vendored pre-built, Linux only)
# ==========================================================================
if [[ "${OS}" == "linux" ]]; then
    echo "------------------------------------------------------------------"
    echo "  [2/2] clang-tidy (pre-built, reassemble + verify)"
    echo "------------------------------------------------------------------"
    echo ""

    if [[ -x "${OUTPUT_TIDY}" && "${REBUILD}" == "false" ]]; then
        VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | head -1)"
        echo "  Already present: ${VER}"
        echo "  Use --rebuild to force re-verification and reassembly."
    else
        bash "${SCRIPT_DIR}/scripts/reassemble-clang-tidy.sh"

        [[ -x "${OUTPUT_TIDY}" ]] || {
            echo "ERROR: clang-tidy not found at ${OUTPUT_TIDY} after reassembly." >&2
            exit 1
        }
        VER="$("${OUTPUT_TIDY}" --version 2>/dev/null | head -1)"
        echo ""
        echo "  Ready: ${VER}"
    fi
    echo ""
else
    echo "  [2/2] clang-tidy — skipped (no pre-built Windows binary vendored)"
    echo ""
fi

# ==========================================================================
# Summary
# ==========================================================================
echo "=================================================================="
echo "  All done."
if [[ "${OS}" == "linux" ]]; then
echo "  clang-format : ${OUTPUT_FMT}"
echo "  clang-tidy   : ${OUTPUT_TIDY}"
else
echo "  clang-format : ${OUTPUT_FMT}"
fi
echo "=================================================================="
echo ""
echo "  Now activate the pre-commit hook:"
echo "    bash ${FORMATTER_DIR}/bootstrap.sh"
echo ""