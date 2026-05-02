#!/usr/bin/env bash
# =============================================================================
# confluence-update.sh — Overwrite a Confluence page with devkit build status
#
# Usage:
#   bash .ci/atlassian/confluence-update.sh \
#       --page-id 123456789 \
#       --status  SUCCESS   \
#       --url     https://jenkins.example.com/job/devkit/42/ \
#       --profile cpp-dev   \
#       --team    "Platform Team" \
#       --build   42
#
# Required environment variables:
#   ATLASSIAN_BASE_URL    e.g. https://your-org.atlassian.net
#   ATLASSIAN_USER_EMAIL  e.g. ci-bot@your-org.com
#   ATLASSIAN_API_TOKEN   Atlassian API token
#
# Optional environment variables:
#   DEVKIT_SERVER_HOST   host of a running devkit server to pull live tool list
#   DEVKIT_SERVER_PORT   port of a running devkit server (default: 9090)
# =============================================================================
set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────────
PAGE_ID=""
BUILD_STATUS=""
BUILD_URL=""
PROFILE="unknown"
TEAM_NAME="unknown"
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --page-id) PAGE_ID="$2";      shift 2 ;;
        --status)  BUILD_STATUS="$2"; shift 2 ;;
        --url)     BUILD_URL="$2";    shift 2 ;;
        --profile) PROFILE="$2";      shift 2 ;;
        --team)    TEAM_NAME="$2";    shift 2 ;;
        --build)   BUILD_NUMBER="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
: "${ATLASSIAN_BASE_URL:?ATLASSIAN_BASE_URL is required}"
: "${ATLASSIAN_USER_EMAIL:?ATLASSIAN_USER_EMAIL is required}"
: "${ATLASSIAN_API_TOKEN:?ATLASSIAN_API_TOKEN is required}"
: "${PAGE_ID:?--page-id is required}"
: "${BUILD_STATUS:?--status is required}"

BASE_URL="${ATLASSIAN_BASE_URL%/}"
AUTH="${ATLASSIAN_USER_EMAIL}:${ATLASSIAN_API_TOKEN}"
WIKI_API="${BASE_URL}/wiki/rest/api"
TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"

# ── Determine status badge ────────────────────────────────────────────────────
case "${BUILD_STATUS^^}" in
    SUCCESS)  STATUS_COLOR="Green"  ;;
    FAILURE)  STATUS_COLOR="Red"    ;;
    UNSTABLE) STATUS_COLOR="Yellow" ;;
    *)        STATUS_COLOR="Grey"   ;;
esac

# ── Helper: confluence_api ────────────────────────────────────────────────────
confluence_api() {
    local method="$1"
    local path="$2"
    local body="${3:-}"

    if [[ -n "${body}" ]]; then
        curl -sf -X "${method}" \
             -u "${AUTH}" \
             -H "Content-Type: application/json" \
             -H "Accept: application/json" \
             -d "${body}" \
             "${WIKI_API}${path}"
    else
        curl -sf -X "${method}" \
             -u "${AUTH}" \
             -H "Accept: application/json" \
             "${WIKI_API}${path}"
    fi
}

# ── 1. Fetch current page metadata ────────────────────────────────────────────
echo "Fetching page ${PAGE_ID} metadata..."
PAGE_META="$(confluence_api GET "/content/${PAGE_ID}?expand=version,title")"
CURRENT_VERSION="$(echo "${PAGE_META}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['version']['number'])")"
PAGE_TITLE="$(echo "${PAGE_META}"      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['title'])")"
NEXT_VERSION=$(( CURRENT_VERSION + 1 ))
echo "Current version: ${CURRENT_VERSION}, updating to: ${NEXT_VERSION}"

# ── 2. Optionally pull live tool list from devkit server ──────────────────────
TOOL_ROWS=""
DEVKIT_HOST="${DEVKIT_SERVER_HOST:-}"
DEVKIT_PORT="${DEVKIT_SERVER_PORT:-9090}"

if [[ -n "${DEVKIT_HOST}" ]]; then
    TOOLS_JSON="$(curl -sf "http://${DEVKIT_HOST}:${DEVKIT_PORT}/api/tools" 2>/dev/null || echo '[]')"
    TOOL_ROWS="$(echo "${TOOLS_JSON}" | python3 -c '
import json, sys
tools = json.load(sys.stdin)
if not isinstance(tools, list):
    tools = list(tools.values()) if isinstance(tools, dict) else []
rows = []
for t in tools:
    name    = t.get("name", t.get("id",""))
    version = t.get("version","—")
    cat     = t.get("category","—")
    status  = "✅ Installed" if t.get("installed") else "○ Available"
    rows.append(f"<tr><td>{name}</td><td>{version}</td><td>{cat}</td><td>{status}</td></tr>")
print("\n".join(rows))
')"
fi

if [[ -z "${TOOL_ROWS}" ]]; then
    TOOL_ROWS="<tr><td colspan='4'><em>Tool list not available — start devkit server and set DEVKIT_SERVER_HOST</em></td></tr>"
fi

# ── 3. Build new page body (Confluence storage format) ───────────────────────
PAGE_BODY="<h2>AirGap DevKit — Deployment Status</h2>
<ac:structured-macro ac:name='info'>
  <ac:rich-text-body>
    <p>This page is automatically updated by the CI/CD pipeline. Last update: <strong>${TIMESTAMP}</strong></p>
  </ac:rich-text-body>
</ac:structured-macro>

<h3>Latest Build</h3>
<table>
  <thead><tr><th>Field</th><th>Value</th></tr></thead>
  <tbody>
    <tr><td><strong>Status</strong></td>
        <td><ac:structured-macro ac:name='status'><ac:parameter ac:name='colour'>${STATUS_COLOR}</ac:parameter><ac:parameter ac:name='title'>${BUILD_STATUS}</ac:parameter></ac:structured-macro></td></tr>
    <tr><td><strong>Build #</strong></td>      <td>${BUILD_NUMBER}</td></tr>
    <tr><td><strong>Profile</strong></td>      <td><code>${PROFILE}</code></td></tr>
    <tr><td><strong>Team</strong></td>         <td>${TEAM_NAME}</td></tr>
    <tr><td><strong>Timestamp</strong></td>    <td>${TIMESTAMP}</td></tr>
    <tr><td><strong>Build URL</strong></td>    <td><a href='${BUILD_URL}'>${BUILD_URL}</a></td></tr>
  </tbody>
</table>

<h3>Tool Inventory</h3>
<table>
  <thead><tr><th>Tool</th><th>Version</th><th>Category</th><th>Status</th></tr></thead>
  <tbody>
    ${TOOL_ROWS}
  </tbody>
</table>"

# ── 4. PUT updated page ───────────────────────────────────────────────────────
echo "Updating page '${PAGE_TITLE}' (id=${PAGE_ID}) to version ${NEXT_VERSION}..."

UPDATE_BODY="$(python3 -c "
import json, sys
body = {
    'id': '${PAGE_ID}',
    'type': 'page',
    'title': '${PAGE_TITLE}',
    'version': {'number': ${NEXT_VERSION}},
    'body': {
        'storage': {
            'value': sys.stdin.read(),
            'representation': 'storage'
        }
    }
}
print(json.dumps(body))
" <<< "${PAGE_BODY}")"

confluence_api PUT "/content/${PAGE_ID}" "${UPDATE_BODY}" >/dev/null
echo "Confluence page updated: ${BASE_URL}/wiki/spaces/_/pages/${PAGE_ID}"

echo "confluence-update.sh complete"
