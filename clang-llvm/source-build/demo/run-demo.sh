#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# clang-llvm-source-build/demo/run-demo.sh
#
# PURPOSE: Demonstrate clang-tidy against a C++ file containing intentional
#          issues. Shows what clang-tidy catches before it is wired into a
#          real project.
#
# USAGE:
#   bash clang-llvm-source-build/demo/run-demo.sh
#
# PREREQUISITES:
#   • clang-tidy assembled at bin/linux/clang-tidy
#     (run bootstrap.sh first if not present)
#   • g++ available on PATH (for compile_commands.json generation)
#
# The script does NOT modify demo.cpp. It only reads it.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLANG_TIDY="${MODULE_ROOT}/bin/linux/clang-tidy"
DEMO_SRC="${SCRIPT_DIR}/demo.cpp"

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
echo "============================================================"
echo " clang-tidy demo"
echo "============================================================"
echo ""

if [[ ! -x "${CLANG_TIDY}" ]]; then
    echo "[ERROR] clang-tidy not found at: ${CLANG_TIDY}"
    echo ""
    echo "  Run bootstrap first:"
    echo "    bash clang-llvm-source-build/bootstrap.sh"
    exit 1
fi

TIDY_VER="$("${CLANG_TIDY}" --version 2>/dev/null | head -1)"
echo "  clang-tidy : ${TIDY_VER}"
echo "  Source     : ${DEMO_SRC}"
echo ""

# ---------------------------------------------------------------------------
# Checks to run
# ---------------------------------------------------------------------------
CHECKS=(
    "modernize-use-nullptr"
    "modernize-use-override"
    "modernize-loop-convert"
    "readability-magic-numbers"
    "cppcoreguidelines-init-variables"
    "performance-unnecessary-copy-initialization"
)

CHECKS_ARG=$(IFS=,; echo "${CHECKS[*]}")

echo "  Enabled checks:"
for c in "${CHECKS[@]}"; do
    echo "    • ${c}"
done
echo ""

# ---------------------------------------------------------------------------
# Run clang-tidy
# ---------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo " Diagnostics"
echo "------------------------------------------------------------"
echo ""

# -- header-filter set to empty string so we only see issues in demo.cpp itself
# -- extra-arg passes C++17 standard so modernize checks work correctly
"${CLANG_TIDY}" \
    "${DEMO_SRC}" \
    --checks="-*,${CHECKS_ARG}" \
    --header-filter="" \
    --extra-arg="-std=c++17" \
    --extra-arg="-I/usr/include" \
    -- 2>&1 || true
# || true: clang-tidy exits non-zero when it finds issues; we want to see them

echo ""
echo "------------------------------------------------------------"
echo " Done."
echo " The issues above are intentional. See demo/demo.cpp for"
echo " comments explaining each one."
echo "------------------------------------------------------------"
echo ""