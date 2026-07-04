#!/usr/bin/env bash
# conan-airgap/scripts/update-export.sh
# RUN ON A NETWORK-CONNECTED MACHINE.
#
# Produces an incremental *delta* bundle containing only newly-requested refs
# (and their dependencies) — for pushing updates/new libraries/plugins to
# air-gapped hosts without re-shipping the entire cache. It fetches the delta in
# an isolated temporary Conan home so the archive contains exactly the new
# packages. Consume it with import-airgap.sh exactly like a full bundle;
# `conan cache restore` is additive.
#
# Usage:
#   bash update-export.sh --requirements FILE [--profiles LIST] [--build POLICY]
#                         [--out DIR] [--name NAME]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/conan-airgap.sh"
KIT_ROOT="$(ca_kit_root)"

REQUIREMENTS=""
PROFILES=""
BUILD_POLICY="missing"
OUT_DIR="${KIT_ROOT}/dist"
NAME="conan-airgap-update"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --requirements) REQUIREMENTS="$2"; shift 2 ;;
        --profiles)     PROFILES="$2"; shift 2 ;;
        --build)        BUILD_POLICY="$2"; shift 2 ;;
        --out)          OUT_DIR="$2"; shift 2 ;;
        --name)         NAME="$2"; shift 2 ;;
        -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)              ca_die "unknown argument: $1" ;;
    esac
done

[[ -n "$REQUIREMENTS" && -f "$REQUIREMENTS" ]] || ca_die "--requirements FILE is required (the new/updated refs)"
ca_require_conan

if [[ -z "$PROFILES" ]]; then
    PROFILES="$(cd "${KIT_ROOT}/config/profiles" && ls | tr '\n' ',' | sed 's/,$//')"
fi
IFS=',' read -r -a PROFILE_ARR <<< "$PROFILES"
mapfile -t REFS < <(grep -vE '^\s*(#|$)' "$REQUIREMENTS" | sed 's/[[:space:]]*$//')
[[ ${#REFS[@]} -gt 0 ]] || ca_die "no requirements listed in $REQUIREMENTS"

# Isolate the delta: fetch into a throwaway Conan home so `cache save` captures
# only these refs and their dependencies — not the whole workstation cache.
DELTA_HOME="$(mktemp -d)"
trap 'rm -rf "$DELTA_HOME"' EXIT
export CONAN_HOME="$DELTA_HOME"
ca_ok "Isolated delta cache: ${CONAN_HOME}"

ca_log "Installing kit config into delta home"
"$CONAN" config install "${KIT_ROOT}/config"

FAILED=()
for prof in "${PROFILE_ARR[@]}"; do
    prof_path="${KIT_ROOT}/config/profiles/${prof}"
    [[ -f "$prof_path" ]] || { ca_warn "profile not found, skipping: ${prof}"; continue; }
    for ref in "${REFS[@]}"; do
        echo ""
        ca_log "delta install ${ref}  [profile ${prof}]"
        "$CONAN" install --requires="${ref}" --build="${BUILD_POLICY}" \
            -pr:h="${prof_path}" -pr:b="${prof_path}" \
            || { ca_warn "could not seed ${ref} for ${prof}"; FAILED+=("${ref}@${prof}"); }
    done
done

STAMP="$(ca_timestamp)"
BUNDLE_DIR="${OUT_DIR}/${NAME}-${STAMP}"
mkdir -p "${BUNDLE_DIR}"

CACHE_TGZ="${BUNDLE_DIR}/conan-cache.tgz"
ca_log "Archiving delta cache"
"$CONAN" cache save "*:*" --file "${CACHE_TGZ}"

# Ship config + overlays too so an update can also carry changed profiles/remotes.
cp -r "${KIT_ROOT}/config"  "${BUNDLE_DIR}/config"
cp -r "${KIT_ROOT}/network" "${BUNDLE_DIR}/network"

CACHE_SHA="$(ca_sha256 "${CACHE_TGZ}")"
{
    echo "{"
    echo "  \"bundle\": \"${NAME}\","
    echo "  \"kind\": \"update\","
    echo "  \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"conan_version\": \"${CONAN_VERSION}\","
    echo "  \"cache_archive\": \"conan-cache.tgz\","
    echo "  \"cache_sha256\": \"${CACHE_SHA}\","
    echo "  \"profiles\": [$(printf '"%s",' "${PROFILE_ARR[@]}" | sed 's/,$//')],"
    echo "  \"requirements\": [$(printf '"%s",' "${REFS[@]}" | sed 's/,$//')]"
    echo "}"
} > "${BUNDLE_DIR}/manifest.json"

TARBALL="${OUT_DIR}/${NAME}-${STAMP}.tar.gz"
ca_log "Creating transport tarball"
tar -czf "${TARBALL}" -C "${OUT_DIR}" "${NAME}-${STAMP}"
echo "$(ca_sha256 "${TARBALL}")  $(basename "${TARBALL}")" > "${TARBALL}.sha256"

echo ""
ca_ok "Update bundle ready: ${TARBALL}"
[[ ${#FAILED[@]} -gt 0 ]] && ca_warn "${#FAILED[@]} ref/profile combo(s) not seeded."
echo "  On the air-gapped host (adds to the existing cache):"
echo "    bash scripts/import-airgap.sh --bundle $(basename "${TARBALL}") --network offline"
