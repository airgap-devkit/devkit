#!/usr/bin/env bash
# Scan files with the VirusTotal API v3.
# Exits 1 if any file receives malicious detections above the threshold.
#
# Usage:
#   bash scripts/virustotal-scan.sh <file> [<file2> ...]
#
# Env vars:
#   VT_API_KEY          VirusTotal API v3 key (required)
#   VT_POLL_INTERVAL    seconds between status polls (default: 20)
#   VT_MALICIOUS_FAIL   allowed malicious detections before failure (default: 0)
set -euo pipefail

VT_API_KEY="${VT_API_KEY:-}"
VT_POLL_INTERVAL="${VT_POLL_INTERVAL:-20}"
VT_MALICIOUS_FAIL="${VT_MALICIOUS_FAIL:-0}"
VT_BASE="https://www.virustotal.com/api/v3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_DIR="$REPO_ROOT/dist/vt-reports"

if [[ $# -eq 0 ]]; then
    echo "Usage: bash scripts/virustotal-scan.sh <file> [<file2> ...]" >&2
    exit 1
fi

if [[ -z "$VT_API_KEY" ]]; then
    echo "ERROR: VT_API_KEY is not set." >&2
    echo "       Export your VirusTotal API v3 key: export VT_API_KEY=<key>" >&2
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "ERROR: curl is required but not on PATH." >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required for JSON parsing but not on PATH." >&2
    exit 1
fi

mkdir -p "$REPORT_DIR"

_has_jq=false
command -v jq &>/dev/null && _has_jq=true

_info() { echo "  $*"; }
_ok()   { echo "  [OK]   $*"; }
_warn() { echo "  [WARN] $*" >&2; }
_fail() { echo "  [FAIL] $*" >&2; }

# Pretty-print JSON if jq is available; otherwise pass through.
_pretty() {
    if [[ "$_has_jq" == true ]]; then
        jq .
    else
        cat
    fi
}

# Upload a file to VT and echo the analysis ID.
# Files >32 MB first obtain a dedicated upload URL.
_vt_upload() {
    local filepath="$1"
    local filesize
    filesize=$(wc -c < "$filepath" | tr -d '[:space:]')
    local max_direct
    max_direct=$(( 32 * 1024 * 1024 ))

    local upload_url="$VT_BASE/files"

    if [[ "$filesize" -gt "$max_direct" ]]; then
        _info "File >32 MB — fetching large-file upload URL ..."
        local url_resp
        url_resp=$(curl -sf \
            --header "x-apikey: $VT_API_KEY" \
            "$VT_BASE/files/upload_url")
        upload_url=$(python3 -c \
            "import sys,json; print(json.loads(sys.argv[1])['data'])" \
            "$url_resp" 2>/dev/null) || true
        if [[ -z "$upload_url" ]]; then
            echo "ERROR: could not obtain large-file upload URL from VirusTotal" >&2
            return 1
        fi
    fi

    local response
    response=$(curl -sf \
        --request POST "$upload_url" \
        --header "x-apikey: $VT_API_KEY" \
        --form "file=@$filepath")

    python3 -c \
        "import sys,json; print(json.loads(sys.argv[1])['data']['id'])" \
        "$response" 2>/dev/null || true
}

# Poll VT analyses endpoint until status == "completed".
# Echoes the final JSON response on stdout.
_vt_poll() {
    local analysis_id="$1"
    local poll_url="$VT_BASE/analyses/$analysis_id"
    local attempts=0
    local max_attempts=60   # 60 × VT_POLL_INTERVAL = up to 20 min default

    _info "Analysis ID: $analysis_id"
    _info "Polling every ${VT_POLL_INTERVAL}s (max ${max_attempts} attempts) ..."

    while [[ $attempts -lt $max_attempts ]]; do
        local resp
        resp=$(curl -sf \
            --header "x-apikey: $VT_API_KEY" \
            "$poll_url")

        local status
        status=$(python3 -c \
            "import sys,json; print(json.loads(sys.argv[1])['data']['attributes']['status'])" \
            "$resp" 2>/dev/null) || status=""

        if [[ "$status" == "completed" ]]; then
            echo "$resp"
            return 0
        fi

        attempts=$(( attempts + 1 ))
        _info "Status: ${status:-unknown}  (attempt $attempts/$max_attempts, waiting ${VT_POLL_INTERVAL}s ...)"
        sleep "$VT_POLL_INTERVAL"
    done

    echo "ERROR: VirusTotal analysis timed out after $max_attempts polls" >&2
    return 1
}

# ── main scan loop ────────────────────────────────────────────────────────────
overall_rc=0

for filepath in "$@"; do
    if [[ ! -f "$filepath" ]]; then
        _fail "File not found: $filepath"
        overall_rc=1
        continue
    fi

    filename="$(basename "$filepath")"
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  VirusTotal scan: $filename"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    _info "Uploading $(du -h "$filepath" | cut -f1) file ..."

    analysis_id=$(_vt_upload "$filepath")
    if [[ -z "$analysis_id" ]]; then
        _fail "Upload failed or no analysis ID returned for $filename"
        overall_rc=1
        continue
    fi

    final_resp=$(_vt_poll "$analysis_id") || { overall_rc=1; continue; }
    if [[ -z "$final_resp" ]]; then
        _fail "Empty response from polling for $filename"
        overall_rc=1
        continue
    fi

    # Save the full JSON report
    report_file="$REPORT_DIR/vt-${timestamp}-${filename}.json"
    echo "$final_resp" | _pretty > "$report_file"
    _info "Report: $report_file"

    # Parse detection stats
    stats=$(python3 - "$final_resp" <<'EOF'
import sys, json
d = json.loads(sys.argv[1])
s = d['data']['attributes']['stats']
print(
    s.get('malicious',  0),
    s.get('suspicious', 0),
    s.get('undetected', 0),
    s.get('harmless',   0),
    s.get('timeout',    0),
    s.get('failure',    0),
)
EOF
    ) || stats="0 0 0 0 0 0"

    read -r malicious suspicious undetected harmless timeout_cnt failure_cnt <<< "$stats"

    echo ""
    printf "  %-16s %s\n" "Malicious:"  "$malicious"
    printf "  %-16s %s\n" "Suspicious:" "$suspicious"
    printf "  %-16s %s\n" "Undetected:" "$undetected"
    printf "  %-16s %s\n" "Harmless:"   "$harmless"
    printf "  %-16s %s\n" "Timeout:"    "$timeout_cnt"
    printf "  %-16s %s\n" "Failure:"    "$failure_cnt"
    echo ""
    echo "  Permalink: https://www.virustotal.com/gui/file-analysis/$analysis_id"

    if [[ "$malicious" -gt "$VT_MALICIOUS_FAIL" ]]; then
        _fail "$filename — $malicious malicious detection(s) exceed threshold ($VT_MALICIOUS_FAIL)"
        overall_rc=1
    elif [[ "$suspicious" -gt 0 ]]; then
        _warn "$filename — $suspicious suspicious detection(s) (review the permalink above)"
        _ok "$filename — passed malicious threshold ($malicious/$VT_MALICIOUS_FAIL)"
    else
        _ok "$filename — clean (0 malicious, 0 suspicious)"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$overall_rc" -eq 0 ]]; then
    echo "  All files passed VirusTotal scan."
else
    echo "  VirusTotal scan FAILED — reports in dist/vt-reports/"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$overall_rc"
