# Changelog

All notable changes to airgap-cpp-devkit are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [1.2.1] — 2026-05-01

### Fixed
- `Dockerfile.rhel8-test` — RHEL 8 CI `$(ldd --version | head -1)` command substitution was evaluated by the outer `/bin/sh` and the result embedded unquoted, causing bash to choke on the parentheses in `ldd (GNU libc) 2.28` with a syntax error; wrapped the substitution in escaped double quotes so the parentheses are safely quoted when bash receives the string
- `.github/workflows/` — updated `actions/checkout` from v4.2.2 (Node.js 20, deprecated) to v4.3.1 (Node.js 24) across all three workflow files

---

## [1.2.0] — 2026-05-01

### Added
- **Manual install fallback** — when the devkit-ui cannot complete an installation, a "Show manual install commands" button appears in the terminal drawer; clicking it opens a modal with tabbed Windows / Linux steps, pre-filled copy-ready shell commands, and split-archive reassembly instructions generated from `GET /api/tool/{id}/manual-install`
- `GET /api/tool/{id}/manual-install` API endpoint — returns platform-specific env block, install command, custom prefix example, split-archive reassembly commands, and per-platform notes
- `scanPrebuiltParts` — server-side scanner that finds `.part-*` files in `prebuilt/` and builds `cat | tar` reassembly commands for each split archive
- `scripts/manual-install.sh` — CLI fallback installer; `--list` enumerates tools, `--tool <id>` installs, `--prefix` sets a custom path, `--verify-only` confirms split parts are present
- `docs/manual-install.md` — step-by-step manual install guide for Windows (Git Bash) and Linux, with tool-specific examples, manual split-archive reassembly commands, receipt creation, PATH wiring, and troubleshooting table
- `.github/workflows/rhel8-test.yml` — CI workflow that builds `Dockerfile.rhel8-test` and runs the full install + smoke-test suite inside UBI 8.10 (RHEL 8 / glibc 2.28); triggers on install-related path changes, weekly Monday schedule, and `workflow_dispatch`

### Fixed
- `install-cli.sh` — added `--admin` flag (selects system-wide install prefix); `Jenkinsfile` and `.gitlab-ci.yml` both pass `--admin` when `ADMIN_INSTALL=true` but the flag was previously unrecognised, crashing the install step
- `Jenkinsfile` and `.gitlab-ci.yml` server-ops stage — all API calls now include `X-DevKit-Token` header; `auth.go` requires the token for every route except `/health`, `/auth/bootstrap`, and `/static/`, so every `curl` to `/api/config`, `/api/health/tools`, etc. was returning 401
- `.gitlab-ci.yml` — replace fragile `/proc/*/cmdline` PID scan in `after_script` with a `.server.pid` file (`after_script` runs in a fresh shell and cannot access variables set in the main script)

---

## [1.1.0] — 2026-04-30

### Added
- **First-run setup wizard** — `/setup` page with animated gradient UI; server redirects all requests there until setup is complete (`setup_complete` flag in `devkit.config.json`)
- **Team Config Repository sync** — configure a git repo URL in Settings; devkit auto-syncs team config on every launch and provides a manual sync button with last-sync status indicator
- `server/internal/team/` package — `CloneOrPull`, `LoadConfig`, `LastCommit` helpers for team config git sync
- `setupCheck` middleware — enforces setup wizard flow on first launch before any dashboard access
- `validateRepoURL` — server-side validation for team config repo URL input
- `sanitizeDisplayName` — sanitization for display name fields
- `GET /api/team/status` and `POST /api/team/sync` API endpoints for team config sync
- Dashboard installed/all filter — clickable stat chip to toggle between all tools and installed-only view
- `escHtml` and `escJs` helper functions in dashboard JS to prevent XSS in dynamic content
- GitHub update version badges in the dashboard update checker UI
- `scripts/release.sh` — atomic version bump, Go binary build, Python wheel build, and optional PyPI upload
- `scripts/download-prebuilt.sh` — download prebuilt binaries from GitHub releases
- `packages/python/` — PyPI package source (`pyproject.toml`, `__main__.py`, `__init__.py`, stage-binaries script)
- `dist/` to `.gitignore` — wheel build artifacts are no longer tracked
- `.github/profile/README.md` — GitHub org profile landing page

### Changed
- `devkit.config.json` schema: added `team_config_repo` (string) and `setup_complete` (bool) fields
- `/api/config` accepts `team_config_repo`; triggers background sync when the repo URL changes
- Removed `7zip` from the built-in `cpp-dev` and `devops` profile tool lists
- `.gitignore`: fixed `.pyirc` typo → `.pypirc`; added `dist/` build artifact exclusion
- `README.md`: updated version reference to v1.1.0

---

## [1.0.1-rc.2] — 2026-04-26

### Changed
- `.gitignore` — added `.devkit-token` and TLS certificate exclusions
- Updated `prebuilt/` submodule to v1.0.1-rc.2 binaries

---

## [1.0.0-rc.1] — 2026-04-25

### Added
- `CONTRIBUTING.md` — dual-licensing CLA with copyright assignment and patent grant
- `CHANGELOG.md` — Keep a Changelog format with full backfilled history
- `SECURITY.md` — private disclosure policy, SLA table, scope definition, security design notes
- `CODE_OF_CONDUCT.md` — professional conduct standards and enforcement contact
- `.github/ISSUE_TEMPLATE/bug_report.md` — structured bug report template
- `.github/ISSUE_TEMPLATE/feature_request.md` — feature request template with air-gap compatibility checklist
- `.github/ISSUE_TEMPLATE/config.yml` — issue chooser with security advisory, discussions, and commercial licensing links
- `.github/pull_request_template.md` — PR checklist enforcing binary policy, SBOM, syntax checks
- `.github/FUNDING.yml` — GitHub sponsor button placeholder
- `SUPPORT.md` — help channels: issues, discussions, security email, commercial contact
- AGPL v3 license badge and CI badge in README
- Contributing and License sections in README with dual-licensing note

### Changed
- **Version bumped to v1.0.0-rc.1** — first release candidate
- `LICENSE` — relicensed from custom Source-Available License v1.0 to GNU Affero General Public License v3.0
- `SECURITY.md` — corrected TLS note: `--tls` auto-generates a self-signed certificate
- `.editorconfig` — added Go (tabs), JSON (2-space), and Makefile (tabs) sections

---

## [0.2.0-alpha.2] — 2025-04-19

### Added
- Session token authentication — one-time bootstrap redirect on first launch; token saved to `.devkit-token`
- Optional HTTPS support — pass `--tls-cert` and `--tls-key` to `launch.sh`
- Response header hardening (`X-Content-Type-Options`, `X-Frame-Options`, `Cache-Control`)
- VS Code integration tool entry

### Changed
- DevKit Manager is now a single pre-compiled Go binary; no Python, pip, or runtime dependencies required
- `launch.sh` selects the correct binary for the current platform automatically

---

## [0.2.0-alpha.1] — 2025-04-13

### Added
- CI/CD pipeline (GitHub Actions): build + smoke-test matrix across Windows and RHEL
- Atlassian integration placeholders
- Layout configuration support in `devkit.config.json`
- **My Team** button relocated to top bar for quicker access

### Changed
- Top bar height adjusted for denser layout
- Profile cards and settings panel layout polish

---

## [0.1.0] — 2025-03

### Added
- Initial air-gapped C++ developer toolkit
- FastAPI + HTMX devkit-ui with SSE live install output
- Tool auto-discovery from `devkit.json` per tool directory
- Install receipt tracking (`INSTALL_RECEIPT.txt`)
- Air-gap wheel vendoring under `tools/dev-tools/devkit-ui/vendor/`
- Multi-profile support: `cpp-dev`, `devops`, `minimal`, `full`
- Team config export/import (`GET /api/export`, `POST /api/import`)
- Update checker comparing installed version vs current `devkit.json`
- SBOM generation (`scripts/generate-sbom.sh` → `sbom.spdx.json`)
- Windows 11 (Git Bash) and RHEL 8 (Bash 4.x) support

---

[Unreleased]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.0.1-rc.2...v1.1.0
[1.0.1-rc.2]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v1.0.0-rc.1...v1.0.1-rc.2
[1.0.0-rc.1]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v0.2.0-alpha.2...v1.0.0-rc.1
[0.2.0-alpha.2]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v0.2.0-alpha.1...v0.2.0-alpha.2
[0.2.0-alpha.1]: https://github.com/NimaShafie/airgap-cpp-devkit/compare/v0.1.0...v0.2.0-alpha.1
[0.1.0]: https://github.com/NimaShafie/airgap-cpp-devkit/releases/tag/v0.1.0
