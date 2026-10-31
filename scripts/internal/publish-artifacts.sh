#!/usr/bin/env bash
# scripts/internal/publish-artifacts.sh
# ─────────────────────────────────────────────────────────────────────────────
# Publish prebuilt binary artifacts to a distribution point so they can live
# OUTSIDE git (Option B). Emits a mirror tree whose layout matches prebuilt/, so
# a consumer sets DEVKIT_ARTIFACT_BASE to the published root and fetch-artifacts.sh
# rehydrates from it. The mirror is just files under relative paths — host it on
# GitHub Releases, a Bitbucket repo's raw path, Nexus/Artifactory, or a file share.
#
# Modes (combine as needed):
#   --dest <dir>     Copy the artifact tree into <dir> (a local staging area, a
#                    mounted share, or a checkout you push to Bitbucket).
#   --gh <tag>       Upload every artifact to GitHub release <tag> via `gh`
#                    (flat asset names; use for the public default base).
#   --bundles        Also build offline bundles (build-bundle.sh) for both
#                    platforms into dist/bundles/.
#
# Usage:
#   bash scripts/internal/publish-artifacts.sh --dest /mnt/mirror/prebuilt
#   bash scripts/internal/publish-artifacts.sh --gh v1.3.5 --bundles
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"

PREBUILT="$REPO_ROOT/prebuilt"
DEST=""
GH_TAG=""
DO_BUNDLES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)    PREBUILT="$2"; shift 2 ;;   # artifact root to publish (default: prebuilt)
        --dest)    DEST="$2"; shift 2 ;;
        --gh)      GH_TAG="$2"; shift 2 ;;
        --bundles) DO_BUNDLES=true; shift ;;
        -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         fail "Unknown argument: $1" ;;
    esac
done

[[ -z "$DEST" && -z "$GH_TAG" && "$DO_BUNDLES" == false ]] \
    && fail "Nothing to do — pass --dest, --gh, and/or --bundles."

# Every artifact file = manifest sibling files (whole archives + parts), for all
# platforms. Manifest files themselves stay in git, so they are not republished.
artifact_files() {
    while IFS= read -r manifest; do
        reldir="$(dirname "${manifest#$PREBUILT/}")"
        while IFS=$'\t' read -r name _sha; do
            [[ -z "$name" ]] && continue
            [[ -f "$PREBUILT/$reldir/$name" ]] && echo "$reldir/$name"
        done < <(python3 "$SCRIPT_DIR/lib/enumerate-artifacts.py" "$manifest" all | tr -d '\r')
    done < <(find "$PREBUILT" -name manifest.json -type f | sort)
}

if [[ -n "$DEST" ]]; then
    log "Exporting artifact mirror → $DEST"
    count=0
    while IFS= read -r rel; do
        mkdir -p "$DEST/$(dirname "$rel")"
        cp -f "$PREBUILT/$rel" "$DEST/$rel"
        count=$((count + 1))
    done < <(artifact_files)
    ok "Mirrored $count artifact file(s). Point DEVKIT_ARTIFACT_BASE at: $DEST"
fi

if [[ -n "$GH_TAG" ]]; then
    command -v gh >/dev/null 2>&1 || fail "gh CLI required for --gh"
    log "Uploading artifacts to GitHub release $GH_TAG (resumable, retried)"
    # Assets already present (by flat name) are skipped so re-runs resume.
    existing="$(gh release view "$GH_TAG" --json assets -q '.assets[].name' 2>/dev/null || true)"
    up=0 skip=0
    while IFS= read -r rel; do
        base="$(basename "$rel")"
        if grep -qxF "$base" <<<"$existing"; then
            skip=$((skip + 1)); continue
        fi
        ok_up=0
        for attempt in 1 2 3; do
            echo "    upload ($attempt): $rel"
            if gh release upload "$GH_TAG" "$PREBUILT/$rel" --clobber; then ok_up=1; break; fi
            echo "    retry in 3s..."; sleep 3
        done
        [[ "$ok_up" == 1 ]] || fail "upload failed after 3 attempts: $rel"
        up=$((up + 1))
    done < <(artifact_files)
    ok "Uploaded $up artifact(s), skipped $skip already-present, to $GH_TAG"
fi

if [[ "$DO_BUNDLES" == true ]]; then
    log "Building offline bundles (windows + linux)"
    bash "$SCRIPT_DIR/build-bundle.sh" --platform windows
    bash "$SCRIPT_DIR/build-bundle.sh" --platform linux
fi

echo ""
echo "Done."
