#!/usr/bin/env bash
# Runs the fast, headless validation suite (no running server required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/tests/validate-manifests.sh" "${@:---verbose}"
