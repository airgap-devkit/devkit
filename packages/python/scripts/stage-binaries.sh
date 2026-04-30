#!/usr/bin/env bash
# Copy prebuilt server binaries into the Python package before building the wheel.
# Run from the repo root: bash packages/python/scripts/stage-binaries.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BIN_SRC="$REPO_ROOT/prebuilt/bin"
BIN_DST="$REPO_ROOT/packages/python/src/airgap_devkit/bin"

for binary in \
    "devkit-server-linux-amd64" \
    "devkit-server-windows-amd64.exe"; do

    src="$BIN_SRC/$binary"
    if [[ ! -f "$src" ]]; then
        echo "MISSING: $src — run 'bash scripts/build-server.sh' first" >&2
        exit 1
    fi
    cp "$src" "$BIN_DST/$binary"
    echo "  staged: $binary"
done

echo ""
echo "Binaries staged. Build the wheel with:"
echo "  pip install build"
echo "  python -m build packages/python/ --outdir dist/python/"
