#!/usr/bin/env bash
# scripts/internal/lib/devkit-prebuilt.sh
# Shared helpers for airgap-devkit prebuilt management scripts.
# Source this file; do not execute directly.
# Compatible with: Git Bash (MINGW64) on Windows, Bash 4.x on RHEL 8 / Linux.

[[ -n "${_DEVKIT_PREBUILT_SH:-}" ]] && return 0
_DEVKIT_PREBUILT_SH=1

log()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    [OK] %s\n' "$*"; }
warn() { printf '    [WARN] %s\n' "$*" >&2; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# Download with curl; skip if already present.
dl() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        ok "Already present: $(basename "$dest")"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    echo "    Downloading $(basename "$dest")..."
    curl -fL --progress-bar -o "$dest" "$url" \
        || fail "Download failed: $url"
}

# Compute SHA256 of a file.
sha256() { sha256sum "$1" | awk '{print $1}'; }

# Repack a zip or tar.gz as tar.xz, stripping the top-level wrapper directory.
# Used for archives where contents are nested under e.g. cmake-4.3.2-windows-x86_64/.
repack_xz_strip1() {
    local src="$1" dest="$2"
    local tmp; tmp="$(mktemp -d -p "${TMP_DIR:-/tmp}")"
    echo "    Extracting $(basename "$src")..."
    case "$src" in
        *.zip)           unzip -q "$src" -d "$tmp/raw" ;;
        *.tar.gz|*.tgz)  mkdir -p "$tmp/raw"; tar -xzf "$src" -C "$tmp/raw" ;;
        *)               fail "repack_xz_strip1: unsupported format: $src" ;;
    esac
    local topdir; topdir="$(ls "$tmp/raw" | head -1)"
    echo "    Repackaging → $(basename "$dest") (xz, no wrapper)..."
    tar -cJf "$dest" -C "$tmp/raw/$topdir" .
    rm -rf "$tmp"
}

# Repack a zip or tar.gz as tar.xz WITHOUT stripping (contents already at root).
repack_xz_flat() {
    local src="$1" dest="$2"
    local tmp; tmp="$(mktemp -d -p "${TMP_DIR:-/tmp}")"
    echo "    Extracting $(basename "$src")..."
    case "$src" in
        *.zip)           unzip -q "$src" -d "$tmp/raw" ;;
        *.tar.gz|*.tgz)  mkdir -p "$tmp/raw"; tar -xzf "$src" -C "$tmp/raw" ;;
        *)               fail "repack_xz_flat: unsupported format: $src" ;;
    esac
    echo "    Repackaging → $(basename "$dest") (xz, flat)..."
    tar -cJf "$dest" -C "$tmp/raw" .
    rm -rf "$tmp"
}

# Split a file into parts and delete the source.
# Uses alphabetic suffixes (part-aa, part-ab, ...) matching the existing prebuilt convention.
# Never use -d (numeric suffixes) — it breaks cat *.part-* glob ordering.
split_parts() {
    local src="$1" dir="$2" basename="$3"
    local part_size="${PART_SIZE:-50m}"
    echo "    Splitting into ${part_size} parts..."
    split -b "$part_size" --suffix-length=2 "$src" "$dir/${basename}.part-"
    rm -f "$src"
    ok "Parts written: $dir/${basename}.part-*"
}

# Extract a single string field from a JSON file using python3.
# Returns empty string if the key is absent or its value is null.
json_field() {
    local file="$1" key="$2"
    python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    v = d.get(sys.argv[2])
    print('' if v is None else str(v))
except Exception:
    print('')
" "$file" "$key"
}
