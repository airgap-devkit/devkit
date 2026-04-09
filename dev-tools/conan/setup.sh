#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/conan/setup.sh
#
# Installs Conan 2.27.0 C/C++ package manager for air-gapped environments.
# Uses self-contained prebuilt executables -- no Python required.
#
# USAGE:
#   bash dev-tools/conan/setup.sh [--prefix <path>] [--rebuild]
#
# OPTIONS:
#   --prefix <path>   Install to a custom path instead of auto-detected default
#   --rebuild         Force reinstall even if already present
#
# INSTALL MODES (auto-detected via scripts/install-mode.sh):
#   admin   /opt/airgap-cpp-devkit/conan/              (Linux)
#           C:\Program Files\airgap-cpp-devkit\conan\  (Windows)
#   user    ~/.local/share/airgap-cpp-devkit/conan/    (Linux)
#           %LOCALAPPDATA%\airgap-cpp-devkit\conan\    (Windows)
#
# PLATFORMS:
#   Windows 11  (Git Bash / MINGW64)
#   RHEL 8 / Linux x86_64
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

VERSION="2.27.0"
PREFIX_OVERRIDE=""
REBUILD=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)  PREFIX_OVERRIDE="$2"; shift 2 ;;
    --rebuild) REBUILD=true; shift ;;
    -h|--help)
      sed -n '2,/^[^#]/{/^#/!q; s/^# \?//; p}' "$0"
      exit 0 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
  Linux*)                OS="linux"   ;;
  *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

source "${REPO_ROOT}/scripts/install-mode.sh"
[[ -n "${PREFIX_OVERRIDE}" ]] && export INSTALL_PREFIX_OVERRIDE="${PREFIX_OVERRIDE}"
install_mode_init "conan" "${VERSION}"
install_log_capture_start

echo ""
echo "============================================================"
echo " Conan ${VERSION} -- Setup"
echo " C/C++ package manager (self-contained, no Python required)"
echo " Platform    : ${OS}"
echo " Install mode: ${INSTALL_MODE}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Already installed check
# ---------------------------------------------------------------------------
CONAN_BIN="${INSTALL_BIN_DIR}/conan"
[[ "${OS}" == "windows" ]] && CONAN_BIN="${INSTALL_BIN_DIR}/conan.exe"

if [[ -f "${CONAN_BIN}" && "${REBUILD}" == "false" ]]; then
  existing_ver="$("${CONAN_BIN}" --version 2>/dev/null | awk '{print $3}' || echo "")"
  if [[ "${existing_ver}" == "${VERSION}" ]]; then
    echo "  [OK]  Conan ${VERSION} already installed at ${INSTALL_PREFIX}"
    echo "        Use --rebuild to force reinstall."
    exit 0
  fi
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
im_progress_start "Installing Conan ${VERSION}"
if [[ "${OS}" == "windows" ]]; then
  bash "${SCRIPTS_DIR}/install-windows.sh" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
else
  bash "${SCRIPTS_DIR}/install-linux.sh" "${INSTALL_MODE}" "${PREFIX_OVERRIDE}"
fi
im_progress_stop "Installation complete"

# ---------------------------------------------------------------------------
# Step 3: Initialise default profile
# ---------------------------------------------------------------------------
if [[ -f "${CONAN_BIN}" ]]; then
  im_progress_start "Initialising Conan default profile"
  "${CONAN_BIN}" profile detect --force 2>/dev/null || true
  im_progress_stop "Profile ready"
fi

# ---------------------------------------------------------------------------
# Register PATH, write receipt
# ---------------------------------------------------------------------------
install_env_register "${INSTALL_BIN_DIR}"
install_receipt_write "success" \
  "conan:${CONAN_BIN}" \
  "version:${VERSION}" \
  "mode:${INSTALL_MODE}"

install_mode_print_footer "success" "conan:${CONAN_BIN}"

echo "  Restart your shell or source env.sh, then:"
echo "    conan --version"
echo "    conan profile show"
echo ""