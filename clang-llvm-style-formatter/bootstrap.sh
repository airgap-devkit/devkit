#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — One-command developer onboarding
#
# Run this once after cloning any host repository that uses
# clang-llvm-style-formatter as a submodule.
#
# What it does (in order):
#   1. Initialises and updates git submodules (including .llvm-hooks).
#   2. Tries to locate clang-format / clang-tidy on PATH.
#   3. If not found, runs setup-user-path.sh --auto.
#   4. Runs install-hooks.sh to wire the pre-commit hook.
#   5. Prints a health summary.
#
# Usage (from host repo root):
#   bash .llvm-hooks/bootstrap.sh [--force] [--skip-path-setup]
# =============================================================================

set -euo pipefail

FORCE=""
SKIP_PATH_SETUP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)           FORCE="--force";     shift ;;
        --skip-path-setup) SKIP_PATH_SETUP=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--force] [--skip-path-setup]"
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "[bootstrap] ERROR: Not inside a git repository." >&2
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================================="
echo "  clang-llvm-style-formatter — Developer Bootstrap"
echo "=================================================================="
echo ""

# ---------------------------------------------------------------------------
# Step 1 — Initialise submodules
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 1/4: Initialising git submodules…"
git -C "${REPO_ROOT}" submodule update --init --recursive
echo "            Done."
echo ""

# ---------------------------------------------------------------------------
# Step 2 — Verify tools (delegates to verify-tools.sh for rich diagnostics)
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 2/4: Verifying clang-format installation…"
CF_OK=false

if bash "${SCRIPT_DIR}/scripts/verify-tools.sh" --quiet 2>/dev/null; then
    CF_OK=true
    CF_VER="$(clang-format --version 2>/dev/null | head -1 || echo "found")"
    echo "            clang-format : ${CF_VER} ✓"
else
    echo "            clang-format : NOT FOUND or version too old"
fi
echo ""

# ---------------------------------------------------------------------------
# Step 3 — PATH setup if needed
# ---------------------------------------------------------------------------
if [[ "${CF_OK}" == "false" && "${SKIP_PATH_SETUP}" == "false" ]]; then
    echo "[bootstrap] Step 3/4: Attempting automatic PATH discovery…"
    bash "${SCRIPT_DIR}/scripts/setup-user-path.sh" --auto 2>&1 | sed 's/^/            /'
    echo ""
    # Re-verify after PATH update (new PATH takes effect in same shell)
    if bash "${SCRIPT_DIR}/scripts/verify-tools.sh" --quiet 2>/dev/null; then
        CF_OK=true
        echo "            clang-format now reachable ✓"
        echo "            Open a new terminal for the PATH change to persist."
    elif [[ -f "${SCRIPT_DIR}/llvm-src/SOURCE_INFO.txt" ]]; then
        echo ""
        echo "            clang-format not found — but vendored LLVM source is present."
        echo ""
        echo "            ┌─────────────────────────────────────────────────┐"
        echo "            │  Build clang-format from vendored source?       │"
        echo "            │  This takes 30–60 minutes on first run.         │"
        echo "            └─────────────────────────────────────────────────┘"
        read -r -p "            Build now? [y/N] " build_confirm
        if [[ "${build_confirm,,}" == "y" ]]; then
            bash "${SCRIPT_DIR}/scripts/build-clang-format.sh"
            if bash "${SCRIPT_DIR}/scripts/verify-tools.sh" --quiet 2>/dev/null; then
                CF_OK=true
                echo "            clang-format built and ready ✓"
            fi
        fi
    else
        echo ""
        echo "            ┌─────────────────────────────────────────────────┐"
        echo "            │  clang-format could not be located.             │"
        echo "            │  No vendored source found either.               │"
        echo "            │                                                 │"
        echo "            │  Run the full diagnostic:                       │"
        echo "            │    bash .llvm-hooks/scripts/verify-tools.sh     │"
        echo "            └─────────────────────────────────────────────────┘"
        echo ""
    fi
else
    echo "[bootstrap] Step 3/4: PATH setup — skipped (tool already found or --skip-path-setup set)."
fi
echo ""

# ---------------------------------------------------------------------------
# Step 4 — Install hooks
# ---------------------------------------------------------------------------
echo "[bootstrap] Step 4/4: Installing pre-commit hook…"
# shellcheck disable=SC2086
bash "${SCRIPT_DIR}/scripts/install-hooks.sh" ${FORCE} 2>&1 | sed 's/^/            /'
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=================================================================="
echo "  Bootstrap complete"
echo "=================================================================="
_yn() { [[ "$1" == "true" ]] && echo "YES" || echo "NO  ← action needed"; }
echo "  clang-format available : $(_yn "${CF_OK}")"
echo "  pre-commit hook        : $(
    [[ -f "${REPO_ROOT}/.git/hooks/pre-commit" ]] && echo "installed" || echo "MISSING"
)"
echo ""
if [[ "${CF_OK}" == "false" ]]; then
    echo "  ACTION REQUIRED:"
    echo "    clang-format is not available. The pre-commit hook will error"
    echo "    on the next commit attempt."
    echo ""
    echo "    Run the install guide diagnostic for your platform:"
    echo "      bash .llvm-hooks/scripts/verify-tools.sh"
    echo ""
    echo "    See: .llvm-hooks/docs/llvm-install-guide.md"
fi
echo ""
