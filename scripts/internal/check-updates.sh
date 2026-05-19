#!/usr/bin/env bash
# scripts/internal/check-updates.sh
# Checks all airgap-devkit tools against their upstream sources and reports
# available version updates.
#
# Usage:
#   bash scripts/internal/check-updates.sh [--json] [--include-prerelease]
#
# Environment:
#   GITHUB_TOKEN  Optional. Authenticates GitHub API calls (5 000 req/hr vs 60/hr).
#
# Exit codes:
#   0  All tools are up-to-date (or manual-check only — no automated update needed)
#   1  One or more updates are available
#   2  Fatal error (missing python3, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/lib/devkit-prebuilt.sh"

# ── Argument parsing ──────────────────────────────────────────────────────────
JSON_MODE=false
INCLUDE_PRERELEASE=false

for arg in "$@"; do
    case "$arg" in
        --json)               JSON_MODE=true ;;
        --include-prerelease) INCLUDE_PRERELEASE=true ;;
        -h|--help)
            echo "Usage: bash check-updates.sh [--json] [--include-prerelease]"
            echo "  --json               Machine-readable JSON array output"
            echo "  --include-prerelease Include pre-release and RC tags"
            exit 0 ;;
    esac
done

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required" >&2; exit 2; }
command -v curl    >/dev/null 2>&1 || { echo "ERROR: curl is required"    >&2; exit 2; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Semver comparison: returns 0 (true) if version $1 is strictly greater than $2.
# Handles up to 4 dot-separated numeric segments.
semver_gt() {
    local a="$1" b="$2"
    IFS='.' read -ra A <<< "$a"
    IFS='.' read -ra B <<< "$b"
    local i av bv
    for (( i=0; i<4; i++ )); do
        av="${A[$i]:-0}"; bv="${B[$i]:-0}"
        # Strip any non-numeric suffix (e.g. "4rc1" → "4")
        av="${av%%[^0-9]*}"; bv="${bv%%[^0-9]*}"
        av="${av:-0}";       bv="${bv:-0}"
        (( 10#$av > 10#$bv )) && return 0
        (( 10#$av < 10#$bv )) && return 1
    done
    return 1  # equal
}

# Query GitHub /releases/latest and print the tag_name on stdout.
# Returns non-zero on any error (network, HTTP, no tag).
gh_latest_tag() {
    local repo="$1"
    local response
    response=$(curl -sf --max-time 15 \
        -w '\n%{http_code}' \
        -H "Accept: application/vnd.github.v3+json" \
        -H "User-Agent: airgap-devkit/1.0" \
        ${GITHUB_TOKEN:+-H "Authorization: token $GITHUB_TOKEN"} \
        "https://api.github.com/repos/${repo}/releases/latest") || return 1

    local http_code body
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | head -n -1)

    [[ "$http_code" == "200" ]] || return 1

    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
tag = d.get('tag_name', '')
if not tag:
    sys.exit(1)
print(tag)
" "$body"
}

# ── ANSI colors (disabled in JSON mode or when stdout is not a terminal) ──────
if [[ "$JSON_MODE" == false ]] && [[ -t 1 ]]; then
    C_GREEN='\033[0;32m' C_YELLOW='\033[0;33m' C_RED='\033[0;31m'
    C_CYAN='\033[0;36m'  C_GREY='\033[0;90m'   C_RESET='\033[0m'
else
    C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_GREY='' C_RESET=''
fi

if [[ "$JSON_MODE" == false ]] && [[ -z "${GITHUB_TOKEN:-}" ]]; then
    printf '%b\n' "${C_YELLOW}Note: GITHUB_TOKEN not set — unauthenticated limit is 60 req/hour.${C_RESET}"
fi

# ── Collect results ───────────────────────────────────────────────────────────

# Temp file accumulates one JSON object per line for final assembly
TMP_RESULTS=$(mktemp)
trap 'rm -f "$TMP_RESULTS"' EXIT

HAS_UPDATES=false

# Table row storage for human output
declare -a T_NAMES T_CURRENTS T_LATESTS T_STATUSES T_NOTES

while IFS= read -r -d '' devkit_file; do
    t_id=$(json_field "$devkit_file" "id")
    [[ -z "$t_id" ]] && continue

    t_name=$(json_field      "$devkit_file" "name")
    t_ver=$(json_field       "$devkit_file" "version")
    t_repo=$(json_field      "$devkit_file" "github_repo")
    t_prefix=$(json_field    "$devkit_file" "tag_prefix")
    t_check_url=$(json_field "$devkit_file" "check_url")

    latest_ver="" latest_tag="" t_status="" t_note=""

    if [[ -z "$t_repo" ]]; then
        # No GitHub source — manual check or no source at all
        if [[ -n "$t_check_url" ]]; then
            t_status="manual-check"
            t_note="$t_check_url"
        else
            t_status="no-source"
            t_note=""
        fi
    else
        if latest_tag=$(gh_latest_tag "$t_repo" 2>/dev/null); then
            # Strip tool-specific tag prefix (default "v").
            # bash '#' operator leaves the string unchanged if prefix doesn't match —
            # so tools like osslsigncode (tag "2.13") work correctly without a tag_prefix field.
            strip_prefix="${t_prefix:-v}"
            latest_ver="${latest_tag#$strip_prefix}"
            # Strip .windows.N suffix present in some Ninja release tags
            latest_ver="${latest_ver%.windows.*}"

            if semver_gt "$latest_ver" "$t_ver"; then
                t_status="update available"
                HAS_UPDATES=true
            elif [[ "$latest_ver" == "$t_ver" ]]; then
                t_status="up-to-date"
            else
                t_status="newer-than-released"
            fi
            t_note="$t_repo"
        else
            t_status="error"
            t_note="GitHub API unreachable or no stable release found"
        fi
    fi

    T_NAMES+=("$t_name")
    T_CURRENTS+=("$t_ver")
    T_LATESTS+=("${latest_ver:-}")
    T_STATUSES+=("$t_status")
    T_NOTES+=("${t_check_url:-}")

    python3 -c "
import json, sys
d = {
    'id':              sys.argv[1],
    'name':            sys.argv[2],
    'current_version': sys.argv[3],
    'latest_version':  sys.argv[4] or None,
    'latest_tag':      sys.argv[5] or None,
    'status':          sys.argv[6],
    'github_repo':     sys.argv[7] or None,
    'check_url':       sys.argv[8] or None,
}
print(json.dumps(d))
" "$t_id" "$t_name" "$t_ver" "$latest_ver" "$latest_tag" \
  "$t_status" "$t_repo" "$t_check_url" >> "$TMP_RESULTS"

done < <(find "$REPO_ROOT/tools" -name devkit.json -print0 | sort -z)

# ── Output ────────────────────────────────────────────────────────────────────

if [[ "$JSON_MODE" == true ]]; then
    python3 - "$TMP_RESULTS" <<'PYEOF'
import json, sys
records = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
print(json.dumps(records, indent=2))
PYEOF
else
    printf '\n%-24s  %-12s  %-12s  %s\n' "Tool" "Current" "Latest" "Status"
    printf '%s\n' "$(printf '%0.s-' {1..72})"

    for i in "${!T_NAMES[@]}"; do
        name="${T_NAMES[$i]}"
        current="${T_CURRENTS[$i]}"
        latest="${T_LATESTS[$i]}"
        status="${T_STATUSES[$i]}"
        note="${T_NOTES[$i]}"

        case "$status" in
            "up-to-date")          color="$C_GREEN"  ;;
            "update available")    color="$C_YELLOW" ;;
            "error")               color="$C_RED"    ;;
            "manual-check")        color="$C_CYAN"   ;;
            "newer-than-released") color="$C_GREY"   ;;
            *)                     color="$C_GREY"   ;;
        esac

        display_latest="$latest"
        [[ "$status" == "manual-check" ]] && display_latest="(see URL)"
        [[ "$status" == "no-source" || -z "$latest" ]] && display_latest="N/A"

        printf "%-24s  %-12s  %-12s  " "$name" "$current" "$display_latest"
        printf '%b%s%b' "$color" "$status" "$C_RESET"
        [[ "$status" == "manual-check" ]] && printf '  %b%s%b' "$C_GREY" "$note" "$C_RESET"
        printf '\n'
    done
    printf '\n'

    if [[ "$HAS_UPDATES" == true ]]; then
        printf '%bTo apply an update:%b\n' "$C_YELLOW" "$C_RESET"
        printf '  bash scripts/internal/apply-tool-update.sh <tool-id> <new-version>\n\n'
    fi
fi

$HAS_UPDATES && exit 1 || exit 0
