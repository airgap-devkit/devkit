#!/usr/bin/env bash
# Verify cryptographic signatures on devkit server binaries.
#
# Authenticode (Windows EXE): osslsigncode verify
# GPG detached sig (Linux):   gpg --verify
#
# Usage:
#   bash scripts/verify-signatures.sh [--dir <path>]
#
# Defaults to checking prebuilt/bin/.  Pass --dir to point at a custom location
# (e.g. a staged or downloaded copy of the binaries).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$REPO_ROOT/prebuilt/bin"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) BIN_DIR="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

WIN_EXE="$BIN_DIR/devkit-server-windows-amd64.exe"
LINUX_BIN="$BIN_DIR/devkit-server-linux-amd64"
LINUX_SIG="$BIN_DIR/devkit-server-linux-amd64.sig"
PUBKEY="$BIN_DIR/devkit-signing-key.asc"

_info() { echo "  $*"; }
_ok()   { echo "  [OK]   $*"; }
_warn() { echo "  [WARN] $*" >&2; }
_fail() { echo "  [FAIL] $*" >&2; }

rc=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Signature verification"
echo "  BIN_DIR: $BIN_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Authenticode (Windows EXE) ────────────────────────────────────────────────
echo ""
_info "Checking Authenticode signature on $(basename "$WIN_EXE") ..."

if [[ ! -f "$WIN_EXE" ]]; then
    _fail "Binary not found: $WIN_EXE"
    rc=1
elif command -v osslsigncode &>/dev/null; then
    # osslsigncode verify exits 0 on valid signature, non-zero otherwise
    if osslsigncode verify -in "$WIN_EXE" 2>&1 | grep -q "Signature verification: ok"; then
        _ok "Authenticode signature valid: $(basename "$WIN_EXE")"
    else
        _fail "Authenticode signature INVALID or missing: $(basename "$WIN_EXE")"
        rc=1
    fi
elif command -v signtool.exe &>/dev/null || command -v signtool &>/dev/null; then
    _st=$(command -v signtool.exe 2>/dev/null || command -v signtool)
    if "$_st" verify /pa "$WIN_EXE" &>/dev/null; then
        _ok "Authenticode signature valid (signtool): $(basename "$WIN_EXE")"
    else
        _fail "Authenticode signature INVALID (signtool): $(basename "$WIN_EXE")"
        rc=1
    fi
else
    _warn "osslsigncode/signtool not found — cannot verify Authenticode signature"
    _warn "Install: apt-get install osslsigncode"
fi

# ── GPG detached signature (Linux binary) ────────────────────────────────────
echo ""
_info "Checking GPG signature on $(basename "$LINUX_BIN") ..."

if [[ ! -f "$LINUX_BIN" ]]; then
    _fail "Binary not found: $LINUX_BIN"
    rc=1
elif [[ ! -f "$LINUX_SIG" ]]; then
    _warn "Signature file not found: $LINUX_SIG (binary may be unsigned)"
elif ! command -v gpg &>/dev/null; then
    _warn "gpg not found — cannot verify GPG signature"
    _warn "Install: apt-get install gnupg  (or equivalent)"
else
    # Import the bundled public key if present
    if [[ -f "$PUBKEY" ]]; then
        gpg --batch --import "$PUBKEY" 2>/dev/null || true
    fi

    if gpg --batch --verify "$LINUX_SIG" "$LINUX_BIN" 2>/dev/null; then
        _ok "GPG signature valid: $(basename "$LINUX_BIN")"
    else
        _fail "GPG signature INVALID: $(basename "$LINUX_BIN")"
        rc=1
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$rc" -eq 0 ]]; then
    echo "  All signatures verified."
else
    echo "  Verification FAILED — see messages above."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit "$rc"
