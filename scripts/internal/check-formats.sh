#!/usr/bin/env bash
# scripts/internal/check-formats.sh
# Guard: prebuilt archives must be in the OS-native, no-admin-extractable format
# only — .zip (Windows) or .tar.gz (Linux). Proprietary/xz formats (.7z, .tar.xz,
# .xz) require extra unpackers and are rejected.
#
# Exit 0 = clean. Exit 1 = offending files found (prints them).
# Run locally or in CI: bash scripts/internal/check-formats.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Directories that legitimately hold staged binary archives.
SCAN_DIRS=("$REPO_ROOT/prebuilt")

# Split parts inherit their base extension (e.g. foo.tar.xz.part-aa), so match
# the format substring anywhere in the name, not just the final extension.
BANNED_RE='\.(7z|tar\.xz|xz)(\.part-[a-z]+)?$'

found=0
for dir in "${SCAN_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        echo "  [BANNED FORMAT] ${f#$REPO_ROOT/}"
        found=1
    done < <(find "$dir" -type f -regextype posix-extended -regex ".*${BANNED_RE}" 2>/dev/null)
done

if [[ "$found" -ne 0 ]]; then
    echo "" >&2
    echo "ERROR: prebuilt archives must be .zip (Windows) or .tar.gz (Linux)." >&2
    echo "       Re-stage the offending tools with the download/apply scripts," >&2
    echo "       which now repack into the native format." >&2
    exit 1
fi

echo "[OK] All prebuilt archives use native formats (.zip / .tar.gz)."
