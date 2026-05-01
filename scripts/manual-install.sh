#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# scripts/manual-install.sh
#
# PURPOSE: Fallback installer for when the devkit-ui web application cannot
#          complete an installation due to OS integration errors or permission
#          issues.  Works entirely offline using the prebuilt/ submodule.
#          Runs in Git Bash (MINGW64) on Windows and in bash on Linux.
#
# USAGE:
#   bash scripts/manual-install.sh --list
#   bash scripts/manual-install.sh --tool cmake
#   bash scripts/manual-install.sh --tool toolchains/llvm
#   bash scripts/manual-install.sh --tool toolchains/llvm --prefix /c/tools/llvm
#   bash scripts/manual-install.sh --tool toolchains/llvm --verify-only
#
# PLATFORMS:
#   Windows — run in Git Bash (MINGW64), not PowerShell or cmd.exe
#   Linux   — run in bash; use sudo for system-wide installs
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="$REPO_ROOT/tools"
PREBUILT_DIR="${PREBUILT_DIR:-$REPO_ROOT/prebuilt}"

TOOL_ID=""
CUSTOM_PREFIX=""
VERIFY_ONLY=false
LIST_TOOLS=false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_usage() {
    cat <<'HELP'
Usage: bash scripts/manual-install.sh [OPTIONS]

Fallback installer for when the devkit-ui web application cannot complete an
installation.  Runs entirely offline using the prebuilt/ binaries.

OPTIONS
  --list, -l              List all available tools and their IDs
  --tool, -t <id>         Tool ID to install (e.g. cmake, toolchains/llvm)
  --prefix, -p <path>     Custom install prefix (overrides the default)
  --verify-only           Verify split-archive parts are present; do not install
  --help, -h              Show this help text

EXAMPLES
  bash scripts/manual-install.sh --list
  bash scripts/manual-install.sh --tool cmake
  bash scripts/manual-install.sh --tool toolchains/llvm
  bash scripts/manual-install.sh --tool toolchains/llvm --prefix /c/tools/llvm
  bash scripts/manual-install.sh --tool toolchains/llvm --verify-only

NOTES
  • Run from the devkit root directory (the folder containing launch.sh), OR
    from anywhere — the script locates the repo root automatically.
  • On Windows, use Git Bash (MINGW64).  PowerShell and cmd.exe are NOT supported.
  • On Linux, run as root for a system-wide install (/opt/airgap-cpp-devkit/).
    Without root the default is a per-user install (~/.local/share/airgap-cpp-devkit/).
  • If the prebuilt/ submodule is empty, initialise it first:
      git submodule update --init prebuilt
HELP
}

_die()  { echo "ERROR: $*" >&2; exit 1; }
_info() { echo "==> $*"; }
_ok()   { echo "    ✓ $*"; }
_warn() { echo "    ⚠ $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool|-t)      TOOL_ID="$2";       shift 2 ;;
        --prefix|-p)    CUSTOM_PREFIX="$2"; shift 2 ;;
        --verify-only)  VERIFY_ONLY=true;   shift   ;;
        --list|-l)      LIST_TOOLS=true;    shift   ;;
        --help|-h)      _usage; exit 0      ;;
        *) _die "Unknown option: $1.  Run with --help for usage." ;;
    esac
done

# ---------------------------------------------------------------------------
# Locate a tool's devkit.json by scanning tools/ for matching "id" field
# ---------------------------------------------------------------------------
_find_devkit_json() {
    local target="$1"
    # Use find + grep rather than jq (jq is not a guaranteed dependency)
    while IFS= read -r -d '' f; do
        local id
        id=$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | \
             head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [[ "$id" == "$target" ]]; then
            echo "$f"
            return 0
        fi
    done < <(find "$TOOLS_DIR" -name "devkit.json" -print0 2>/dev/null)
    return 1
}

_get_json_field() {
    local file="$1" field="$2"
    grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | \
        head -1 | sed "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/"
}

# ---------------------------------------------------------------------------
# --list: print all available tools
# ---------------------------------------------------------------------------
if [[ "$LIST_TOOLS" == "true" ]]; then
    _info "Available tools:"
    while IFS= read -r -d '' f; do
        local_id=$(_get_json_field "$f" "id" 2>/dev/null || true)
        local_name=$(_get_json_field "$f" "name" 2>/dev/null || true)
        local_ver=$(_get_json_field "$f" "version" 2>/dev/null || true)
        [[ -z "$local_id" ]] && continue
        printf "    %-30s %s %s\n" "$local_id" "$local_name" "${local_ver:+(v$local_ver)}"
    done < <(find "$TOOLS_DIR" -name "devkit.json" -print0 2>/dev/null | sort -z)
    echo ""
    echo "Install a tool with:  bash scripts/manual-install.sh --tool <id>"
    exit 0
fi

# ---------------------------------------------------------------------------
# --tool: validate and resolve
# ---------------------------------------------------------------------------
[[ -z "$TOOL_ID" ]] && { _usage; exit 1; }

DEVKIT_JSON=$(_find_devkit_json "$TOOL_ID") || \
    _die "Tool '$TOOL_ID' not found.  Run --list to see available tools."

TOOL_DIR="$(dirname "$DEVKIT_JSON")"
SETUP_SCRIPT_REL=$(_get_json_field "$DEVKIT_JSON" "setup")
SETUP_SCRIPT_REL="${SETUP_SCRIPT_REL:-setup.sh}"

# Resolve the setup script path (relative to tool dir or repo root)
if [[ -f "$TOOL_DIR/$SETUP_SCRIPT_REL" ]]; then
    SETUP_SCRIPT="$TOOL_DIR/$SETUP_SCRIPT_REL"
elif [[ -f "$REPO_ROOT/$SETUP_SCRIPT_REL" ]]; then
    SETUP_SCRIPT="$REPO_ROOT/$SETUP_SCRIPT_REL"
else
    _die "setup script not found: $SETUP_SCRIPT_REL (searched relative to $TOOL_DIR and $REPO_ROOT)"
fi

TOOL_NAME=$(_get_json_field "$DEVKIT_JSON" "name")
TOOL_VER=$(_get_json_field "$DEVKIT_JSON" "version")
USES_PREBUILT=$(_get_json_field "$DEVKIT_JSON" "uses_prebuilt" 2>/dev/null || echo "")

_info "Tool      : ${TOOL_NAME:-$TOOL_ID} ${TOOL_VER:+(v$TOOL_VER)}"
_info "Setup     : $SETUP_SCRIPT"

# ---------------------------------------------------------------------------
# Prebuilt directory resolution
# ---------------------------------------------------------------------------
if [[ "${USES_PREBUILT,,}" == "true" ]]; then
    if [[ ! -d "$PREBUILT_DIR" ]]; then
        _warn "Prebuilt directory not found: $PREBUILT_DIR"
        echo ""
        echo "    The prebuilt/ submodule may not be initialised.  Run:"
        echo "      git submodule update --init prebuilt"
        echo "    from the devkit root, then retry."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# --verify-only: check that all split-archive part files are present
# ---------------------------------------------------------------------------
if [[ "$VERIFY_ONLY" == "true" ]]; then
    _info "Verifying prebuilt parts for $TOOL_ID..."

    # Derive the expected prebuilt subdirectory from the tool directory
    # e.g. TOOL_DIR = /repo/tools/toolchains/llvm → subpath = toolchains/llvm
    REL_TOOL_DIR="${TOOL_DIR#$TOOLS_DIR/}"
    PARTS_DIR="$PREBUILT_DIR/$REL_TOOL_DIR/${TOOL_VER}"

    if [[ ! -d "$PARTS_DIR" ]]; then
        _warn "No prebuilt directory at: $PARTS_DIR"
        exit 1
    fi

    PART_COUNT=$(find "$PARTS_DIR" -name "*.part-*" 2>/dev/null | wc -l)
    if [[ "$PART_COUNT" -gt 0 ]]; then
        _ok "Found $PART_COUNT split-archive part(s) in $PARTS_DIR"
        find "$PARTS_DIR" -name "*.part-*" | sort | while read -r pf; do
            echo "      $(basename "$pf")"
        done
    else
        ARCHIVE_COUNT=$(find "$PARTS_DIR" -name "*.tar.*" -o -name "*.zip" -o -name "*.tgz" 2>/dev/null | wc -l)
        if [[ "$ARCHIVE_COUNT" -gt 0 ]]; then
            _ok "Found $ARCHIVE_COUNT archive(s) — not split, single-file install"
        else
            _warn "No archives or part files found in $PARTS_DIR"
            exit 1
        fi
    fi

    _ok "Verification complete — all parts present."
    exit 0
fi

# ---------------------------------------------------------------------------
# Install: build environment and delegate to setup.sh
# ---------------------------------------------------------------------------
_info "Running setup script..."
echo ""

# Build the same environment variables that the Go server passes to setup.sh
export PREBUILT_DIR
export INSTALL_PREFIX_OVERRIDE="${CUSTOM_PREFIX:-}"

# Detect OS
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" || \
      "${OS:-}"     == "Windows_NT" || "$(uname -s 2>/dev/null)" == MINGW* ]]; then
    export AIRGAP_OS="windows"
else
    export AIRGAP_OS="linux"
fi

# Build extra args
EXTRA_ARGS=()
if [[ -n "$CUSTOM_PREFIX" ]]; then
    EXTRA_ARGS=("--prefix" "$CUSTOM_PREFIX")
fi

bash "$SETUP_SCRIPT" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"

echo ""
_ok "Done.  If this tool adds binaries to a new directory, restart your"
echo "    terminal (or source the env.sh in the install prefix) so the"
echo "    new PATH takes effect."
