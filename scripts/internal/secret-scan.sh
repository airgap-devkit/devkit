#!/usr/bin/env bash
# Full-tree credential scan that does NOT honor .gitignore.
#
# gitleaks and trufflehog skip .gitignore'd paths, so a token left in an ignored
# dotfile slips past them. This scans the entire working tree with whichever
# ignore-agnostic engine is available (trivy preferred, then detect-secrets),
# and falls back to a small built-in pattern check so the gate still fails on an
# obvious credential even with no scanner installed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

fail() { echo "SECRET SCAN: $*" >&2; exit 1; }

if command -v trivy >/dev/null 2>&1; then
    # trivy's secret scanner walks the filesystem and ignores .gitignore.
    if ! trivy fs --scanners secret --exit-code 1 --skip-dirs .git --quiet .; then
        fail "trivy found a secret in the working tree (including ignored files)."
    fi
    exit 0
fi

if command -v detect-secrets >/dev/null 2>&1; then
    # --all-files disables the git-tracked-only default, so ignored files are scanned.
    if detect-secrets scan --all-files --exclude-files '\.git/' \
        | grep -Eq '"type":[[:space:]]*"'; then
        fail "detect-secrets found a potential secret in the working tree."
    fi
    exit 0
fi

# Minimal fallback: known high-value credential prefixes, ignore rules bypassed.
if grep -rInE 'pypi-AgE[A-Za-z0-9_-]{20,}|-----BEGIN (RSA|EC|OPENSSH) PRIVATE KEY-----|AKIA[0-9A-Z]{16}' \
    --exclude-dir=.git . >/dev/null 2>&1; then
    fail "credential pattern found in the working tree (install trivy for full coverage)."
fi

echo "secret-scan: no scanner installed; ran built-in pattern check only." >&2
exit 0
