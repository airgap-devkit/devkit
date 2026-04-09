#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# dev-tools/conan/setup.sh
#
# Installs Conan 2.27.0 C/C++ package manager for air-gapped environments.
#
# Two install methods:
#   1. Self-contained binary (default) — no Python required. Uses the
#      prebuilt conan executable bundle from conan-io/conan releases.
#
#   2. pip/whl install (--install-via-pip) — installs into the devkit's
#      portable Python venv. Requires languages/python to be installed.
#
# USAGE:
#   bash dev-tools/conan/setup.sh [OPTIONS]
#
# OPTIONS:
#   --install-via-pip    Install from vendored .whl into devkit Python venv
#   --prefix <path>      Override install prefix
#   --rebuild            Force reinstall even if already present
#   -h | --help          Print this help
#
# PLATFORMS:
#   Windows 11  (Git Bash / MINGW64) — self-contained bundle or pip whl
#   RHEL 8 / Linux x86_64            — self-contained tgz or pip whl
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CONAN_VERSION="2.27.0"
TOOL_NAME="conan"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
INSTALL_VIA_PIP=false
REBUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-via-pip) INSTALL_VIA_PIP=true; shift ;;
        --rebuild)         REBUILD=true; shift ;;
        --prefix)          export INSTALL_PREFIX_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^[^#]/{/^#/!q; s/^# \?//; p}' "$0"
            exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Source install-mode library
# ---------------------------------------------------------------------------
source "${REPO_ROOT}/scripts/install-mode.sh"
install_mode_init "${TOOL_NAME}" "${CONAN_VERSION}"
install_log_capture_start

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    Linux*)                OS="linux"   ;;
    *) echo "ERROR: Unsupported platform." >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Check for existing install
# ---------------------------------------------------------------------------
if [[ -f "${INSTALL_RECEIPT}" && "${REBUILD}" == "false" ]]; then
    existing_ver="$(grep "^Version" "${INSTALL_RECEIPT}" 2>/dev/null | awk '{print $3}' || echo "")"
    if [[ "${existing_ver}" == "${CONAN_VERSION}" ]]; then
        echo "  [OK]  Conan ${CONAN_VERSION} already installed at ${INSTALL_PREFIX}"
        echo "        Use --rebuild to force reinstall."
        exit 0
    fi
fi

VENDOR_DIR="${SCRIPT_DIR}/vendor"

# ---------------------------------------------------------------------------
# Method 1: self-contained binary (default)
# ---------------------------------------------------------------------------
_install_binary() {
    local archive conan_bin_src

    case "${OS}" in
        windows)
            archive="${VENDOR_DIR}/conan-${CONAN_VERSION}-windows-x86_64.zip"
            if [[ ! -f "${archive}" ]]; then
                echo "ERROR: Archive not found: ${archive}" >&2
                echo "       Vendor from: https://github.com/conan-io/conan/releases/download/${CONAN_VERSION}/conan-${CONAN_VERSION}-windows-x86_64.zip" >&2
                exit 1
            fi
            echo "  [....] Extracting Conan ${CONAN_VERSION} (Windows)..."
            im_progress_start "Extracting conan Windows bundle"
            mkdir -p "${INSTALL_PREFIX}"
            if command -v 7z &>/dev/null; then
                7z x "${archive}" -o"${INSTALL_PREFIX}" -y > /dev/null
            elif command -v unzip &>/dev/null; then
                unzip -q "${archive}" -d "${INSTALL_PREFIX}"
            else
                echo "ERROR: Need 7z or unzip. Install dev-tools/7zip first." >&2
                exit 1
            fi
            im_progress_stop "Extracted"

            # Locate conan.exe — bundle may place it in a subdir
            local found_exe
            found_exe="$(find "${INSTALL_PREFIX}" -maxdepth 3 -name "conan.exe" | head -1)"
            if [[ -z "${found_exe}" ]]; then
                echo "ERROR: conan.exe not found after extraction." >&2; exit 1
            fi
            mkdir -p "${INSTALL_BIN_DIR}"
            if [[ "$(dirname "${found_exe}")" != "${INSTALL_BIN_DIR}" ]]; then
                # Bundle places everything in one dir — move that dir to bin
                local bundle_dir
                bundle_dir="$(dirname "${found_exe}")"
                cp -r "${bundle_dir}/." "${INSTALL_BIN_DIR}/"
            fi
            ;;

        linux)
            archive="${VENDOR_DIR}/conan-${CONAN_VERSION}-linux-x86_64.tgz"
            if [[ ! -f "${archive}" ]]; then
                echo "ERROR: Archive not found: ${archive}" >&2
                echo "       Vendor from: https://github.com/conan-io/conan/releases/download/${CONAN_VERSION}/conan-${CONAN_VERSION}-linux-x86_64.tgz" >&2
                exit 1
            fi
            echo "  [....] Extracting Conan ${CONAN_VERSION} (Linux)..."
            im_progress_start "Extracting conan Linux bundle"
            mkdir -p "${INSTALL_BIN_DIR}"
            tar -xzf "${archive}" -C "${INSTALL_BIN_DIR}"
            im_progress_stop "Extracted"

            chmod +x "${INSTALL_BIN_DIR}/conan" 2>/dev/null || true
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Method 2: pip / vendored .whl
# ---------------------------------------------------------------------------
_install_pip() {
    # Find the devkit Python venv, or fall back to system Python
    local python_bin=""

    # Prefer devkit portable Python venv
    local devkit_python_venv="${INSTALL_PREFIX_OVERRIDE:-${HOME}/.local/share/airgap-cpp-devkit}/languages/python"
    if [[ -f "${devkit_python_venv}/venv/bin/python" ]]; then
        python_bin="${devkit_python_venv}/venv/bin/python"
    elif command -v python3 &>/dev/null; then
        python_bin="$(command -v python3)"
    elif command -v python &>/dev/null; then
        python_bin="$(command -v python)"
    else
        echo "ERROR: No Python interpreter found." >&2
        echo "       Install languages/python first, or use the binary install (default)." >&2
        exit 1
    fi

    echo "  [OK]  Using Python: ${python_bin}"

    local whl_file="${VENDOR_DIR}/conan-${CONAN_VERSION}-py3-none-any.whl"
    if [[ ! -f "${whl_file}" ]]; then
        echo "ERROR: Vendored whl not found: ${whl_file}" >&2
        echo "       Download from https://pypi.org/project/conan/${CONAN_VERSION}/" >&2
        exit 1
    fi

    echo "  [....] Installing Conan ${CONAN_VERSION} via pip whl..."
    im_progress_start "pip install conan whl"
    "${python_bin}" -m pip install --quiet --no-index "${whl_file}"
    im_progress_stop "pip install complete"

    # Locate the conan script installed by pip
    local pip_conan
    pip_conan="$(dirname "${python_bin}")/conan"
    [[ "${OS}" == "windows" ]] && pip_conan="${pip_conan}.exe"

    mkdir -p "${INSTALL_BIN_DIR}"
    if [[ -f "${pip_conan}" ]]; then
        ln -sf "${pip_conan}" "${INSTALL_BIN_DIR}/conan" 2>/dev/null || \
            cp "${pip_conan}" "${INSTALL_BIN_DIR}/conan"
    fi
}

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
_verify() {
    local conan_bin="${INSTALL_BIN_DIR}/conan"
    [[ "${OS}" == "windows" && ! -f "${conan_bin}" ]] && conan_bin="${INSTALL_BIN_DIR}/conan.exe"

    if [[ ! -f "${conan_bin}" ]]; then
        echo "ERROR: conan not found at ${conan_bin}" >&2
        exit 1
    fi

    local installed_ver
    installed_ver="$("${conan_bin}" --version 2>/dev/null | awk '{print $3}')"
    echo "  [OK]  conan --version: ${installed_ver}"

    if [[ "${installed_ver}" != "${CONAN_VERSION}" ]]; then
        echo "  [!!]  WARNING: Expected ${CONAN_VERSION}, got ${installed_ver}" >&2
    fi
}

# ---------------------------------------------------------------------------
# Initialise Conan home (creates default profile on first run)
# ---------------------------------------------------------------------------
_init_conan_home() {
    local conan_bin="${INSTALL_BIN_DIR}/conan"
    [[ "${OS}" == "windows" && ! -f "${conan_bin}" ]] && conan_bin="${INSTALL_BIN_DIR}/conan.exe"

    echo "  [....] Initialising Conan home (~/.conan2)..."
    # conan profile detect creates default profile from current environment
    "${conan_bin}" profile detect --force 2>/dev/null || true
    echo "  [OK]  Conan home initialised."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
echo "  Installing Conan ${CONAN_VERSION} (${OS})"
echo "  Install mode : ${INSTALL_MODE}  ->  ${INSTALL_PREFIX}"
echo ""

if [[ "${INSTALL_VIA_PIP}" == "true" ]]; then
    _install_pip
else
    _install_binary
fi

_verify
_init_conan_home

install_env_register "${INSTALL_BIN_DIR}"
install_receipt_write "success" "conan:${INSTALL_BIN_DIR}/conan"
install_mode_print_footer "success" "conan:${INSTALL_BIN_DIR}/conan"

echo ""
echo "  Conan ${CONAN_VERSION} installed."
echo "  Restart your shell, or:"
echo "    source \"$(install_env_register "${INSTALL_BIN_DIR}")\""
echo ""
echo "  Quick start:"
echo "    conan --version"
echo "    conan search zlib -r conancenter   # (requires internet)"
echo "    conan install . --build=missing    # (uses local cache)"
echo ""
