#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/sqlite/setup.sh
#
# Installs the SQLite 3.53.0 CLI binary for Windows and Linux.
# The sqlite3 Python module is already built into Python 3.14.4 -- this
# script installs only the standalone sqlite3 CLI for database inspection.
#
# USAGE:
#   bash dev-tools/sqlite/setup.sh [--prefix <path>] [--rebuild]
#
# OPTIONS:
#   --prefix <path>   Install to a custom path instead of auto-detected default
#   --rebuild         Force reinstall even if already present
#
# PLATFORMS:
#   Windows 11  (Git Bash / MINGW64) -- sqlite3.exe
#   RHEL 8 / Linux x86_64            -- sqlite3
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
VERSION="3.53.0"
REBUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)  export INSTALL_PREFIX_OVERRIDE="$2"; shift 2 ;;
    --rebuild) REBUILD=true; shift ;;
    -h|--help)
      sed -n '2,/^[^#]/{/^#/!q; s/^# \?//; p}' "$0"
      exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  Linux*)                OS="linux"   ;;
  *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "sqlite" "${VERSION}"
install_log_capture_start

echo ""
echo "============================================================"
echo " SQLite ${VERSION} -- CLI Setup"
echo " Platform    : ${OS}"
echo " Install mode: ${INSTALL_MODE}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Already installed check
# ---------------------------------------------------------------------------
SQLITE_BIN="${INSTALL_BIN_DIR}/sqlite3"
[[ "${OS}" == "windows" ]] && SQLITE_BIN="${INSTALL_BIN_DIR}/sqlite3.exe"

if [[ -f "${SQLITE_BIN}" && "${REBUILD}" == "false" ]]; then
  existing_ver="$("${SQLITE_BIN}" --version 2>/dev/null | awk '{print $1}' || echo "")"
  echo "  [OK]  SQLite CLI already installed: ${existing_ver}"
  echo "        Use --rebuild to force reinstall."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1: Verify archive
# ---------------------------------------------------------------------------
im_progress_start "Verifying vendor archive"
bash "${SCRIPTS_DIR}/verify.sh"
im_progress_stop "Verification complete"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Install
# ---------------------------------------------------------------------------
im_progress_start "Installing SQLite ${VERSION} CLI"
if [[ "${OS}" == "windows" ]]; then
  bash "${SCRIPTS_DIR}/install-windows.sh" "${INSTALL_MODE}" "${INSTALL_PREFIX_OVERRIDE:-}"
else
  bash "${SCRIPTS_DIR}/install-linux.sh" "${INSTALL_MODE}" "${INSTALL_PREFIX_OVERRIDE:-}"
fi
im_progress_stop "Installation complete"

# ---------------------------------------------------------------------------
# Register PATH, write receipt
# ---------------------------------------------------------------------------
install_env_register "${INSTALL_BIN_DIR}"
install_receipt_write "success" "sqlite3:${SQLITE_BIN}"
install_mode_print_footer "success" "sqlite3:${SQLITE_BIN}"

echo "  Verify with:"
echo "    sqlite3 --version"
echo "    sqlite3 :memory: 'SELECT sqlite_version();'"
echo ""