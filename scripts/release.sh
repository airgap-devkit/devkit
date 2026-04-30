#!/usr/bin/env bash
# Release script — bumps version, builds Go binaries, builds pip wheel, uploads to PyPI.
#
# Usage:
#   bash scripts/release.sh <version> [--no-build] [--test] [--upload]
#
# Examples:
#   bash scripts/release.sh 1.0.2                   # bump + build wheel, no upload
#   bash scripts/release.sh 1.0.2 --upload          # bump + build + upload to PyPI
#   bash scripts/release.sh 1.0.2 --test            # upload to TestPyPI instead
#   bash scripts/release.sh 1.0.2 --no-build        # skip Go compile (use existing prebuilt/)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── args ──────────────────────────────────────────────────────────────────────
VERSION="${1:-}"
NO_BUILD=false
UPLOAD=false
TEST_PYPI=false

if [[ -z "$VERSION" ]]; then
    echo "Usage: bash scripts/release.sh <version> [--no-build] [--test] [--upload]" >&2
    echo "  version format: 1.2.3 or 1.2.3rc1 or 1.2.3b2" >&2
    exit 1
fi

shift
for arg in "$@"; do
    case "$arg" in
        --no-build) NO_BUILD=true ;;
        --upload)   UPLOAD=true ;;
        --test)     TEST_PYPI=true; UPLOAD=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# ── python detection ──────────────────────────────────────────────────────────
# Find a Python that has 'build' and 'twine' installed.
PYTHON=""
for candidate in \
    "/c/Users/n1mz/AppData/Local/Python/pythoncore-3.14-64/python.exe" \
    "python3" "python"; do
    if "$candidate" -c "import build, twine" 2>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done

if [[ -z "$PYTHON" ]]; then
    echo "ERROR: No Python found with 'build' and 'twine' installed." >&2
    echo "Run: pip install build twine" >&2
    exit 1
fi
echo "Python: $PYTHON ($($PYTHON --version))"

# ── validate version ──────────────────────────────────────────────────────────
# PEP 440: 1.2.3 / 1.2.3rc1 / 1.2.3b2 / 1.2.3a1
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(a|b|rc)[0-9]+$|^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: invalid version '$VERSION'. Use PEP 440 format: 1.2.3 or 1.2.3rc1" >&2
    exit 1
fi

# go version.go uses dashes (1.0.1-rc.2); pip uses no-dash (1.0.1rc2)
# Derive the Go-style version for version.go from the PEP 440 string
GO_VERSION="$VERSION"
if echo "$VERSION" | grep -qE '(a|b|rc)[0-9]+$'; then
    # 1.0.2rc1 → 1.0.2-rc.1  |  1.0.2b2 → 1.0.2-beta.2  |  1.0.2a1 → 1.0.2-alpha.1
    GO_VERSION=$(echo "$VERSION" | sed -E \
        -e 's/([0-9]+)rc([0-9]+)$/\1-rc.\2/' \
        -e 's/([0-9]+)b([0-9]+)$/\1-beta.\2/' \
        -e 's/([0-9]+)a([0-9]+)$/\1-alpha.\2/')
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Version bump"
echo "    PEP 440 (pip):  $VERSION"
echo "    Go (server):    $GO_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Escape for use as a sed replacement string (guards / \ & against any future
# version-format changes that might introduce these characters).
_sed_escape() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
VERSION_ESC="$(_sed_escape "$VERSION")"
GO_VERSION_ESC="$(_sed_escape "$GO_VERSION")"

# ── 1. bump version.go ────────────────────────────────────────────────────────
VERSION_GO="$REPO_ROOT/server/internal/api/version.go"
sed -i "s/const AppVersion = \".*\"/const AppVersion = \"$GO_VERSION_ESC\"/" "$VERSION_GO"
echo "  bumped $VERSION_GO → $GO_VERSION"

# ── 2. bump pyproject.toml ────────────────────────────────────────────────────
PYPROJECT="$REPO_ROOT/packages/python/pyproject.toml"
sed -i "s/^version = \".*\"/version = \"$VERSION_ESC\"/" "$PYPROJECT"
echo "  bumped $PYPROJECT → $VERSION"

# ── 3. bump __init__.py ───────────────────────────────────────────────────────
INIT_PY="$REPO_ROOT/packages/python/src/airgap_devkit/__init__.py"
sed -i "s/__version__ = \".*\"/__version__ = \"$VERSION_ESC\"/" "$INIT_PY"
echo "  bumped $INIT_PY → $VERSION"

# ── 4. build Go binaries ──────────────────────────────────────────────────────
if [[ "$NO_BUILD" == false ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Building Go binaries"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    bash "$REPO_ROOT/scripts/build-server.sh"
else
    echo "  --no-build: skipping Go compile, using existing prebuilt/"
fi

# ── 5. stage binaries ─────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Staging binaries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$REPO_ROOT/packages/python/scripts/stage-binaries.sh"

# ── 6. build wheel ────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building wheel"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
rm -rf "$REPO_ROOT/dist/python/"
"$PYTHON" -m build "$REPO_ROOT/packages/python/" --outdir "$REPO_ROOT/dist/python/"

WHEEL=$(ls "$REPO_ROOT/dist/python/"*.whl 2>/dev/null | head -1)
echo ""
echo "  Built: $WHEEL"
echo "  Size:  $(du -h "$WHEEL" | cut -f1)"

# ── 7. check ──────────────────────────────────────────────────────────────────
echo ""
echo "  Checking with twine..."
"$PYTHON" -m twine check "$REPO_ROOT/dist/python/"*

# ── 8. upload ─────────────────────────────────────────────────────────────────
if [[ "$UPLOAD" == true ]]; then
    echo ""
    if [[ "$TEST_PYPI" == true ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Uploading to TestPyPI"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$PYTHON" -m twine upload --repository testpypi "$REPO_ROOT/dist/python/"*
        echo ""
        echo "  Test install with:"
        echo "    pip install -i https://test.pypi.org/simple/ airgap-devkit==$VERSION"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Uploading to PyPI"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        "$PYTHON" -m twine upload "$REPO_ROOT/dist/python/"*
        echo ""
        echo "  Install with:"
        echo "    pip install airgap-devkit==$VERSION"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done — v$VERSION"
if [[ "$UPLOAD" == false ]]; then
    echo ""
    echo "  To upload to TestPyPI: bash scripts/release.sh $VERSION --no-build --test"
    echo "  To upload to PyPI:     bash scripts/release.sh $VERSION --no-build --upload"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
