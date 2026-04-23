# GitLab CI/CD Setup Guide — AirGap DevKit

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| GitLab | 15.0+ (GitLab.com or self-managed) |
| GitLab Runner | 15.0+, registered to your project or group |
| Runner tags | `linux` (required), `windows` (optional) |
| Runner executor | `shell` or `docker` with bash/python3/curl available |

---

## 1. Register Runners

### Linux Runner (required)

```bash
# On your Linux CI machine / VM
gitlab-runner register \
  --url "https://gitlab.example.com" \
  --registration-token "YOUR_REGISTRATION_TOKEN" \
  --executor shell \
  --tag-list linux \
  --description "airgap-devkit-linux" \
  --non-interactive
```

### Windows Runner (optional — only needed for `TARGET_OS=windows` or `both`)

```powershell
# On your Windows CI machine
gitlab-runner register `
  --url "https://gitlab.example.com" `
  --registration-token "YOUR_REGISTRATION_TOKEN" `
  --executor shell `
  --tag-list windows `
  --description "airgap-devkit-windows" `
  --non-interactive
```

The Windows runner must have Git Bash (MINGW64) in PATH so `bash` commands work.

---

## 2. Configure CI/CD Variables

Go to **Settings → CI/CD → Variables → Expand → Add variable**.

### Required for Atlassian integration (add when ready)

| Key | Type | Protected | Masked | Value |
|-----|------|-----------|--------|-------|
| `ATLASSIAN_BASE_URL` | Variable | yes | no | `https://your-org.atlassian.net` |
| `ATLASSIAN_USER_EMAIL` | Variable | yes | no | `ci-bot@your-org.com` |
| `ATLASSIAN_API_TOKEN` | Variable | yes | **yes** | your API token |

### Optional persistent defaults (override per-run if needed)

| Key | Default | Description |
|-----|---------|-------------|
| `TEAM_NAME` | `My Team` | Overrides devkit.config.json team name |
| `PROFILE` | `minimal` | Default install profile |
| `SERVER_PORT` | `9090` | Default devkit server port |

Variables set in **Settings → CI/CD** persist across all pipelines. Variables set at run time (via **Run pipeline**) override them for that run only.

---

## 3. Running the Pipeline

### Standard push trigger

Pipelines run automatically on:
- Push to the default branch
- Merge request events
- Scheduled pipelines

### Manual run with custom variables

1. Go to **CI/CD → Pipelines → Run pipeline**
2. Select your branch
3. Add variable overrides in the **Variables** form:

| Variable | Example value |
|----------|--------------|
| `PROFILE` | `cpp-dev` |
| `TEAM_NAME` | `Backend Team` |
| `TARGET_OS` | `both` |
| `ATLASSIAN_UPDATE` | `true` |
| `JIRA_ISSUE_KEY` | `DEVKIT-42` |
| `CONFLUENCE_PAGE_ID` | `123456789` |
| `EXPORT_TEAM_CONFIG` | `true` |
| `UPLOAD_PACKAGE` | `true` |
| `PACKAGE_FILE_PATH` | `/opt/packages/my-bundle.zip` |

4. Click **Run pipeline**

---

## 4. Variable Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `TEAM_NAME` | `My Team` | Team display name written to `devkit.config.json` |
| `ORG_NAME` | _(empty)_ | Organization name |
| `DEVKIT_NAME` | `AirGap DevKit` | UI header title |
| `PROFILE` | `minimal` | Install profile: `minimal` \| `cpp-dev` \| `devops` \| `full` |
| `TARGET_OS` | `linux` | Platform: `linux` \| `windows` \| `both` |
| `SERVER_HOST` | `127.0.0.1` | Bind address for the devkit server |
| `SERVER_PORT` | `9090` | Port for the devkit server |
| `ADMIN_INSTALL` | `false` | Set `true` to pass `--admin` to `install-cli.sh` |
| `UPLOAD_PACKAGE` | `false` | Set `true` to upload a `.zip` bundle |
| `PACKAGE_FILE_PATH` | _(empty)_ | Absolute path on runner to a `.zip` package |
| `EXPORT_TEAM_CONFIG` | `false` | Set `true` to export and artifact `team-config-export.json` |
| `IMPORT_TEAM_CONFIG` | _(empty)_ | Raw JSON to `POST /api/import` (paste team-config.json) |
| `SAVE_PROFILE_JSON` | _(empty)_ | JSON body for `POST /api/profiles` |
| `RUN_VALIDATE` | `true` | Run `tests/validate-manifests.sh` |
| `RUN_SMOKE_TESTS` | `true` | Run `tests/run-tests.sh` after install |
| `ATLASSIAN_UPDATE` | `false` | Push results to Jira/Confluence |
| `JIRA_ISSUE_KEY` | _(empty)_ | Jira issue key, e.g. `DEVKIT-42` |
| `CONFLUENCE_PAGE_ID` | _(empty)_ | Confluence page numeric ID |

---

## 5. Pipeline Stages and Jobs

```
validate → configure → install → server-ops → test → atlassian
```

| Job | Stage | Runs on | Condition |
|-----|-------|---------|-----------|
| `validate:manifests` | validate | linux | `RUN_VALIDATE=true` |
| `configure` | configure | linux | always |
| `install:linux` | install | linux | `TARGET_OS=linux` or `both` |
| `install:windows` | install | windows | `TARGET_OS=windows` or `both` |
| `server-ops` | server-ops | linux | always |
| `test:linux` | test | linux | `RUN_SMOKE_TESTS=true` and `TARGET_OS=linux` or `both` |
| `test:windows` | test | windows | `RUN_SMOKE_TESTS=true` and `TARGET_OS=windows` or `both` |
| `atlassian:update` | atlassian | linux | `ATLASSIAN_UPDATE=true` and issue/page set |

---

## 6. Artifacts

| Path | Kept for | Contents |
|------|----------|---------|
| `devkit.config.json` | 1 hour | Configured file (passed to install/server stages) |
| `**/INSTALL_RECEIPT.txt` | 7 days | Per-tool install stamps |
| `devkit-server.log` | 14 days | Server stdout from server-ops stage |
| `tool-health.json` | 14 days | `GET /api/health/tools` snapshot |
| `team-config-export.json` | 14 days | `GET /api/export` result (when enabled) |

---

## 7. Scheduled Pipelines

Go to **CI/CD → Schedules → New schedule**:

| Purpose | Cron | Variables |
|---------|------|-----------|
| Weekly smoke test (minimal) | `0 6 * * 1` | `PROFILE=minimal`, `RUN_SMOKE_TESTS=true` |
| Weekly smoke test (full) | `0 8 * * 1` | `PROFILE=full`, `TARGET_OS=linux` |
| Nightly health check | `0 2 * * *` | `RUN_VALIDATE=true`, `RUN_SMOKE_TESTS=false` |

---

## 8. Submodule Configuration

The runner must be able to clone submodules. The pipeline sets:
```yaml
GIT_SUBMODULE_STRATEGY: recursive
```

If your submodule uses SSH and your runner uses HTTPS (or vice versa), configure submodule URL rewrites in `.gitmodules` or via GitLab's **Settings → Repository → Mirroring**.

For air-gapped runners with no internet access: pre-clone the repo with all submodules to the runner's workspace directory, then configure the runner to use that as a cache.

---

## 9. Triggering via API

```bash
# Trigger pipeline with custom profile
curl -X POST \
  "https://gitlab.example.com/api/v4/projects/YOUR_PROJECT_ID/trigger/pipeline" \
  --form "token=YOUR_TRIGGER_TOKEN" \
  --form "ref=main" \
  --form "variables[PROFILE]=cpp-dev" \
  --form "variables[TEAM_NAME]=Backend Team" \
  --form "variables[ATLASSIAN_UPDATE]=true" \
  --form "variables[JIRA_ISSUE_KEY]=DEVKIT-42"
```

---

## 10. Troubleshooting

| Symptom | Fix |
|---------|-----|
| Job skipped unexpectedly | Check the `rules:` condition — `$TARGET_OS == "linux"` is string comparison |
| `bash: command not found` on Windows | Ensure Git Bash is in PATH on the Windows runner |
| Server health check fails | Verify `SERVER_HOST`/`SERVER_PORT` match `devkit.config.json`; check the server log artifact |
| `400 Bad Request` on package upload | Only `.zip` files accepted; check the file exists at `PACKAGE_FILE_PATH` |
| Atlassian `401 Unauthorized` | Verify masked variables are set; test with `curl -u email:token` manually |
| `configure` artifact not found | `configure` job must complete before `install`/`server-ops` (uses `needs:`) |
