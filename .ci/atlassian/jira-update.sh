#!/usr/bin/env bash
# =============================================================================
# jira-update.sh — Post build results to a Jira issue
#
# Usage:
#   bash .ci/atlassian/jira-update.sh \
#       --issue   DEVKIT-42 \
#       --status  SUCCESS   \
#       --url     https://jenkins.example.com/job/devkit/42/ \
#       --profile cpp-dev   \
#       --team    "Platform Team"
#
# Required environment variables (set as secrets in Jenkins/GitLab):
#   ATLASSIAN_BASE_URL    e.g. https://your-org.atlassian.net
#   ATLASSIAN_USER_EMAIL  e.g. ci-bot@your-org.com
#   ATLASSIAN_API_TOKEN   Atlassian API token (not your password)
#
# Optional environment variables:
#   JIRA_PROJECT_KEY      e.g. DEVKIT  (used when auto-creating failure issues)
#   JIRA_TRANSITION_SUCCESS   transition name to apply on SUCCESS  (default: Done)
#   JIRA_TRANSITION_FAILURE   transition name to apply on FAILURE  (default: "In Progress")
#   JIRA_TRANSITION_UNSTABLE  transition name to apply on UNSTABLE (default: "In Review")
# =============================================================================
set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────────
ISSUE_KEY=""
BUILD_STATUS=""
BUILD_URL=""
PROFILE="unknown"
TEAM_NAME="unknown"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue)   ISSUE_KEY="$2";    shift 2 ;;
        --status)  BUILD_STATUS="$2"; shift 2 ;;
        --url)     BUILD_URL="$2";    shift 2 ;;
        --profile) PROFILE="$2";      shift 2 ;;
        --team)    TEAM_NAME="$2";    shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ── Validate ──────────────────────────────────────────────────────────────────
: "${ATLASSIAN_BASE_URL:?ATLASSIAN_BASE_URL is required}"
: "${ATLASSIAN_USER_EMAIL:?ATLASSIAN_USER_EMAIL is required}"
: "${ATLASSIAN_API_TOKEN:?ATLASSIAN_API_TOKEN is required}"
: "${ISSUE_KEY:?--issue is required}"
: "${BUILD_STATUS:?--status is required}"

BASE_URL="${ATLASSIAN_BASE_URL%/}"
AUTH="${ATLASSIAN_USER_EMAIL}:${ATLASSIAN_API_TOKEN}"

JIRA_TRANSITION_SUCCESS="${JIRA_TRANSITION_SUCCESS:-Done}"
JIRA_TRANSITION_FAILURE="${JIRA_TRANSITION_FAILURE:-In Progress}"
JIRA_TRANSITION_UNSTABLE="${JIRA_TRANSITION_UNSTABLE:-In Review}"

# ── Determine build outcome ───────────────────────────────────────────────────
case "${BUILD_STATUS^^}" in
    SUCCESS)  STATUS_EMOJI="✅"; DESIRED_TRANSITION="${JIRA_TRANSITION_SUCCESS}" ;;
    FAILURE)  STATUS_EMOJI="❌"; DESIRED_TRANSITION="${JIRA_TRANSITION_FAILURE}" ;;
    UNSTABLE) STATUS_EMOJI="⚠️"; DESIRED_TRANSITION="${JIRA_TRANSITION_UNSTABLE}" ;;
    *)        STATUS_EMOJI="ℹ️"; DESIRED_TRANSITION="" ;;
esac

TIMESTAMP="$(date -u '+%Y-%m-%d %H:%M UTC')"

# ── Helper: jira_api_call ──────────────────────────────────────────────────────
jira_api() {
    local method="$1"
    local path="$2"
    local body="${3:-}"
    local url="${BASE_URL}/rest/api/3${path}"

    if [[ -n "${body}" ]]; then
        curl -sf -X "${method}" \
             -u "${AUTH}" \
             -H "Content-Type: application/json" \
             -H "Accept: application/json" \
             -d "${body}" \
             "${url}"
    else
        curl -sf -X "${method}" \
             -u "${AUTH}" \
             -H "Accept: application/json" \
             "${url}"
    fi
}

# ── 1. Post a comment ─────────────────────────────────────────────────────────
echo "Posting comment to ${ISSUE_KEY}..."

COMMENT_BODY=$(cat <<JSONEOF
{
  "body": {
    "type": "doc",
    "version": 1,
    "content": [
      {
        "type": "paragraph",
        "content": [
          {
            "type": "text",
            "text": "${STATUS_EMOJI} AirGap DevKit CI Build — ${BUILD_STATUS}",
            "marks": [{"type": "strong"}]
          }
        ]
      },
      {
        "type": "table",
        "attrs": {"isNumberColumnEnabled": false, "layout": "default"},
        "content": [
          {
            "type": "tableRow",
            "content": [
              {"type": "tableHeader", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Field"}]}]},
              {"type": "tableHeader", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Value"}]}]}
            ]
          },
          {
            "type": "tableRow",
            "content": [
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Status"}]}]},
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "${STATUS_EMOJI} ${BUILD_STATUS}"}]}]}
            ]
          },
          {
            "type": "tableRow",
            "content": [
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Profile"}]}]},
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "${PROFILE}"}]}]}
            ]
          },
          {
            "type": "tableRow",
            "content": [
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Team"}]}]},
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "${TEAM_NAME}"}]}]}
            ]
          },
          {
            "type": "tableRow",
            "content": [
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Timestamp"}]}]},
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "${TIMESTAMP}"}]}]}
            ]
          },
          {
            "type": "tableRow",
            "content": [
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "Build URL"}]}]},
              {"type": "tableCell", "content": [{"type": "paragraph", "content": [{"type": "text", "text": "${BUILD_URL}", "marks": [{"type": "link", "attrs": {"href": "${BUILD_URL}"}}]}]}]}
            ]
          }
        ]
      }
    ]
  }
}
JSONEOF
)

jira_api POST "/issue/${ISSUE_KEY}/comment" "${COMMENT_BODY}" >/dev/null
echo "Comment posted to ${ISSUE_KEY}"

# ── 2. Transition the issue (if desired transition is configured) ──────────────
if [[ -n "${DESIRED_TRANSITION}" ]]; then
    echo "Looking up transitions for ${ISSUE_KEY}..."
    TRANSITIONS_JSON="$(jira_api GET "/issue/${ISSUE_KEY}/transitions")"
    # Pass DESIRED_TRANSITION via environment variable, not string interpolation,
    # to prevent shell metacharacters in transition names from injecting Python code.
    TRANSITION_ID="$(echo "${TRANSITIONS_JSON}" | \
        DESIRED_TRANSITION="${DESIRED_TRANSITION}" python3 -c "
import json, os, sys
data = json.load(sys.stdin)
target = os.environ['DESIRED_TRANSITION'].lower()
for t in data.get('transitions', []):
    if t['name'].lower() == target:
        print(t['id'])
        break
")"

    if [[ -n "${TRANSITION_ID}" ]]; then
        TRANSITION_BODY="{\"transition\":{\"id\":\"${TRANSITION_ID}\"}}"
        jira_api POST "/issue/${ISSUE_KEY}/transitions" "${TRANSITION_BODY}" >/dev/null
        echo "Issue ${ISSUE_KEY} transitioned to '${DESIRED_TRANSITION}' (id=${TRANSITION_ID})"
    else
        echo "WARNING: transition '${DESIRED_TRANSITION}' not found for ${ISSUE_KEY} — skipping"
        echo "Available transitions: $(echo "${TRANSITIONS_JSON}" | python3 -c "import json,sys; [print(' -', t['name']) for t in json.load(sys.stdin).get('transitions',[])]")"
    fi
fi

# ── 3. Add label ──────────────────────────────────────────────────────────────
echo "Adding 'devkit-deployed' label to ${ISSUE_KEY}..."
LABEL_BODY='{"update":{"labels":[{"add":"devkit-deployed"}]}}'
jira_api PUT "/issue/${ISSUE_KEY}" "${LABEL_BODY}" >/dev/null
echo "Label added"

echo "jira-update.sh complete for ${ISSUE_KEY}"
