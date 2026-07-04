#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/internal/checksum-verify.sh
#
# Cross-project integrity gate built on the dso-suite `checksum_generator`
# engine (stdlib-only, vendored at scripts/internal/lib/checksum_generator.py).
#
# This is ADDITIVE — it does not replace airgap-devkit's prebuilt manifests
# (scripts/internal/lib/generate-manifest.py) or the SBOM checksum flow. It
# provides a uniform whole-tree SHA-256 manifest + drift gate (exit 3) that runs
# identically across every dso-suite-family project (airgap-devkit, oxide-sloc,
# dso-suite) and over any files/repos/artifacts — the shared checksum contract.
#
# USAGE:
#   # Generate a manifest of a tree (default: repo root -> checksums/)
#   bash scripts/internal/checksum-verify.sh generate [--root DIR] [--out-dir DIR]
#
#   # Verify a tree against a prior manifest; exits 3 on drift (added/modified/deleted)
#   bash scripts/internal/checksum-verify.sh verify --baseline PATH [--root DIR]
#
# Extra args after the mode are passed straight through to the engine
# (e.g. --exclude '.git/*' --include 'prebuilt/*').
#
# Exit codes: 0 = ok, 3 = drift found (verify), 1 = usage/other error.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENGINE="${SCRIPT_DIR}/lib/checksum_generator.py"

PY="$(command -v python3 || command -v python || true)"
[[ -n "${PY}" ]] || { echo "[!!] python3 not found on PATH" >&2; exit 1; }
[[ -f "${ENGINE}" ]] || { echo "[!!] checksum engine missing: ${ENGINE}" >&2; exit 1; }

MODE="${1:-}"
shift || true

ROOT="${REPO_ROOT}"
OUT_DIR="checksums"
BASELINE=""
PASSTHRU=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)     ROOT="$2"; shift 2 ;;
        --out-dir)  OUT_DIR="$2"; shift 2 ;;
        --baseline) BASELINE="$2"; shift 2 ;;
        *)          PASSTHRU+=("$1"); shift ;;
    esac
done

case "${MODE}" in
    generate)
        echo "[checksum] Generating manifest for ${ROOT} -> ${OUT_DIR}/"
        "${PY}" "${ENGINE}" --root "${ROOT}" --out-dir "${OUT_DIR}" --ci "${PASSTHRU[@]}"
        ;;
    verify)
        [[ -n "${BASELINE}" ]] || { echo "[!!] verify requires --baseline PATH" >&2; exit 1; }
        echo "[checksum] Verifying ${ROOT} against ${BASELINE} (drift gate, exit 3 on change)"
        "${PY}" "${ENGINE}" --root "${ROOT}" --verify "${BASELINE}" --ci "${PASSTHRU[@]}"
        ;;
    *)
        echo "Usage: bash scripts/internal/checksum-verify.sh {generate|verify} [options]" >&2
        echo "  generate [--root DIR] [--out-dir DIR]" >&2
        echo "  verify --baseline PATH [--root DIR]" >&2
        exit 1
        ;;
esac
