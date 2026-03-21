#!/usr/bin/env bash
# =============================================================================
# scripts/install-mode.sh
# Author: Nima Shafie
#
# PURPOSE: Shared library sourced by all airgap-cpp-devkit bootstrap/setup
#          scripts. Detects whether the current user has admin/root privileges,
#          selects appropriate system-wide or per-user install paths, and
#          provides helpers for install receipt and log file generation.
#
# USAGE:
#   Source this file early in any bootstrap/setup script:
#     source "${REPO_ROOT}/scripts/install-mode.sh"
#     install_mode_init "<tool-name>" "<tool-version>"
#
#   Then use the exported variables:
#     INSTALL_MODE       — "admin" or "user"
#     INSTALL_PREFIX     — root install directory
#     INSTALL_BIN_DIR    — where binaries go
#     INSTALL_LOG_FILE   — full path to the timestamped log file
#     INSTALL_RECEIPT    — full path to the install receipt file
#
#   And the helpers:
#     install_mode_print_header    — print the mode banner
#     install_receipt_write        — write the receipt file
#     install_log_capture_start    — tee all output to log file
#
# INSTALL PATHS:
#
#   Admin (system-wide):
#     Windows : C:\Program Files\airgap-cpp-devkit\<tool>\
#     Linux   : /opt/airgap-cpp-devkit/<tool>/
#
#   User (per-user, no admin required):
#     Windows : %LOCALAPPDATA%\airgap-cpp-devkit\<tool>\
#               (~/.local/share equivalent in Git Bash)
#     Linux   : ~/.local/share/airgap-cpp-devkit/<tool>/
#
#   Log files (always written regardless of install mode):
#     Windows : %TEMP%\airgap-cpp-devkit\logs\
#               (~/AppData/Local/Temp/airgap-cpp-devkit/logs/ in Git Bash)
#     Linux   : /var/log/airgap-cpp-devkit/
#               (falls back to ~/airgap-cpp-devkit-logs/ if not writable)
# =============================================================================

# Guard against double-sourcing
[[ -n "${_INSTALL_MODE_LOADED:-}" ]] && return 0
_INSTALL_MODE_LOADED=1

# ---------------------------------------------------------------------------
# Internal: detect OS
# ---------------------------------------------------------------------------
_im_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Linux*)                echo "linux"   ;;
        Darwin*)               echo "macos"   ;;
        *)                     echo "unknown" ;;
    esac
}

# ---------------------------------------------------------------------------
# Internal: test whether we can write to a system path
# Tries a temp file write — cleaner than checking group membership.
# ---------------------------------------------------------------------------
_im_can_write_system() {
    local test_path="$1"
    mkdir -p "${test_path}" 2>/dev/null || true
    local test_file="${test_path}/.airgap_write_test_$$"
    if touch "${test_file}" 2>/dev/null; then
        rm -f "${test_file}" 2>/dev/null || true
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Internal: resolve Windows %LOCALAPPDATA% in Git Bash
# ---------------------------------------------------------------------------
_im_localappdata() {
    if [[ -n "${LOCALAPPDATA:-}" ]]; then
        cygpath -u "${LOCALAPPDATA}" 2>/dev/null || \
            printf '%s' "${LOCALAPPDATA}" | sed 's|\\|/|g; s|^C:|/c|i'
    else
        echo "${HOME}/AppData/Local"
    fi
}

# ---------------------------------------------------------------------------
# Internal: resolve Windows %TEMP% in Git Bash
# ---------------------------------------------------------------------------
_im_temp_dir() {
    local os="$(_im_os)"
    if [[ "${os}" == "windows" ]]; then
        if [[ -n "${TEMP:-}" ]]; then
            cygpath -u "${TEMP}" 2>/dev/null || \
                printf '%s' "${TEMP}" | sed 's|\\|/|g; s|^C:|/c|i'
        else
            echo "${HOME}/AppData/Local/Temp"
        fi
    else
        echo "/tmp"
    fi
}

# ---------------------------------------------------------------------------
# install_mode_init <tool_name> <tool_version>
#
# Sets all exported variables. Call once at the start of each bootstrap.
# ---------------------------------------------------------------------------
install_mode_init() {
    local tool_name="${1:-unknown}"
    local tool_version="${2:-unknown}"
    local os
    os="$(_im_os)"
    local timestamp
    timestamp="$(date +"%Y%m%d-%H%M%S")"

    # ---- Determine system-wide paths per platform ----
    local sys_prefix user_prefix
    case "${os}" in
        windows)
            # System-wide: C:\Program Files\airgap-cpp-devkit\
            local pf
            pf="$( cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null \
                   || echo "/c/Program Files" )"
            sys_prefix="${pf}/airgap-cpp-devkit/${tool_name}"
            # Per-user: %LOCALAPPDATA%\airgap-cpp-devkit\
            user_prefix="$(_im_localappdata)/airgap-cpp-devkit/${tool_name}"
            ;;
        linux|macos)
            sys_prefix="/opt/airgap-cpp-devkit/${tool_name}"
            user_prefix="${HOME}/.local/share/airgap-cpp-devkit/${tool_name}"
            ;;
        *)
            sys_prefix="/opt/airgap-cpp-devkit/${tool_name}"
            user_prefix="${HOME}/.local/share/airgap-cpp-devkit/${tool_name}"
            ;;
    esac

    # ---- Detect admin capability ----
    if _im_can_write_system "${sys_prefix}"; then
        export INSTALL_MODE="admin"
        export INSTALL_PREFIX="${sys_prefix}"
    else
        export INSTALL_MODE="user"
        export INSTALL_PREFIX="${user_prefix}"
    fi

    export INSTALL_BIN_DIR="${INSTALL_PREFIX}/bin"
    export INSTALL_TOOL_NAME="${tool_name}"
    export INSTALL_TOOL_VERSION="${tool_version}"
    export INSTALL_TIMESTAMP="${timestamp}"
    export INSTALL_OS="${os}"

    # ---- Log file location ----
    local log_base
    case "${os}" in
        windows)
            log_base="$(_im_temp_dir)/airgap-cpp-devkit/logs"
            ;;
        linux|macos)
            if _im_can_write_system "/var/log/airgap-cpp-devkit"; then
                log_base="/var/log/airgap-cpp-devkit"
            else
                log_base="${HOME}/airgap-cpp-devkit-logs"
            fi
            ;;
        *)
            log_base="${HOME}/airgap-cpp-devkit-logs"
            ;;
    esac
    mkdir -p "${log_base}" 2>/dev/null || true
    export INSTALL_LOG_DIR="${log_base}"
    export INSTALL_LOG_FILE="${log_base}/${tool_name}-${timestamp}.log"

    # ---- Receipt file (written inside install prefix) ----
    export INSTALL_RECEIPT="${INSTALL_PREFIX}/INSTALL_RECEIPT.txt"

    # ---- Print the mode banner immediately ----
    install_mode_print_header
}

# ---------------------------------------------------------------------------
# install_mode_print_header
#
# Prints a prominent banner showing install mode and target paths.
# Called automatically by install_mode_init.
# ---------------------------------------------------------------------------
install_mode_print_header() {
    local mode_label scope_label mode_icon
    if [[ "${INSTALL_MODE}" == "admin" ]]; then
        mode_label="SYSTEM-WIDE  (admin / root)"
        scope_label="ALL users on this machine"
        mode_icon="✓"
    else
        mode_label="CURRENT USER ONLY  (no admin rights detected)"
        scope_label="THIS user only — other users will NOT have access"
        mode_icon="⚠"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    printf "║  %-64s║\n" "  airgap-cpp-devkit — Install Mode"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  %-64s║\n" "  Tool        : ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION}"
    printf "║  %-64s║\n" "  Mode        : ${mode_icon}  ${mode_label}"
    printf "║  %-64s║\n" "  Install dir : ${INSTALL_PREFIX}"
    printf "║  %-64s║\n" "  Available to: ${scope_label}"
    printf "║  %-64s║\n" "  Log file    : ${INSTALL_LOG_FILE}"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "${INSTALL_MODE}" == "user" ]]; then
        echo "  ⚠  NOTE: Running without admin/root privileges."
        echo "     Tools will be installed to your personal directory only."
        echo "     To install system-wide for all users, re-run as admin/root:"
        case "${INSTALL_OS}" in
            windows) echo "       Right-click Git Bash → 'Run as administrator'" ;;
            linux)   echo "       sudo bash $(basename "$0")" ;;
        esac
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# install_mode_print_footer <status> [<binary_paths...>]
#
# Prints a final summary box at the end of a bootstrap/setup script.
# Call with "success" or "failure" as the first argument, followed by
# any number of "label:path" pairs for the installed binaries.
#
# Example:
#   install_mode_print_footer "success" \
#       "clang-format:${INSTALL_BIN_DIR}/clang-format" \
#       "clang-tidy:${INSTALL_BIN_DIR}/clang-tidy"
# ---------------------------------------------------------------------------
install_mode_print_footer() {
    local status="${1:-success}"
    shift || true

    local status_label status_icon
    if [[ "${status}" == "success" ]]; then
        status_label="SUCCESS"
        status_icon="✓"
    else
        status_label="FAILED"
        status_icon="✗"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    printf "║  %-64s║\n" "  ${status_icon}  ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION} — ${status_label}"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  %-64s║\n" "  Install mode : ${INSTALL_MODE}"
    printf "║  %-64s║\n" "  Install path : ${INSTALL_PREFIX}"
    for pair in "$@"; do
        local label="${pair%%:*}"
        local path="${pair#*:}"
        printf "║  %-64s║\n" "  ${label} : ${path}"
    done
    echo "╠══════════════════════════════════════════════════════════════════╣"
    printf "║  %-64s║\n" "  Log  : ${INSTALL_LOG_FILE}"
    printf "║  %-64s║\n" "  Receipt : ${INSTALL_RECEIPT}"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "${INSTALL_MODE}" == "user" ]]; then
        echo "  ⚠  Installed to user path — NOT available to other users."
        echo "     Re-run as admin/root to install system-wide."
        echo ""
    fi
}

# ---------------------------------------------------------------------------
# install_receipt_write <status> [<binary_paths...>]
#
# Writes a plain-text audit receipt to INSTALL_RECEIPT.
# Same signature as install_mode_print_footer.
# ---------------------------------------------------------------------------
install_receipt_write() {
    local status="${1:-success}"
    shift || true

    mkdir -p "${INSTALL_PREFIX}" 2>/dev/null || true

    {
        echo "airgap-cpp-devkit — Install Receipt"
        echo "===================================="
        echo ""
        echo "Tool         : ${INSTALL_TOOL_NAME}"
        echo "Version      : ${INSTALL_TOOL_VERSION}"
        echo "Status       : ${status}"
        echo "Install mode : ${INSTALL_MODE}"
        echo "Install path : ${INSTALL_PREFIX}"
        echo "Date         : $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "User         : $(whoami 2>/dev/null || echo unknown)"
        echo "Hostname     : $(hostname 2>/dev/null || echo unknown)"
        echo "OS           : ${INSTALL_OS}"
        echo "Log file     : ${INSTALL_LOG_FILE}"
        echo ""
        if [[ $# -gt 0 ]]; then
            echo "Installed binaries:"
            for pair in "$@"; do
                local label="${pair%%:*}"
                local path="${pair#*:}"
                echo "  ${label} : ${path}"
                if [[ -f "${path}" || -f "${path}.exe" ]]; then
                    local actual_path="${path}"
                    [[ -f "${path}.exe" ]] && actual_path="${path}.exe"
                    local sha256
                    sha256="$(sha256sum "${actual_path}" 2>/dev/null | awk '{print $1}' || echo "unavailable")"
                    echo "    SHA256 : ${sha256}"
                fi
            done
        fi
        echo ""
        echo "Available to all users : $([[ "${INSTALL_MODE}" == "admin" ]] && echo "YES" || echo "NO — current user only")"
        echo ""
        if [[ "${INSTALL_MODE}" == "user" ]]; then
            echo "WARNING: This installation is only accessible to the current user."
            echo "         To make available system-wide, re-run as admin/root."
        fi
    } > "${INSTALL_RECEIPT}" 2>/dev/null || {
        echo "[install-mode] WARNING: Could not write receipt to ${INSTALL_RECEIPT}" >&2
    }

    echo "[install-mode] Receipt written: ${INSTALL_RECEIPT}"
}

# ---------------------------------------------------------------------------
# install_log_capture_start
#
# Redirects all subsequent stdout/stderr to both the terminal and the log
# file using a background tee process. Call once near the start of a script
# after install_mode_init.
#
# Note: This uses exec redirection — it affects the entire calling script.
# ---------------------------------------------------------------------------
install_log_capture_start() {
    mkdir -p "${INSTALL_LOG_DIR}" 2>/dev/null || true

    # Write a log header
    {
        echo "airgap-cpp-devkit — Install Log"
        echo "================================"
        echo "Tool      : ${INSTALL_TOOL_NAME} ${INSTALL_TOOL_VERSION}"
        echo "Mode      : ${INSTALL_MODE}"
        echo "Prefix    : ${INSTALL_PREFIX}"
        echo "Date      : $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "User      : $(whoami 2>/dev/null || echo unknown)"
        echo "Hostname  : $(hostname 2>/dev/null || echo unknown)"
        echo "================================"
        echo ""
    } >> "${INSTALL_LOG_FILE}" 2>/dev/null || true

    # Tee stdout and stderr to the log file
    # Use a named pipe + background process to avoid subshell issues
    exec > >(tee -a "${INSTALL_LOG_FILE}") 2>&1

    echo "[install-mode] Logging to: ${INSTALL_LOG_FILE}"
    echo ""
}