#!/usr/bin/env bash
set -euo pipefail
: "${1:?Usage: ci/release.sh <version> [--no-build] [--upload] [--test]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/release.sh" "$@"
