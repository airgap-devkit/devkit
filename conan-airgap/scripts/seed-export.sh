#!/usr/bin/env bash
# conan-airgap/scripts/seed-export.sh
# RUN ON A NETWORK-CONNECTED MACHINE.
#
# Fetches the requested Conan recipes + binary packages for every target profile
# and packs them — together with the kit's config (profiles, remotes, network
# overlays) — into a single portable bundle that can be carried to air-gapped
# hosts and consumed by import-airgap.sh.
#
# Usage:
#   bash seed-export.sh [--requirements FILE] [--profiles p1,p2,...]
#                       [--out DIR] [--build POLICY] [--name NAME]
#
#   --requirements FILE  List of refs to seed (default: requirements/baseline.txt)
#   --profiles LIST      Comma-separated profile names from config/profiles/
#                        (default: all profiles in config/profiles/)
#   --build POLICY       Passed to `conan install --build` (default: missing)
#   --out DIR            Where to write the bundle (default: ./dist)
#   --name NAME          Bundle base name (default: conan-airgap-bundle)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/conan-airgap.sh"
KIT_ROOT="$(ca_kit_root)"

REQUIREMENTS="${KIT_ROOT}/requirements/baseline.txt"
PROFILES=""
BUILD_POLICY="missing"
OUT_DIR="${KIT_ROOT}/dist"
NAME="conan-airgap-bundle"

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

ca_require_conan
[[ -f "$REQUIREMENTS" ]] || ca_die "requirements file not found: $REQUIREMENTS"

# Resolve the profile set.
if [[ -z "$PROFILES" ]]; then
    PROFILES="$(cd "${KIT_ROOT}/config/profiles" && ls | tr '\n' ',' | sed 's/,$//')"
fi
IFS=',' read -r -a PROFILE_ARR <<< "$PROFILES"

# Read requirement refs (skip comments/blanks).
mapfile -t REFS < <(grep -vE '^\s*(#|$)' "$REQUIREMENTS" | sed 's/[[:space:]]*$//')
[[ ${#REFS[@]} -gt 0 ]] || ca_die "no requirements listed in $REQUIREMENTS"

ca_log "Seeding ${#REFS[@]} requirement(s) across ${#PROFILE_ARR[@]} profile(s)"
echo "    Requirements : ${REFS[*]}"
echo "    Profiles     : ${PROFILE_ARR[*]}"
echo "    Build policy : ${BUILD_POLICY}"

# Make the kit's profiles available to this Conan home so -pr resolves them.
ca_log "Installing kit config into Conan home ($("$CONAN" config home))"
"$CONAN" config install "${KIT_ROOT}/config"

# Install every ref for every profile — this downloads recipes + binaries into
# the local cache. A binary that ConanCenter does not publish for a given
# profile is built from source when the host can (--build), else it is skipped
# with a warning so one gap does not abort the whole seed.
FAILED=()
for prof in "${PROFILE_ARR[@]}"; do
    prof_path="${KIT_ROOT}/config/profiles/${prof}"
    [[ -f "$prof_path" ]] || { ca_warn "profile not found, skipping: ${prof}"; continue; }
    for ref in "${REFS[@]}"; do
        echo ""
        ca_log "install ${ref}  [profile ${prof}]"
        if ! "$CONAN" install --requires="${ref}" \
                --build="${BUILD_POLICY}" \
                -pr:h="${prof_path}" -pr:b="${prof_path}"; then
            ca_warn "could not seed ${ref} for ${prof} (no prebuilt binary and/or cannot cross-build here)"
            FAILED+=("${ref}@${prof}")
        fi
    done
done

# Stage the bundle.
STAMP="$(ca_timestamp)"
BUNDLE_DIR="${OUT_DIR}/${NAME}-${STAMP}"
mkdir -p "${BUNDLE_DIR}"
ca_log "Staging bundle at ${BUNDLE_DIR}"

# 1. The whole seeded cache (recipes + binaries) as one archive.
CACHE_TGZ="${BUNDLE_DIR}/conan-cache.tgz"
ca_log "Archiving Conan cache (recipes + binaries)"
"$CONAN" cache save "*:*" --file "${CACHE_TGZ}"

# 2. The kit config + network overlays (so the target configures identically).
cp -r "${KIT_ROOT}/config"  "${BUNDLE_DIR}/config"
cp -r "${KIT_ROOT}/network" "${BUNDLE_DIR}/network"

# 3. A manifest describing the bundle for traceability + integrity.
CACHE_SHA="$(ca_sha256 "${CACHE_TGZ}")"
{
    echo "{"
    echo "  \"bundle\": \"${NAME}\","
    echo "  \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"conan_version\": \"${CONAN_VERSION}\","
    echo "  \"seed_host_os\": \"$(ca_os)\","
    echo "  \"cache_archive\": \"conan-cache.tgz\","
    echo "  \"cache_sha256\": \"${CACHE_SHA}\","
    echo "  \"profiles\": [$(printf '"%s",' "${PROFILE_ARR[@]}" | sed 's/,$//')],"
    echo "  \"requirements\": [$(printf '"%s",' "${REFS[@]}" | sed 's/,$//')],"
    echo "  \"seed_failures\": [$(printf '"%s",' "${FAILED[@]:-}" | sed 's/,$//; s/^""$//')]"
    echo "}"
} > "${BUNDLE_DIR}/manifest.json"

# 4. Tar the whole thing for transport.
TARBALL="${OUT_DIR}/${NAME}-${STAMP}.tar.gz"
ca_log "Creating transport tarball"
tar -czf "${TARBALL}" -C "${OUT_DIR}" "${NAME}-${STAMP}"
TAR_SHA="$(ca_sha256 "${TARBALL}")"
echo "${TAR_SHA}  $(basename "${TARBALL}")" > "${TARBALL}.sha256"

echo ""
ca_ok "Bundle ready:"
echo "    ${TARBALL}"
echo "    sha256: ${TAR_SHA}"
[[ ${#FAILED[@]} -gt 0 ]] && ca_warn "${#FAILED[@]} ref/profile combination(s) were not seeded (see manifest.json seed_failures)."
echo ""
echo "  Transfer ${TARBALL} (+ .sha256) to the air-gapped host, then:"
echo "    bash scripts/import-airgap.sh --bundle $(basename "${TARBALL}") --network offline"
