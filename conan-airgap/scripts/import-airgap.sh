#!/usr/bin/env bash
# conan-airgap/scripts/import-airgap.sh
# RUN ON AN AIR-GAPPED MACHINE.
#
# Consumes a bundle produced by seed-export.sh: applies the Conan config
# (profiles + global.conf), applies the chosen network overlay (remotes/proxy),
# restores the seeded packages into the local Conan cache, and verifies the host
# can resolve offline.
#
# Usage:
#   bash import-airgap.sh --bundle <PATH> [--network TYPE] [--home DIR] [--verify-ref REF]
#
#   --bundle PATH     Bundle .tar.gz OR an already-extracted bundle directory (required)
#   --network TYPE    Network overlay under network/: offline | internal-mirror | proxy
#                     (default: offline)
#   --home DIR        Use DIR as CONAN_HOME instead of the default ~/.conan2
#   --verify-ref REF  After restore, prove offline resolution of REF (optional)
#   --skip-verify     Do not run the post-restore checksum verification
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/conan-airgap.sh"

BUNDLE=""
NETWORK="offline"
CONAN_HOME_OVERRIDE=""
VERIFY_REF=""
SKIP_VERIFY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle)      BUNDLE="$2"; shift 2 ;;
        --network)     NETWORK="$2"; shift 2 ;;
        --home)        CONAN_HOME_OVERRIDE="$2"; shift 2 ;;
        --verify-ref)  VERIFY_REF="$2"; shift 2 ;;
        --skip-verify) SKIP_VERIFY=true; shift ;;
        -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)             ca_die "unknown argument: $1" ;;
    esac
done

[[ -n "$BUNDLE" ]] || ca_die "--bundle is required"
ca_require_conan

# Optionally isolate the cache (useful for testing or per-project homes).
if [[ -n "$CONAN_HOME_OVERRIDE" ]]; then
    mkdir -p "$CONAN_HOME_OVERRIDE"
    export CONAN_HOME="$CONAN_HOME_OVERRIDE"
    ca_ok "CONAN_HOME=${CONAN_HOME}"
fi

# Resolve the bundle to a directory (extract the tarball to a temp dir if needed).
CLEANUP_DIR=""
if [[ -d "$BUNDLE" ]]; then
    BUNDLE_DIR="$BUNDLE"
elif [[ -f "$BUNDLE" ]]; then
    # Integrity: verify the sidecar checksum if present.
    if [[ -f "${BUNDLE}.sha256" ]]; then
        ca_verify_sha256 "$BUNDLE" "$(awk '{print $1}' "${BUNDLE}.sha256")"
    fi
    CLEANUP_DIR="$(mktemp -d)"
    trap 'rm -rf "$CLEANUP_DIR"' EXIT
    ca_log "Extracting bundle"
    tar -xzf "$BUNDLE" -C "$CLEANUP_DIR"
    BUNDLE_DIR="$(find "$CLEANUP_DIR" -maxdepth 1 -mindepth 1 -type d | head -1)"
    [[ -n "$BUNDLE_DIR" ]] || ca_die "could not find bundle directory inside $BUNDLE"
else
    ca_die "bundle not found: $BUNDLE"
fi
ca_ok "Bundle: ${BUNDLE_DIR}"

[[ -f "${BUNDLE_DIR}/manifest.json" ]] && cat "${BUNDLE_DIR}/manifest.json"
CACHE_TGZ="${BUNDLE_DIR}/conan-cache.tgz"
[[ -f "$CACHE_TGZ" ]] || ca_die "cache archive missing: $CACHE_TGZ"

# Verify the cache archive against the manifest checksum before importing.
if [[ "$SKIP_VERIFY" != "true" && -f "${BUNDLE_DIR}/manifest.json" ]]; then
    EXPECTED="$(grep -oE '"cache_sha256"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]+"' "${BUNDLE_DIR}/manifest.json" \
        | grep -oE '[0-9a-fA-F]{64}' | head -1 || true)"
    ca_verify_sha256 "$CACHE_TGZ" "$EXPECTED"
fi

# 1. Base config (profiles + global.conf + default empty remotes).
ca_log "Applying base config"
"$CONAN" config install "${BUNDLE_DIR}/config"

# 2. Network overlay (remotes / proxy) for this environment.
OVERLAY="${BUNDLE_DIR}/network/${NETWORK}"
[[ -d "$OVERLAY" ]] || ca_die "unknown network type '${NETWORK}'. Available: $(cd "${BUNDLE_DIR}/network" && ls | tr '\n' ' ')"
ca_log "Applying network overlay: ${NETWORK}"
"$CONAN" config install "$OVERLAY"

# 3. Restore the seeded packages into the local cache.
ca_log "Restoring Conan cache (recipes + binaries)"
"$CONAN" cache restore "$CACHE_TGZ"

# 4. Report + verify.
ca_log "Packages now available in the cache:"
"$CONAN" list "*:*" 2>/dev/null || "$CONAN" list "*" 2>/dev/null || true

if [[ -n "$VERIFY_REF" ]]; then
    ca_log "Verifying offline resolution of ${VERIFY_REF}"
    # A given host only needs a binary for its own platform, so try each seeded
    # profile and succeed as soon as one resolves entirely from the cache.
    resolved=""
    for PROF in $(cd "${BUNDLE_DIR}/config/profiles" && ls); do
        if "$CONAN" install --requires="$VERIFY_REF" --build=never \
                -pr:h="${BUNDLE_DIR}/config/profiles/${PROF}" \
                -pr:b="${BUNDLE_DIR}/config/profiles/${PROF}" >/dev/null 2>&1; then
            resolved="$PROF"; break
        fi
    done
    if [[ -n "$resolved" ]]; then
        ca_ok "${VERIFY_REF} resolved from cache with no network (profile: ${resolved})."
    else
        ca_warn "${VERIFY_REF} did not resolve for any seeded profile — it may not have been seeded, or not for this platform."
    fi
fi

echo ""
ca_ok "Import complete. Conan is configured for '${NETWORK}' and the cache is populated."
echo "    Conan home : $("$CONAN" config home)"
echo "    Profiles   : run 'conan profile list' to see them."
