#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/internal/import-grpc-prebuilt.sh
#
# Import the prebuilt gRPC release packages into airgap-devkit's
# `prebuilt/` submodule, split into commit-friendly parts with a checksum
# manifest. This is the documented sync mechanism: the maintainer build is the
# source; airgap-devkit ships a frozen, checksummed copy so it stays
# independently releasable.
#
# It stages the RELEASE packages for every MSVC toolset (v142/v143/v145). The
# Debug packages are intentionally NOT shipped in the product (too large).
#
# USAGE:
#   bash scripts/internal/import-grpc-prebuilt.sh \
#       --from "$HOME/grpc-prebuilt/dist" \
#       [--version 1.81.1] [--toolsets 142,143,145] [--part-size 45m] [--prune-old]
#
# Requires: bash, split, sha256sum, python3 (all already devkit dependencies).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=scripts/internal/lib/devkit-prebuilt.sh
source "${SCRIPT_DIR}/lib/devkit-prebuilt.sh"

# ---------------------------------------------------------------------------
# Defaults / args
# ---------------------------------------------------------------------------
FROM_DIR="${GRPC_DIST_DIR:-$HOME/grpc-prebuilt/dist}"
VERSION="1.81.1"
TOOLSETS="142,143,145"
PART_SIZE="45m"
PRUNE_OLD=false

# VS-version labels per toolset (keep in sync with
# tools/frameworks/grpc/Check-Environment.ps1 and devkit.json variants).
_vs_version() {
    case "$1" in
        141) echo "Visual Studio 2017" ;;
        142) echo "Visual Studio 2019" ;;
        143) echo "Visual Studio 2022" ;;
        145) echo "Visual Studio 2026" ;;
        *)   echo "MSVC v$1" ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)      FROM_DIR="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --toolsets)  TOOLSETS="$2"; shift 2 ;;
        --part-size) PART_SIZE="$2"; shift 2 ;;
        --prune-old) PRUNE_OLD=true; shift ;;
        -h|--help)
            sed -n '2,30p' "$0"; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

DEST_DIR="${REPO_ROOT}/prebuilt/frameworks/grpc/windows/${VERSION}"

[[ -d "${FROM_DIR}" ]] || fail "Source dist dir not found: ${FROM_DIR}"
command -v sha256sum >/dev/null || fail "sha256sum is required"
command -v python3   >/dev/null || fail "python3 is required"

log "Importing gRPC ${VERSION} release packages"
echo "    Source : ${FROM_DIR}"
echo "    Dest   : ${DEST_DIR}"
echo "    Tools  : ${TOOLSETS}   (part size ${PART_SIZE})"

# ---------------------------------------------------------------------------
# Prune old version dirs (optional)
# ---------------------------------------------------------------------------
if [[ "${PRUNE_OLD}" == true ]]; then
    WIN_DIR="${REPO_ROOT}/prebuilt/frameworks/grpc/windows"
    for d in "${WIN_DIR}"/*/; do
        base="$(basename "${d%/}")"
        [[ "${base}" == "${VERSION}" ]] && continue
        [[ "${base}" == "README.md" ]] && continue
        if [[ -d "${d}" ]]; then
            warn "Pruning old prebuilt dir: ${d}"
            rm -rf "${d}"
        fi
    done
fi

mkdir -p "${DEST_DIR}"

# ---------------------------------------------------------------------------
# Split each release package into parts + record checksums
# ---------------------------------------------------------------------------
# Emits, per toolset, a line: "<toolset>|<archive>|<full_sha256>" so the manifest
# builder can pair the parts (scanned from disk) with metadata.
META_FILE="$(mktemp)"
trap 'rm -f "${META_FILE}"' EXIT

IFS=',' read -r -a TS_ARR <<< "${TOOLSETS}"
for ts in "${TS_ARR[@]}"; do
    ts="$(echo "$ts" | tr -d '[:space:]')"
    archive="grpc-${VERSION}-msvc${ts}-x64-release.zip"
    src="${FROM_DIR}/${archive}"
    [[ -f "${src}" ]] || fail "Missing source package: ${src}"

    log "toolset v${ts}  ($(_vs_version "${ts}"))  ->  ${archive}"
    full_sha="$(sha256 "${src}")"
    echo "    full sha256: ${full_sha}"

    # Remove any stale parts/whole archive for this toolset, then split fresh.
    rm -f "${DEST_DIR}/${archive}" "${DEST_DIR}/${archive}".part-*
    echo "    Splitting into ${PART_SIZE} parts (source left intact)..."
    split -b "${PART_SIZE}" --suffix-length=2 "${src}" "${DEST_DIR}/${archive}.part-"
    n_parts="$(ls "${DEST_DIR}/${archive}".part-* | wc -l | tr -d '[:space:]')"
    ok "${n_parts} part(s) written for ${archive}"

    echo "${ts}|${archive}|${full_sha}" >> "${META_FILE}"
done

# ---------------------------------------------------------------------------
# Build manifest.json (multi-variant: one platform key per toolset)
# ---------------------------------------------------------------------------
log "Writing manifest.json"
python3 - "${DEST_DIR}" "${VERSION}" "${META_FILE}" <<'PY'
import hashlib, json, os, sys

dest_dir, version, meta_file = sys.argv[1], sys.argv[2], sys.argv[3]

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

VS = {"141": "Visual Studio 2017", "142": "Visual Studio 2019",
      "143": "Visual Studio 2022", "145": "Visual Studio 2026"}

rows = []
with open(meta_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        ts, archive, full = line.split("|")
        rows.append((ts, archive, full))

platforms, variants = {}, []
# Default toolset preference order: v143 (VS2022, mainstream) first.
order = {"143": 0, "145": 1, "142": 2, "141": 3}
rows.sort(key=lambda r: order.get(r[0], 9))

for i, (ts, archive, full) in enumerate(rows):
    parts = sorted(p for p in os.listdir(dest_dir)
                   if p.startswith(archive + ".part-"))
    part_sha = {p: sha256(os.path.join(dest_dir, p)) for p in parts}
    platforms[f"windows-msvc{ts}"] = {
        "archive": archive,
        "toolset": f"v{ts}",
        "vs_version": VS.get(ts, f"MSVC v{ts}"),
        "sha256": full,
        "part_sha256": part_sha,
        "reassemble": f"cat {archive}.part-* > {archive} && unzip -o {archive}",
    }
    variants.append({
        "id": f"v{ts}",
        "toolset": f"v{ts}",
        "vs_version": VS.get(ts, f"MSVC v{ts}"),
        "archive": archive,
        "default": i == 0,
    })

manifest = {
    "tool": "grpc",
    "version": version,
    "source": f"https://github.com/grpc/grpc/releases/tag/v{version}",
    "provenance": "grpc (maintainer prebuilt, release configuration)",
    "platforms": platforms,
    "compression": "zip",
    "part_size_mb": 45,
    "variants": variants,
}

with open(os.path.join(dest_dir, "manifest.json"), "w") as mf:
    json.dump(manifest, mf, indent=2)
    mf.write("\n")

print(f"  OK  manifest.json  ({len(platforms)} toolset variant(s))")
PY

ok "gRPC ${VERSION} imported into ${DEST_DIR}"
echo ""
echo "    Next: review the parts + manifest, then commit inside the prebuilt"
echo "    submodule and bump its pointer in the main repo."
