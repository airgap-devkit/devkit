#!/usr/bin/env bash
# Sign the devkit server binaries.
#
# Windows PE (Authenticode): osslsigncode — requires CODESIGN_CERT + CODESIGN_PASSWD
# Linux binary (GPG):        gpg          — requires GPG_KEY_ID
#
# Usage:
#   bash scripts/sign-binaries.sh [--windows-only] [--linux-only]
#
# Env vars (both are optional; missing means that target is skipped with a warning):
#   CODESIGN_CERT    absolute path to a PKCS#12 (.pfx/.p12) certificate file
#   CODESIGN_PASSWD  passphrase for the PKCS#12 file
#   GPG_KEY_ID       key fingerprint or e-mail address in the local GPG keyring
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$REPO_ROOT/prebuilt/bin"

WIN_EXE="$BIN_DIR/devkit-server-windows-amd64.exe"
LINUX_BIN="$BIN_DIR/devkit-server-linux-amd64"

WINDOWS_ONLY=false
LINUX_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --windows-only) WINDOWS_ONLY=true ;;
        --linux-only)   LINUX_ONLY=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

_warn() { echo "  [WARN] $*" >&2; }
_info() { echo "  $*"; }
_ok()   { echo "  [OK]   $*"; }
_fail() { echo "  [FAIL] $*" >&2; exit 1; }

# ── Auto-discover osslsigncode from devkit install prefix ─────────────────────
# Handles the common case where the tool was installed via the devkit but the
# user hasn't yet sourced the env.sh PATH update in their current shell.
if ! command -v osslsigncode &>/dev/null; then
    _DEVKIT_OSSL="${LOCALAPPDATA:-$HOME/AppData/Local}/airgap-cpp-devkit/osslsigncode/bin"
    if [[ -f "$_DEVKIT_OSSL/osslsigncode.exe" || -f "$_DEVKIT_OSSL/osslsigncode" ]]; then
        export PATH="$_DEVKIT_OSSL:$PATH"
    fi
fi

# ── Windows Authenticode ──────────────────────────────────────────────────────
sign_windows() {
    _info "Signing Windows PE binary ..."

    if [[ -z "${CODESIGN_CERT:-}" ]]; then
        _warn "CODESIGN_CERT not set — skipping Authenticode signing"
        return 0
    fi
    if [[ -z "${CODESIGN_PASSWD:-}" ]]; then
        _warn "CODESIGN_PASSWD not set — skipping Authenticode signing"
        return 0
    fi
    if [[ ! -f "$WIN_EXE" ]]; then
        _fail "Windows binary not found: $WIN_EXE"
    fi

    local signed_tmp="$WIN_EXE.signed"

    if command -v osslsigncode &>/dev/null; then
        _info "Tool: osslsigncode ($(osslsigncode --version 2>&1 | head -1))"
        osslsigncode sign \
            -pkcs12 "$CODESIGN_CERT" \
            -pass   "$CODESIGN_PASSWD" \
            -n      "airgap-devkit server" \
            -i      "https://github.com/airgap-devkit/airgap-devkit" \
            -ts     "http://timestamp.digicert.com" \
            -h      sha256 \
            -in     "$WIN_EXE" \
            -out    "$signed_tmp"
        mv "$signed_tmp" "$WIN_EXE"
        _ok "Authenticode applied (osslsigncode): $(basename "$WIN_EXE")"

    elif command -v signtool.exe &>/dev/null || command -v signtool &>/dev/null; then
        local _st
        _st=$(command -v signtool.exe 2>/dev/null || command -v signtool)
        _info "Tool: signtool (Windows SDK)"
        "$_st" sign \
            /fd sha256 \
            /f  "$CODESIGN_CERT" \
            /p  "$CODESIGN_PASSWD" \
            /d  "airgap-devkit server" \
            /du "https://github.com/airgap-devkit/airgap-devkit" \
            /tr "http://timestamp.digicert.com" \
            /td sha256 \
            "$WIN_EXE"
        _ok "Authenticode applied (signtool): $(basename "$WIN_EXE")"
    else
        _warn "Neither osslsigncode nor signtool found — skipping Authenticode signing"
        _warn "Install: apt-get install osslsigncode  (or use the Windows SDK signtool)"
    fi
}

# ── Linux GPG detached signature ──────────────────────────────────────────────
sign_linux() {
    _info "Signing Linux binary with GPG ..."

    if [[ -z "${GPG_KEY_ID:-}" ]]; then
        _warn "GPG_KEY_ID not set — skipping GPG signing"
        return 0
    fi
    if [[ ! -f "$LINUX_BIN" ]]; then
        _fail "Linux binary not found: $LINUX_BIN"
    fi
    if ! command -v gpg &>/dev/null; then
        _warn "gpg not found — skipping GPG signing"
        return 0
    fi

    rm -f "$LINUX_BIN.sig"
    gpg --batch --yes \
        --local-user "$GPG_KEY_ID" \
        --detach-sign \
        --armor \
        --output "$LINUX_BIN.sig" \
        "$LINUX_BIN"
    _ok "GPG detached signature: $(basename "$LINUX_BIN").sig"

    # Export the public key so downstream verifiers have it alongside the binary
    local pubkey="$BIN_DIR/devkit-signing-key.asc"
    gpg --batch --yes --armor --export "$GPG_KEY_ID" > "$pubkey"
    _ok "Public key exported: $(basename "$pubkey")"
}

# ── main ──────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Code signing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$LINUX_ONLY"   == false ]] && sign_windows
[[ "$WINDOWS_ONLY" == false ]] && sign_linux

echo ""
echo "  Signing complete."
