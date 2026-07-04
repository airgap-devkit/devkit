#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/internal/airgap-transfer.sh
#
# Build a self-verifying air-gap TRANSFER package of this git super-repo and its
# submodules, then verify one on the far side. Self-contained: uses git bundles
# + a portable SHA256SUMS manifest (`sha256sum -c`), so neither side needs a
# dso-suite checkout or the checksum engine at runtime.
#
# This mirrors the dso-suite `git_bundles` + `scripts/airgap-package.sh` contract
# (bundle super-repo + submodules, whole-payload SHA-256 manifest, bundled
# verify.sh, TRANSFER-RECEIPT.md, exit 3 on drift), so packages are interoperable
# with the dso-suite hub tooling that operates across every project. For a richer
# manifest with drift metrics, the cross-project engine is also available via
# scripts/internal/checksum-verify.sh.
#
# USAGE:
#   bash scripts/internal/airgap-transfer.sh build  [--repo DIR] [--out DIR] [--name NAME]
#   bash scripts/internal/airgap-transfer.sh verify  <package-dir>
#
# Exit codes: 0 = ok/intact, 3 = integrity drift (verify), 1/2 = usage/tooling.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

_die() { echo "[!!] $*" >&2; exit "${2:-1}"; }
command -v git >/dev/null || _die "git not found"
command -v sha256sum >/dev/null || _die "sha256sum not found"

MODE="${1:-}"; shift || true

# ---------------------------------------------------------------------------
build_package() {
    local repo="${REPO_ROOT}" out="." name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            --out)  out="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) _die "Unknown build arg: $1" ;;
        esac
    done
    repo="$(cd "${repo}" && pwd)"
    [[ -d "${repo}/.git" ]] || _die "Not a git repo: ${repo}"
    local ver; ver="$(git -C "${repo}" describe --tags --always --dirty 2>/dev/null || echo unknown)"
    [[ -n "${name}" ]] || name="$(basename "${repo}")-airgap-${ver}"
    mkdir -p "${out}"
    local pkg; pkg="$(cd "${out}" && pwd)/${name}"
    rm -rf "${pkg}"; mkdir -p "${pkg}/bundles"

    echo "==> Bundling super-repo + submodules from ${repo} (version ${ver})"
    git -C "${repo}" bundle create "${pkg}/bundles/$(basename "${repo}").bundle" --all
    # Each initialized submodule -> its own bundle (path flattened with __).
    while read -r sm; do
        [[ -n "${sm}" ]] || continue
        if git -C "${repo}/${sm}" rev-parse --git-dir >/dev/null 2>&1; then
            echo "    submodule: ${sm}"
            git -C "${repo}/${sm}" bundle create "${pkg}/bundles/${sm//\//__}.bundle" --all
        fi
    done < <(git -C "${repo}" submodule --quiet foreach 'echo "$sm_path"' 2>/dev/null || true)

    # Self-describing receipt (written BEFORE the manifest so it is covered).
    cat > "${pkg}/TRANSFER-RECEIPT.md" <<EOF
# Air-gap Transfer Package

- Source repo : $(basename "${repo}")
- Version     : ${ver}
- Created     : $(date -u +'%Y-%m-%dT%H:%M:%SZ')
- Contents    : git bundles (super-repo + submodules) under bundles/
- Integrity   : SHA256SUMS (whole-payload SHA-256; verify with verify.sh)

## Verify on the far side
    bash verify.sh          # exit 0 = intact, 3 = integrity drift

## Restore
    git clone bundles/$(basename "${repo}").bundle <dest>
    # then fetch each submodule bundle from bundles/<path__flattened>.bundle
EOF

    # Portable whole-payload manifest: every file except the manifest itself.
    echo "==> Generating SHA256SUMS"
    ( cd "${pkg}" && find . -type f ! -name SHA256SUMS ! -name verify.sh -print0 \
        | sort -z | xargs -0 sha256sum > SHA256SUMS )

    # Bundled, dependency-free verify script.
    cat > "${pkg}/verify.sh" <<'EOF'
#!/usr/bin/env bash
# Self-contained integrity gate for this transfer package.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -f SHA256SUMS ]] || { echo "[!!] SHA256SUMS missing"; exit 2; }
command -v sha256sum >/dev/null || { echo "[!!] sha256sum not found"; exit 2; }
if sha256sum -c --quiet SHA256SUMS; then
    echo "[verify] OK — payload intact"
    exit 0
else
    echo "[verify] DRIFT — payload does not match SHA256SUMS"
    exit 3
fi
EOF
    chmod +x "${pkg}/verify.sh"

    echo "==> Package ready: ${pkg}"
    echo "    Transfer the whole folder; on the far side run: bash verify.sh"
}

# ---------------------------------------------------------------------------
verify_package() {
    local pkg="${1:-}"
    [[ -n "${pkg}" && -d "${pkg}" ]] || _die "verify: pass the package directory" 2
    [[ -f "${pkg}/verify.sh" ]] || _die "verify: no verify.sh in ${pkg}" 2
    bash "${pkg}/verify.sh"
}

case "${MODE}" in
    build)  build_package "$@" ;;
    verify) verify_package "$@" ;;
    *) echo "Usage: airgap-transfer.sh {build|verify} ..." >&2; exit 1 ;;
esac
