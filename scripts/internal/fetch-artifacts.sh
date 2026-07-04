#!/usr/bin/env bash
# scripts/internal/fetch-artifacts.sh
# ─────────────────────────────────────────────────────────────────────────────
# Option B fetcher: resolve prebuilt binary artifacts from a CONFIGURABLE source
# and verify them against the checksums recorded in each prebuilt manifest.json.
#
# The binaries themselves live outside git (published as release artifacts /
# mirrored into a customer's own store); only the manifests live in the repo.
# This script rehydrates the binaries into a local artifact root that the normal
# setup.sh scripts consume via PREBUILT_DIR.
#
# The source is deliberately host-agnostic — it is just "a base + a relative
# path". That is what makes this work on any customer's Bitbucket Server, a
# Nexus/Artifactory, an internal file share, or a plain HTTP mirror, with no
# dependency on GitHub-specific "releases" APIs:
#
#   DEVKIT_ARTIFACT_BASE examples
#     https://github.com/<org>/<repo>/releases/download/v1.3.5   (public default)
#     https://bitbucket.internal/rest/.../repos/prebuilt/raw     (customer Bitbucket)
#     https://nexus.internal/repository/airgap-prebuilt          (Nexus/Artifactory)
#     /mnt/share/airgap-devkit/prebuilt                          (file share / USB)
#     file:///media/usb/prebuilt                                 (transferred media)
#
# For a fully air-gapped host with no reachable mirror, do not run this — use the
# offline bundle from build-bundle.sh instead. This script is for the connected
# staging machine or a semi-connected enclave with an internal mirror.
#
# Usage:
#   DEVKIT_ARTIFACT_BASE=<base> \
#     bash scripts/internal/fetch-artifacts.sh [--platform windows|linux|all]
#                                              [--dest <dir>]
#                                              [--manifests <dir>]
#
#   --platform   Which platform's artifacts to fetch (default: all).
#   --dest       Where to write artifacts (default: ./prebuilt — in place).
#   --manifests  Root of manifest.json files (default: ./prebuilt).
#
# Exit 0 = every selected artifact fetched and checksum-verified.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"

PLATFORM="all"
DEST="$REPO_ROOT/prebuilt"
MANIFESTS="$REPO_ROOT/prebuilt"
BASE="${DEVKIT_ARTIFACT_BASE:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)  PLATFORM="$2"; shift 2 ;;
        --dest)      DEST="$2"; shift 2 ;;
        --manifests) MANIFESTS="$2"; shift 2 ;;
        --base)      BASE="$2"; shift 2 ;;
        -h|--help)   sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           fail "Unknown argument: $1" ;;
    esac
done

[[ -z "$BASE" ]] && fail "No artifact source. Set DEVKIT_ARTIFACT_BASE or pass --base <url|path>."
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

case "$PLATFORM" in
    windows|linux|all) ;;
    *) fail "Invalid --platform: $PLATFORM (expected windows|linux|all)" ;;
esac

log "Artifact source : $BASE"
log "Platform        : $PLATFORM"
log "Destination     : $DEST"

# Enumerate the files a manifest requires for the selected platform, one per line
# as "<filename>\t<sha256>" (shared with build-bundle.sh). Strip CR so Windows
# python's CRLF output does not corrupt the checksum field.
enumerate_manifest() {
    python3 "$SCRIPT_DIR/lib/enumerate-artifacts.py" "$1" "$2" | tr -d '\r'
}

# Fetch a single file from BASE/<relpath> and verify its sha256.
fetch_one() {
    local relpath="$1" expected="$2"
    local out="$DEST/$relpath"
    mkdir -p "$(dirname "$out")"

    if [[ -f "$out" ]]; then
        local have; have=$(sha256 "$out")
        if [[ "${have,,}" == "${expected,,}" ]]; then
            ok "cached: $relpath"
            return 0
        fi
        warn "checksum drift on cached $relpath — refetching"
        rm -f "$out"
    fi

    local src="$BASE/$relpath"
    echo "    fetch: $relpath"
    case "$BASE" in
        http://*|https://*)
            curl -fL --retry 3 --progress-bar -o "$out" "$src" \
                || fail "download failed: $src"
            ;;
        file://*)
            cp -f "${src#file://}" "$out" || fail "copy failed: ${src#file://}"
            ;;
        *)  # local directory / mounted share / UNC path
            cp -f "$src" "$out" || fail "copy failed: $src"
            ;;
    esac

    local actual; actual=$(sha256 "$out")
    [[ "${actual,,}" == "${expected,,}" ]] \
        || fail "checksum mismatch: $relpath\n       expected $expected\n       actual   $actual"
    ok "verified: $relpath"
}

total=0 fetched=0
while IFS= read -r manifest; do
    reldir="$(dirname "${manifest#$MANIFESTS/}")"
    while IFS=$'\t' read -r name sha; do
        [[ -z "$name" ]] && continue
        total=$((total + 1))
        fetch_one "$reldir/$name" "$sha"
        fetched=$((fetched + 1))
    done < <(enumerate_manifest "$manifest" "$PLATFORM")
done < <(find "$MANIFESTS" -name manifest.json -type f | sort)

echo ""
echo "============================================================"
echo " Fetched/verified $fetched of $total selected artifact(s)."
echo " Artifact root: $DEST"
echo " Install offline with:  PREBUILT_DIR=$DEST bash scripts/internal/install-cli.sh --yes --profile cpp-dev"
echo "============================================================"
