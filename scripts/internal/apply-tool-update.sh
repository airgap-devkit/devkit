#!/usr/bin/env bash
# scripts/internal/apply-tool-update.sh
# Downloads, stages, and applies a version update for a single airgap-devkit tool.
#
# Usage:
#   bash scripts/internal/apply-tool-update.sh <tool-id> <new-version> [--dry-run] [--all-platforms]
#
# Examples:
#   bash scripts/internal/apply-tool-update.sh cmake 4.4.0
#   bash scripts/internal/apply-tool-update.sh ninja 1.13.3 --all-platforms
#   bash scripts/internal/apply-tool-update.sh llvm 22.1.5 --dry-run
#
# What it does:
#   1. Confirms the release tag exists on GitHub
#   2. Resolves the asset download URL using asset_match / asset_match_linux
#   3. Downloads to a temp directory
#   4. Repacks archives (zip/tar.gz → tar.xz) where needed
#   5. Splits files >50MB into alphabetic part- files (matching prebuilt convention)
#   6. Writes prebuilt/<category>/<tool>/<version>/manifest.json
#   7. Updates tools/<category>/<tool>/devkit.json "version" field
#   8. Updates tools/<category>/<tool>/setup.sh VERSION= line
#   9. Syntax-checks setup.sh
#  10. Prints a next-steps summary
#
# Environment:
#   GITHUB_TOKEN    Optional. Authenticates GitHub API calls.
#   PART_SIZE       Override split size (default: 50m)
#   DRY_RUN=1       Report what would happen; skip downloads and file writes.
#   ALL_PLATFORMS=1 Stage assets for both Windows and Linux (default: current OS only).
#
# Supported special cases:
#   VS Code  — uses download_url_template_windows / download_url_template_linux
#   LLVM     — uses tag_prefix "llvmorg-" so tag becomes "llvmorg-22.1.5"
#   GCC      — Linux RPMs are manual; Windows uses brechtsanders/winlibs_mingw
#   osslsigncode — no "v" tag prefix (tag = version)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_DIR=$(mktemp -d)

source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"

trap 'rm -rf "$TMP_DIR"' EXIT

# ── Argument parsing ──────────────────────────────────────────────────────────
TOOL_ID="${1:-}"
NEW_VERSION="${2:-}"
DRY_RUN="${DRY_RUN:-}"
ALL_PLATFORMS="${ALL_PLATFORMS:-}"
TAG_OVERRIDE=""  # --tag <tag>: override the release tag (for tools like GCC/WinLibs)

shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)       DRY_RUN=1 ;;
        --all-platforms) ALL_PLATFORMS=1 ;;
        --tag)           TAG_OVERRIDE="${2:-}"; shift ;;
        -h|--help)
            sed -n '2,/^# Environment:/p' "${BASH_SOURCE[0]}" | grep '^#' | sed 's/^# //'
            exit 0 ;;
    esac
    shift
done

[[ -z "$TOOL_ID" || -z "$NEW_VERSION" ]] && {
    echo "Usage: bash apply-tool-update.sh <tool-id> <new-version> [--dry-run] [--all-platforms]" >&2
    exit 1
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v curl    >/dev/null 2>&1 || fail "curl is required"

# ── Network preflight ─────────────────────────────────────────────────────────
if [[ -z "${DRY_RUN:-}" ]]; then
    curl -sf --max-time 5 -o /dev/null "https://api.github.com" 2>/dev/null || \
        fail "Cannot reach api.github.com — internet access is required.\n       Run this script on an internet-connected machine, then commit prebuilt/ to the repo."
fi

[[ -n "${DRY_RUN:-}" ]] && log "DRY RUN — no files will be downloaded or modified"

# ── Locate devkit.json ────────────────────────────────────────────────────────
DEVKIT_JSON="" CATEGORY="" TOOL_DIR=""

for f in "$REPO_ROOT"/tools/*/devkit.json \
         "$REPO_ROOT"/tools/*/*/devkit.json; do
    [[ -f "$f" ]] || continue
    fid=$(json_field "$f" "id")
    if [[ "$fid" == "$TOOL_ID" ]]; then
        DEVKIT_JSON="$f"
        # Extract category from path: tools/<category>/<tool>/devkit.json
        # or                          tools/<category>/devkit.json (nested)
        rel="${f#$REPO_ROOT/tools/}"           # e.g. build-tools/cmake/devkit.json
        CATEGORY="${rel%%/*}"                   # build-tools
        TOOL_DIR="$(dirname "$f")"
        break
    fi
done

[[ -z "$DEVKIT_JSON" ]] && fail "Tool '$TOOL_ID' not found in tools/*/devkit.json"

# ── Read tool metadata ────────────────────────────────────────────────────────
TOOL_NAME=$(json_field     "$DEVKIT_JSON" "name")
CURRENT_VER=$(json_field   "$DEVKIT_JSON" "version")
GITHUB_REPO=$(json_field   "$DEVKIT_JSON" "github_repo")
# tag_prefix: distinguish absent (default "v") from explicitly "" (no prefix, e.g. Conan, 7zip)
TAG_PREFIX=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(d['tag_prefix'] if 'tag_prefix' in d else '__ABSENT__')
" "$DEVKIT_JSON")
ASSET_MATCH=$(json_field   "$DEVKIT_JSON" "asset_match")
ASSET_MATCH_LIN=$(json_field "$DEVKIT_JSON" "asset_match_linux")
DL_TPL_WIN=$(json_field    "$DEVKIT_JSON" "download_url_template_windows")
DL_TPL_LIN=$(json_field    "$DEVKIT_JSON" "download_url_template_linux")
PLATFORM=$(json_field      "$DEVKIT_JSON" "platform")
PLATFORM_NOTE=$(json_field "$DEVKIT_JSON" "platform_note")

log "Tool         : $TOOL_NAME ($TOOL_ID)"
log "Version      : $CURRENT_VER → $NEW_VERSION"
log "Category     : $CATEGORY"
log "devkit.json  : $DEVKIT_JSON"

[[ -z "$GITHUB_REPO" && -z "$DL_TPL_WIN" && -z "$DL_TPL_LIN" ]] && \
    fail "Tool '$TOOL_ID' has no github_repo or download_url_template — cannot auto-update"

# ── Detect current OS ─────────────────────────────────────────────────────────
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) CURRENT_OS="windows" ;;
    *)                    CURRENT_OS="linux" ;;
esac

log "Current OS   : $CURRENT_OS"
[[ -n "$ALL_PLATFORMS" ]] && log "Staging both Windows + Linux assets (ALL_PLATFORMS=1)"

# ── Build the expected GitHub tag ────────────────────────────────────────────
# If tag_prefix key was absent use "v" as default; if present (even "") use as-is
[[ "$TAG_PREFIX" == "__ABSENT__" ]] && EFFECTIVE_PREFIX="v" || EFFECTIVE_PREFIX="$TAG_PREFIX"
EXPECTED_TAG="${TAG_OVERRIDE:-${EFFECTIVE_PREFIX}${NEW_VERSION}}"

log "GitHub repo  : ${GITHUB_REPO:-N/A}"
log "Release tag  : $EXPECTED_TAG"

# ── Confirm release exists on GitHub ─────────────────────────────────────────
if [[ -n "$GITHUB_REPO" ]]; then
    release_json=$(curl -sf --max-time 15 \
        -H "Accept: application/vnd.github.v3+json" \
        -H "User-Agent: airgap-devkit/1.0" \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${EXPECTED_TAG}") || \
        fail "Release tag '${EXPECTED_TAG}' not found on ${GITHUB_REPO} (or GitHub API unreachable)"

    ok "Release '${EXPECTED_TAG}' confirmed on GitHub"
else
    release_json=""
fi

# ── Resolve asset download URLs ───────────────────────────────────────────────

# resolve_asset_url <match_str> [exclude_str] → prints URL or fails
# Reads release JSON from $release_json (global), uses stdin-pipe to avoid arg-length limits.
resolve_asset_url() {
    local match="$1" exclude="${2:-}"
    echo "$release_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
match   = sys.argv[1].lower()
exclude = sys.argv[2].lower() if len(sys.argv) > 2 else ''
for a in data.get('assets', []):
    name = a['name'].lower()
    if match in name and (not exclude or exclude not in name):
        print(a['browser_download_url'])
        sys.exit(0)
sys.exit(1)
" "$match" "$exclude" || fail "No asset matching '${match}' in release '${EXPECTED_TAG}' of ${GITHUB_REPO}"
}

# Build download URL for a given platform
# Outputs: "<url> <filename>"
asset_for_platform() {
    local os_target="$1"

    # download_url_template fields (VS Code CDN, .NET SDK, etc.)
    if [[ "$os_target" == "windows" && -n "$DL_TPL_WIN" ]]; then
        local url="${DL_TPL_WIN//\{version\}/$NEW_VERSION}"
        # Use the real filename from the URL if it has a file extension; otherwise construct one.
        local url_path="${url%%\?*}"
        local fname="${url_path##*/}"
        if [[ "$fname" == "stable" || "$fname" != *.* ]]; then
            # CDN URL with no real filename (VS Code pattern)
            if [[ "$TOOL_ID" == "vscode" ]]; then
                fname="VSCodeUserSetup-x64-${NEW_VERSION}.exe"
            else
                fname="${TOOL_ID}-${NEW_VERSION}-windows-x64.bin"
            fi
        fi
        echo "$url $fname"
        return
    fi
    if [[ "$os_target" == "linux" && -n "$DL_TPL_LIN" ]]; then
        local url="${DL_TPL_LIN//\{version\}/$NEW_VERSION}"
        local url_path="${url%%\?*}"
        local fname="${url_path##*/}"
        if [[ "$fname" == "stable" || "$fname" != *.* ]]; then
            if [[ "$TOOL_ID" == "vscode" ]]; then
                fname="code-${NEW_VERSION}.el8.x86_64.rpm"
            else
                fname="${TOOL_ID}-${NEW_VERSION}-linux-x64.bin"
            fi
        fi
        echo "$url $fname"
        return
    fi

    # GCC Linux: RPMs are manual
    if [[ "$os_target" == "linux" && "$TOOL_ID" == "gcc" ]]; then
        warn "GCC Linux RPMs must be staged manually."
        [[ -n "$PLATFORM_NOTE" ]] && warn "  Note: $PLATFORM_NOTE"
        return 1
    fi

    # Standard GitHub asset resolution
    [[ -z "$release_json" ]] && fail "No release JSON available for GitHub asset resolution"

    local match
    if [[ "$os_target" == "linux" ]]; then
        match="${ASSET_MATCH_LIN:-$ASSET_MATCH}"
    else
        match="$ASSET_MATCH"
    fi
    [[ -z "$match" ]] && { warn "No asset_match for $os_target; skipping"; return 1; }

    # Read optional asset_exclude field (e.g. "net48" for Servy to skip .NET Framework variant)
    local asset_exclude; asset_exclude=$(json_field "$DEVKIT_JSON" "asset_exclude")

    local url; url=$(resolve_asset_url "$match" "$asset_exclude")
    local fname="${url##*/}"
    echo "$url $fname"
}

# ── Determine which platforms to stage ───────────────────────────────────────
declare -a PLATFORMS_TO_STAGE
if [[ -n "$ALL_PLATFORMS" ]]; then
    PLATFORMS_TO_STAGE=("windows" "linux")
elif [[ "$PLATFORM" == "windows" ]]; then
    PLATFORMS_TO_STAGE=("windows")
elif [[ "$PLATFORM" == "linux" ]]; then
    PLATFORMS_TO_STAGE=("linux")
else
    PLATFORMS_TO_STAGE=("$CURRENT_OS")
fi

# ── Create destination directory ──────────────────────────────────────────────
DEST_DIR="$REPO_ROOT/prebuilt/$CATEGORY/$TOOL_ID/$NEW_VERSION"

if [[ -z "${DRY_RUN:-}" ]]; then
    mkdir -p "$DEST_DIR"
    ok "Destination: $DEST_DIR"
else
    ok "[DRY RUN] Would create: $DEST_DIR"
fi

# ── Download, repack, and split assets ───────────────────────────────────────

declare -A WIN_ASSETS LIN_ASSETS  # maps: filename → sha256 (or "parts" if split)

download_and_stage() {
    local os_target="$1"
    local url fname staged_file staged_name staged_sha

    if ! read -r url fname < <(asset_for_platform "$os_target"); then
        warn "Skipping $os_target asset for $TOOL_ID"
        return 0
    fi

    log "Downloading $os_target asset: $fname"
    echo "    URL: $url"

    if [[ -n "${DRY_RUN:-}" ]]; then
        ok "[DRY RUN] Would download: $fname"
        return 0
    fi

    local raw_dl="$TMP_DIR/$fname"
    dl "$url" "$raw_dl"

    # ── Repack if needed ───────────────────────────────────────────────────
    local base="${fname%.*}"

    # Determine final staged filename and repack strategy
    staged_file="$raw_dl"
    staged_name="$fname"

    case "$fname" in
        *.zip)
            # Decide strip1 vs flat: inspect the zip root
            local nroots
            nroots=$(unzip -l "$raw_dl" | awk 'NR>3{print $4}' | cut -d'/' -f1 | sort -u | grep -v '^\s*$' | wc -l)
            local xz_name="${base}.tar.xz"
            staged_file="$TMP_DIR/$xz_name"
            staged_name="$xz_name"
            if (( nroots == 1 )); then
                repack_xz_strip1 "$raw_dl" "$staged_file"
            else
                repack_xz_flat "$raw_dl" "$staged_file"
            fi
            ;;
        *.tar.gz|*.tgz)
            # Strip compound extension correctly (.tar.gz → not just .gz)
            local xz_name
            if [[ "$fname" == *.tar.gz ]]; then
                xz_name="${fname%.tar.gz}.tar.xz"
            else
                xz_name="${fname%.tgz}.tar.xz"
            fi
            staged_file="$TMP_DIR/$xz_name"
            staged_name="$xz_name"
            repack_xz_flat "$raw_dl" "$staged_file"
            ;;
        *.tar.xz|*.exe|*.rpm|*.deb|*.7z)
            # Use as-is
            ;;
    esac

    # ── Split if >50MB ─────────────────────────────────────────────────────
    local size_bytes; size_bytes=$(wc -c < "$staged_file")
    local limit_bytes=$(( 50 * 1024 * 1024 ))

    if (( size_bytes > limit_bytes )); then
        split_parts "$staged_file" "$DEST_DIR" "$staged_name"
        if [[ "$os_target" == "windows" ]]; then
            WIN_ASSETS["$staged_name"]="parts"
        else
            LIN_ASSETS["$staged_name"]="parts"
        fi
    else
        cp "$staged_file" "$DEST_DIR/$staged_name"
        staged_sha=$(sha256 "$DEST_DIR/$staged_name")
        if [[ "$os_target" == "windows" ]]; then
            WIN_ASSETS["$staged_name"]="$staged_sha"
        else
            LIN_ASSETS["$staged_name"]="$staged_sha"
        fi
        ok "Staged: $staged_name ($(( size_bytes / 1024 / 1024 )) MB)"
    fi
}

for platform in "${PLATFORMS_TO_STAGE[@]}"; do
    download_and_stage "$platform"
done

# ── Write manifest.json ───────────────────────────────────────────────────────
if [[ -z "${DRY_RUN:-}" ]]; then
    log "Writing manifest.json"

    python3 - "$DEST_DIR" "$TOOL_ID" "$NEW_VERSION" \
              "$GITHUB_REPO" "$EXPECTED_TAG" \
              "${#WIN_ASSETS[@]}" "${#LIN_ASSETS[@]}" <<PYEOF
import json, sys, os

dest_dir, tool_id, version, github_repo, tag, win_count, lin_count = sys.argv[1:8]
win_count, lin_count = int(win_count), int(lin_count)

def build_platform_entry(assets_dict, part_shas_dict, archive_prefix):
    """Build the platform entry for manifest.json."""
    # Find the main archive name from assets
    archive = next(iter(assets_dict), '')
    sha_val = assets_dict.get(archive, '')

    if sha_val == 'parts':
        # Multi-part archive
        sorted_parts = sorted(part_shas_dict.keys())
        return {
            'archive': archive,
            'part_sha256': {p: part_shas_dict[p] for p in sorted_parts},
            'reassemble': f'cat {archive}.part-* | tar -xJ',
        }
    elif archive.endswith('.tar.xz'):
        return {
            'archive': archive,
            'sha256': sha_val,
            'reassemble': f'tar -xJf {archive}',
        }
    elif archive.endswith(('.exe', '.rpm', '.deb')):
        ext = archive.rsplit('.', 1)[-1]
        key = 'package' if ext in ('rpm', 'deb') else 'installer'
        return {key: archive, 'sha256': sha_val}
    else:
        return {'archive': archive, 'sha256': sha_val}

# Read part SHA mappings from the staged directory
def read_parts(prefix):
    result = {}
    for fn in sorted(os.listdir(dest_dir)):
        if fn.startswith(prefix + '.part-'):
            path = os.path.join(dest_dir, fn)
            import subprocess
            sha = subprocess.check_output(['sha256sum', path]).split()[0].decode()
            result[fn] = sha
    return result

# Build WIN / LIN entries from the staged files in DEST_DIR
def collect_assets(os_filter):
    """Collect staged assets whose names contain a platform hint."""
    result = {}
    for fn in sorted(os.listdir(dest_dir)):
        if fn.startswith('.') or fn == 'manifest.json':
            continue
        if '.part-' in fn:
            continue  # parts handled separately
        fp = os.path.join(dest_dir, fn)
        import subprocess
        sha = subprocess.check_output(['sha256sum', fp]).split()[0].decode()
        result[fn] = sha
    return result

# For simplicity, collect all non-part files and group them
all_files = {}
import subprocess
for fn in sorted(os.listdir(dest_dir)):
    if fn.startswith('.') or fn == 'manifest.json' or '.part-' in fn:
        continue
    fp = os.path.join(dest_dir, fn)
    sha = subprocess.check_output(['sha256sum', fp]).split()[0].decode()
    all_files[fn] = sha

# Group by platform hint (windows / linux)
def is_windows_asset(name):
    n = name.lower()
    return any(x in n for x in ('windows', 'win32', 'win64', 'win-', 'x64.exe', 'x64.msi',
                                  'vscodeusersetup', 'npp.', 'servy', 'osslsigncode'))

def is_linux_asset(name):
    n = name.lower()
    return any(x in n for x in ('linux', '.rpm', '.deb', '.tgz',))

manifest = {
    'tool': tool_id,
    'version': version,
    'source': f'https://github.com/{github_repo}/releases/tag/{tag}' if github_repo else '',
    'platforms': {},
    'compression': 'tar.xz',
}

# Single-platform tools get simpler manifest
if len(all_files) == 1:
    fn, sha = next(iter(all_files.items()))
    # Check for parts
    parts = {f: None for f in os.listdir(dest_dir) if f.startswith(fn + '.part-')}
    if parts:
        for p in parts:
            sha = subprocess.check_output(['sha256sum', os.path.join(dest_dir, p)]).split()[0].decode()
            parts[p] = sha
        entry = {'archive': fn, 'part_sha256': parts,
                 'reassemble': f'cat {fn}.part-* | tar -xJ'}
    elif fn.endswith('.tar.xz'):
        entry = {'archive': fn, 'sha256': sha, 'reassemble': f'tar -xJf {fn}'}
    else:
        ext = fn.rsplit('.', 1)[-1]
        key = 'package' if ext in ('rpm', 'deb') else ('installer' if ext == 'exe' else 'archive')
        entry = {key: fn, 'sha256': sha}

    # Determine platform key
    if is_windows_asset(fn):
        manifest['platforms']['windows'] = entry
    elif is_linux_asset(fn):
        manifest['platforms']['linux-x64'] = entry
    else:
        manifest['platforms']['windows'] = entry  # fallback
else:
    # Multi-platform: assign by name heuristics
    for fn, sha in all_files.items():
        parts = sorted(f for f in os.listdir(dest_dir) if f.startswith(fn + '.part-'))
        if parts:
            part_shas = {}
            for p in parts:
                part_shas[p] = subprocess.check_output(
                    ['sha256sum', os.path.join(dest_dir, p)]).split()[0].decode()
            entry = {'archive': fn, 'part_sha256': part_shas,
                     'reassemble': f'cat {fn}.part-* | tar -xJ'}
        elif fn.endswith('.tar.xz'):
            entry = {'archive': fn, 'sha256': sha, 'reassemble': f'tar -xJf {fn}'}
        else:
            ext = fn.rsplit('.', 1)[-1]
            key = 'package' if ext in ('rpm', 'deb') else ('installer' if ext == 'exe' else 'archive')
            entry = {key: fn, 'sha256': sha}

        if is_windows_asset(fn) or not is_linux_asset(fn):
            manifest['platforms'].setdefault('windows', entry)
        else:
            manifest['platforms'].setdefault('linux-x64', entry)

manifest_path = os.path.join(dest_dir, 'manifest.json')
with open(manifest_path, 'w') as mf:
    json.dump(manifest, mf, indent=2)
    mf.write('\n')
print(f'    Wrote {manifest_path}')
PYEOF

    ok "manifest.json written"
fi

# ── Update devkit.json version ────────────────────────────────────────────────
if [[ -z "${DRY_RUN:-}" ]]; then
    log "Updating devkit.json: version $CURRENT_VER → $NEW_VERSION"
    python3 -c "
import json, sys
path, new_ver = sys.argv[1], sys.argv[2]
d = json.load(open(path))
d['version'] = new_ver
with open(path, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
print('    Updated: ' + path)
" "$DEVKIT_JSON" "$NEW_VERSION"
    ok "devkit.json updated"
else
    ok "[DRY RUN] Would update devkit.json version to $NEW_VERSION"
fi

# ── Update setup.sh VERSION= line ────────────────────────────────────────────
SETUP_SH="$TOOL_DIR/setup.sh"
if [[ -f "$SETUP_SH" ]]; then
    if [[ -z "${DRY_RUN:-}" ]]; then
        log "Updating setup.sh: VERSION=\"$CURRENT_VER\" → VERSION=\"$NEW_VERSION\""
        if grep -q "VERSION=\"$CURRENT_VER\"" "$SETUP_SH"; then
            sed -i "s/VERSION=\"$CURRENT_VER\"/VERSION=\"$NEW_VERSION\"/" "$SETUP_SH"
            ok "setup.sh updated"
        else
            warn "VERSION=\"$CURRENT_VER\" not found in $SETUP_SH — update manually"
        fi
        bash -n "$SETUP_SH" && ok "setup.sh syntax check passed" || \
            fail "setup.sh syntax check FAILED — review $SETUP_SH"
    else
        ok "[DRY RUN] Would update setup.sh VERSION to $NEW_VERSION"
    fi
else
    warn "No setup.sh found at $SETUP_SH — skipping"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================================================"
if [[ -n "${DRY_RUN:-}" ]]; then
    echo " DRY RUN complete: $TOOL_NAME $CURRENT_VER → $NEW_VERSION"
    echo " No files were downloaded or modified."
else
    echo " Applied: $TOOL_NAME $CURRENT_VER → $NEW_VERSION"
    echo ""
    echo " Staged files:"
    ls -lh "$DEST_DIR" 2>/dev/null | tail -n +2 | awk '{print "   " $0}' || true
    echo ""
    echo " Next steps:"
    echo "   1. Regenerate SBOM:"
    echo "        bash scripts/internal/generate-sbom.sh"
    echo "   2. Commit prebuilt submodule:"
    echo "        (cd prebuilt && git add $CATEGORY/$TOOL_ID && git commit -m 'chore: $TOOL_ID $NEW_VERSION')"
    echo "   3. Commit parent repo:"
    echo "        git add tools/$CATEGORY/$TOOL_ID"
    echo "        git commit -m 'chore: bump $TOOL_ID to $NEW_VERSION'"
fi
echo "========================================================================"
