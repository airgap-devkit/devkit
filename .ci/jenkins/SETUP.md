# Jenkins Setup Guide — AirGap DevKit

## Prerequisites

| Requirement | Minimum version |
|-------------|----------------|
| Jenkins | 2.387 LTS |
| Pipeline plugin | bundled |
| Pipeline Utility Steps plugin | 2.15+ |
| Credentials Binding plugin | bundled |
| AnsiColor plugin | optional (prettier logs) |
| Git plugin | bundled |

---

## 1. Create the Pipeline Job

1. **New Item → Pipeline** — name it e.g. `airgap-devkit`
2. **General → This project is parameterized** — check the box
   - Jenkins reads all `parameters {}` from `Jenkinsfile` on first run. You do not need to manually add them — run the pipeline once (it will fail early) and the parameter form auto-populates.
3. **Build Triggers** — configure as needed:
   - Poll SCM: `H/15 * * * *` (check every 15 min)
   - GitHub/GitLab webhook: configure per your SCM integration
   - Build periodically for scheduled smoke tests: `H 6 * * 1` (Mondays 06:00)

---

## 2. Configure SCM

Under **Pipeline → Definition: Pipeline script from SCM**:

| Field | Value |
|-------|-------|
| SCM | Git |
| Repository URL | your repo URL |
| Credentials | your Git credentials (if needed) |
| Branch | `*/main` |
| Script Path | `Jenkinsfile` |
| **Lightweight checkout** | uncheck (pipeline params need full checkout) |

Enable **Submodules** under Additional Behaviours → Advanced sub-modules behaviours:
- Check "Recursively update submodules"
- Uncheck "Tracking submodules" (use pinned commits)

---

## 3. Configure Agent Labels

The pipeline expects two agent labels. Configure them to match your environment:

| Label | Purpose |
|-------|---------|
| `linux` | Ubuntu/RHEL runner with bash, curl, python3 |
| `windows` | Windows runner with Git Bash (MINGW64) |

To use a single Linux-only setup:
- Keep `linux` as your only agent
- Always set `TARGET_OS=linux` in the pipeline parameters

If you only have one agent and it has no label, edit `Jenkinsfile` and replace `agent { label 'linux' }` with `agent any`.

---

## 4. Add Credentials

Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credential**.

Add the following as **Secret text** credentials:

| Credential ID | Value |
|---------------|-------|
| `ATLASSIAN_BASE_URL` | `https://your-org.atlassian.net` |
| `ATLASSIAN_USER_EMAIL` | `ci-bot@your-org.com` |
| `ATLASSIAN_API_TOKEN` | your Atlassian API token |

These are only used when `ATLASSIAN_UPDATE=true`. You can skip them if you do not use Atlassian.

To generate an Atlassian API token: https://id.atlassian.com/manage-profile/security/api-tokens

---

## 5. First Run

1. Click **Build with Parameters**
2. Accept all defaults (`PROFILE=minimal`, `TARGET_OS=linux`, `RUN_VALIDATE=true`)
3. Watch the stage view — each stage name maps directly to a `stage {}` block in the `Jenkinsfile`

---

## 6. Parameter Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TEAM_NAME` | String | `My Team` | Displayed in the devkit UI header. Written to `devkit.config.json`. |
| `ORG_NAME` | String | _(blank)_ | Organization name, also written to `devkit.config.json`. |
| `DEVKIT_NAME` | String | `AirGap DevKit` | Dashboard title shown in the browser tab and header. |
| `PROFILE` | Choice | `minimal` | Install profile. See table below. |
| `TARGET_OS` | Choice | `linux` | Which agents to install on. `both` requires linux+windows agents. |
| `SERVER_HOST` | String | `127.0.0.1` | Bind address for server health checks in the Server stage. |
| `SERVER_PORT` | String | `9090` | Port for the devkit server. |
| `ADMIN_INSTALL` | Boolean | `false` | Pass `--admin` to `install-cli.sh` (system-wide install). |
| `UPLOAD_PACKAGE` | Boolean | `false` | Upload a `.zip` package bundle via `POST /packages/upload`. |
| `PACKAGE_FILE_PATH` | String | _(blank)_ | Absolute path on the Linux agent to the `.zip` to upload. |
| `EXPORT_TEAM_CONFIG` | Boolean | `false` | Call `GET /api/export` and archive the result as `team-config-export.json`. |
| `IMPORT_TEAM_CONFIG` | Text | _(blank)_ | Raw JSON to `POST /api/import`. Paste `team-config.json` contents here. |
| `SAVE_PROFILE_JSON` | Text | _(blank)_ | JSON body for `POST /api/profiles`. Creates or updates a named profile. |
| `RUN_VALIDATE` | Boolean | `true` | Run `tests/validate-manifests.sh` before install. |
| `RUN_SMOKE_TESTS` | Boolean | `true` | Run `tests/run-tests.sh` after install. |
| `ATLASSIAN_UPDATE` | Boolean | `false` | Push results to Jira/Confluence. Requires credentials above. |
| `JIRA_ISSUE_KEY` | String | _(blank)_ | Jira issue to comment on, e.g. `DEVKIT-42`. |
| `CONFLUENCE_PAGE_ID` | String | _(blank)_ | Confluence page ID to overwrite with status table. |

### Profile Contents

| Profile | Tools |
|---------|-------|
| `minimal` | clang, cmake, python, style-formatter |
| `cpp-dev` | clang, cmake, python, conan, vscode-extensions, sqlite, 7zip |
| `devops` | cmake, python, conan, sqlite, 7zip |
| `full` | all available tools |

---

## 7. Pipeline Stages

```
Validate Manifests  →  Configure  →  Install (parallel: Linux + Windows)
  →  Server Operations  →  Smoke Tests (parallel)  →  Atlassian
```

| Stage | What it does |
|-------|-------------|
| Validate Manifests | Runs `tests/validate-manifests.sh` — checks JSON syntax, required fields, SHA checksums |
| Configure | Patches `devkit.config.json` with pipeline parameters; stashes the file |
| Install — Linux | Runs `install-cli.sh --yes --profile <PROFILE>` on the linux agent |
| Install — Windows | Same on the windows agent (skipped if TARGET_OS=linux) |
| Server Operations | Starts the devkit server, pushes config, optionally uploads packages / imports team config / exports team config, collects tool health JSON, stops server |
| Smoke Tests | Runs `tests/run-tests.sh --verbose` (and `check-installed-tools.sh` on Linux) |
| Atlassian | Posts build status comment to Jira issue; updates Confluence status page |

---

## 8. Artifacts Collected Per Build

| File | Source |
|------|--------|
| `**/INSTALL_RECEIPT.txt` | Each tool's install stamp |
| `team-config-export.json` | When `EXPORT_TEAM_CONFIG=true` |
| `tool-health.json` | Live health check of all tools |
| `devkit-server.log` | Server stdout/stderr from the Server Operations stage |

---

## 9. Triggering via API

```bash
# Trigger with custom profile and team name
curl -X POST \
  "https://jenkins.example.com/job/airgap-devkit/buildWithParameters" \
  --user "user:api-token" \
  --data "PROFILE=cpp-dev&TEAM_NAME=Backend+Team&TARGET_OS=linux&RUN_SMOKE_TESTS=true"
```

---

## 10. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Parameters not showing | Build once to seed the form; Jenkins reads params from Jenkinsfile on first run |
| `readJSON` step not found | Install the **Pipeline Utility Steps** plugin |
| `label 'linux'` agent not found | Add the label to your agent under Manage Jenkins → Nodes |
| Server health check timeout | Increase the `seq 1 30` loop or check that `launch.sh` works manually |
| Atlassian `401 Unauthorized` | Verify `ATLASSIAN_USER_EMAIL` + `ATLASSIAN_API_TOKEN` credentials are correct |
| `package` field 400 error | Only `.zip` files are accepted by `POST /packages/upload` |
