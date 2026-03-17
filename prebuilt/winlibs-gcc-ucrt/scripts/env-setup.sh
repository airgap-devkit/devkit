#!/usr/bin/env bash
# =============================================================================
# prebuilt/winlibs-gcc-ucrt/scripts/env-setup.sh
#
# PURPOSE: Add the WinLibs GCC UCRT toolchain to the current shell session.
#          Source this file — do not execute it.
#
# USAGE:
#   source scripts/env-setup.sh [x86_64|i686] [install_dir]
#
#   Both arguments default to the same values used by install.sh.
#
# EXAMPLE (after install):
#   source prebuilt/winlibs-gcc-ucrt/scripts/env-setup.sh
#   source prebuilt/winlibs-gcc-ucrt/scripts/env-setup.sh x86_64 /opt/winlibs
#
# PARALLEL TOOLCHAINS:
#   This script prepends to PATH, so the WinLibs GCC takes priority over any
#   system GCC while this session is active. Open a new shell to reset.
# =============================================================================

_winlibs_setup() {
  local SCRIPT_DIR
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local MODULE_ROOT
  MODULE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

  local ARCH="${1:-x86_64}"
  local INSTALL_DIR="${2:-${MODULE_ROOT}/toolchain/${ARCH}}"

  local EXTRACT_ROOT
  if [[ "${ARCH}" == "x86_64" ]]; then
    EXTRACT_ROOT="mingw64"
  elif [[ "${ARCH}" == "i686" ]]; then
    EXTRACT_ROOT="mingw32"
  else
    echo "[env-setup] ERROR: Unknown arch '${ARCH}'. Use 'x86_64' or 'i686'." >&2
    return 1
  fi

  local BIN_DIR="${INSTALL_DIR}/${EXTRACT_ROOT}/bin"

  if [[ ! -d "${BIN_DIR}" ]]; then
    echo "[env-setup] ERROR: Toolchain bin dir not found: ${BIN_DIR}" >&2
    echo "[env-setup]        Run install.sh first." >&2
    return 1
  fi

  # Prepend to PATH (idempotent — skip if already present)
  case ":${PATH}:" in
    *":${BIN_DIR}:"*)
      echo "[env-setup] Already on PATH: ${BIN_DIR}" ;;
    *)
      export PATH="${BIN_DIR}:${PATH}"
      echo "[env-setup] Added to PATH: ${BIN_DIR}" ;;
  esac

  # Export env vars for downstream scripts (e.g. CMake toolchain files)
  export WINLIBS_GCC_ROOT="${INSTALL_DIR}/${EXTRACT_ROOT}"
  export WINLIBS_GCC_BIN="${BIN_DIR}"
  export WINLIBS_GCC_ARCH="${ARCH}"
  export WINLIBS_GCC_VERSION="15.2.0"
  export WINLIBS_MINGW_VERSION="13.0.0"
  export WINLIBS_CRT="ucrt"

  echo "[env-setup] WINLIBS_GCC_ROOT=${WINLIBS_GCC_ROOT}"
  echo "[env-setup] Toolchain active. Verify with: gcc --version"
}

_winlibs_setup "$@"
unset -f _winlibs_setup
