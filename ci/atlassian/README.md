# Atlassian Integration — AirGap DevKit

Connects the CI/CD pipeline to Jira and Confluence via the Atlassian REST API.

---

## Scripts

| Script | Purpose |
|--------|---------|
| `jira-update.sh` | Post a build status comment to a Jira issue and optionally transition it |
| `confluence-update.sh` | Overwrite a Confluence page with a build status + tool inventory table |

Both scripts are called automatically by the **Atlassian** stage in `Jenkinsfile` and `atlassian:update` job in `.gitlab-ci.yml` when `ATLASSIAN_UPDATE=true`.

---

## Quick Setup

### 1. Generate an Atlassian API token

1. Log in to [id.atlassian.com](https://id.atlassian.com/manage-profile/security/api-tokens)
2. **Create API token** → give it a name (e.g. `devkit-ci`)
3. Copy the token — you will not see it again

### 2. Store secrets in your CI platform

**Jenkins** (Manage Jenkins → Credentials → System → Global → Add Credential → Secret text):

| ID | Value |
|----|-------|
| `ATLASSIAN_BASE_URL` | `https://your-org.atlassian.net` |
| `ATLASSIAN_USER_EMAIL` | email of the account that owns the API token |
| `ATLASSIAN_API_TOKEN` | the token from step 1 |

**GitLab** (Settings → CI/CD → Variables, mark `ATLASSIAN_API_TOKEN` as **Masked**):

| Key | Value |
|-----|-------|
| `ATLASSIAN_BASE_URL` | `https://your-org.atlassian.net` |
| `ATLASSIAN_USER_EMAIL` | email of the account that owns the API token |
| `ATLASSIAN_API_TOKEN` | the token from step 1 |

### 3. Fill in `atlassian.config.json`

Copy the template and record your project key and page IDs:
```bash
cp .ci/atlassian/atlassian.config.json .ci/atlassian/atlassian.local.json
# edit atlassian.local.json — this file is gitignored
```

> **Never commit your API token.** `atlassian.config.json` is a template with placeholder values only.

---

## Finding Confluence Page IDs

### Method 1: URL
Open the page in your browser. The URL contains the page ID:
```
https://your-org.atlassian.net/wiki/spaces/DEVKIT/pages/123456789/DevKit+Status
                                                                  ^^^^^^^^^^^
```

### Method 2: Page info
On the page: `⋯ (More actions) → Page information` — the ID appears in the URL.

### Method 3: API
```bash
curl -u email:token \
  "https://your-org.atlassian.net/wiki/rest/api/content?title=DevKit+Status&spaceKey=DEVKIT"
```

---

## Jira Transition Names

The pipeline transitions the Jira issue based on build result. Default mappings:

| Build result | Default transition |
|-------------|-------------------|
| `SUCCESS` | `Done` |
| `FAILURE` | `In Progress` |
| `UNSTABLE` | `In Review` |

Override these with environment variables in Jenkins/GitLab:

```bash
JIRA_TRANSITION_SUCCESS=Done
JIRA_TRANSITION_FAILURE="In Progress"
JIRA_TRANSITION_UNSTABLE="In Review"
```

To see the available transitions for your workflow:
```bash
curl -u email:token \
  "https://your-org.atlassian.net/rest/api/3/issue/DEVKIT-42/transitions"
```

---

## Running Scripts Manually

```bash
export ATLASSIAN_BASE_URL="https://your-org.atlassian.net"
export ATLASSIAN_USER_EMAIL="you@org.com"
export ATLASSIAN_API_TOKEN="your-token"

# Post to Jira
bash .ci/atlassian/jira-update.sh \
  --issue   DEVKIT-42 \
  --status  SUCCESS   \
  --url     "https://jenkins.example.com/job/devkit/42/" \
  --profile cpp-dev   \
  --team    "Platform Team"

# Update Confluence page
bash .ci/atlassian/confluence-update.sh \
  --page-id 123456789 \
  --status  SUCCESS   \
  --url     "https://jenkins.example.com/job/devkit/42/" \
  --profile cpp-dev   \
  --team    "Platform Team" \
  --build   42
```

---

## Live Tool List in Confluence

If you set `DEVKIT_SERVER_HOST` when calling `confluence-update.sh`, it fetches the live tool inventory from `GET /api/tools` and renders it as a table on the page:

```bash
export DEVKIT_SERVER_HOST=127.0.0.1
export DEVKIT_SERVER_PORT=9090
bash .ci/atlassian/confluence-update.sh --page-id 123456789 ...
```

Without this, the tool table shows a placeholder message.

---

## API Reference

| Endpoint | Used by |
|----------|---------|
| `POST /rest/api/3/issue/{key}/comment` | `jira-update.sh` — adds build status comment |
| `GET  /rest/api/3/issue/{key}/transitions` | `jira-update.sh` — discovers available workflow transitions |
| `POST /rest/api/3/issue/{key}/transitions` | `jira-update.sh` — moves issue through workflow |
| `PUT  /rest/api/3/issue/{key}` | `jira-update.sh` — adds `devkit-deployed` label |
| `GET  /wiki/rest/api/content/{id}` | `confluence-update.sh` — fetches current page version |
| `PUT  /wiki/rest/api/content/{id}` | `confluence-update.sh` — overwrites page body |
| `GET  /api/tools` | `confluence-update.sh` — live tool list from devkit server |
