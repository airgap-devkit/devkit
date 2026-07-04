#!/usr/bin/env bash
# Author: Nima Shafie
# =============================================================================
# serve.sh -- host the DevKit Manager for a whole team (Mode 1: shared server)
#
# Runs the devkit-ui bound to a network interface so team members can reach it
# from their own machines, prints the token-authenticated access URL to share,
# and (optionally) enables HTTPS. Tools installed through this server land on
# THIS host — see docs/DEPLOYMENT.md for the shared-host model.
#
# For a single user with no admin rights, use scripts/launch.sh instead
# (localhost, per-user install). See docs/DEPLOYMENT.md Mode 2.
#
# USAGE:
#   bash scripts/serve.sh                       # bind 0.0.0.0, auto-detect URL
#   bash scripts/serve.sh --port 9090 --tls     # HTTPS on a custom port
#   bash scripts/serve.sh --advertise devbox.corp.local
#
# OPTIONS:
#   --host <addr>       Interface to bind (default: 0.0.0.0 = all interfaces)
#   --advertise <name>  Hostname/IP to put in the shared URL
#                       (default: auto-detected LAN address)
#   --port <n>          Port (default: devkit.config.json port, else 9090)
#   --tls               Serve HTTPS with an auto-generated self-signed cert
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BIND_HOST="0.0.0.0"
ADVERTISE=""
PORT=""
TLS=false
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)      BIND_HOST="$2"; shift 2 ;;
        --advertise) ADVERTISE="$2"; shift 2 ;;
        --port)      PORT="$2"; shift 2 ;;
        --tls)       TLS=true; shift ;;
        -h|--help)   grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           PASS_ARGS+=("$1"); shift ;;
    esac
done

# --- Effective port: --port > config > 9090 -------------------------------
if [[ -z "$PORT" ]]; then
    PORT="$(grep -oE '"port"[[:space:]]*:[[:space:]]*[0-9]+' "${REPO_ROOT}/devkit.config.json" 2>/dev/null \
        | grep -oE '[0-9]+$' | head -1)"
    PORT="${PORT:-9090}"
fi

# --- Ensure a stable auth token exists so we can print the URL up front ----
TOKEN_FILE="${REPO_ROOT}/.devkit-token"
if [[ ! -s "$TOKEN_FILE" ]]; then
    if command -v openssl &>/dev/null; then
        TOKEN="$(openssl rand -hex 32)"
    elif [[ -r /dev/urandom ]]; then
        TOKEN="$(head -c32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    else
        echo "ERROR: cannot generate a token (no openssl or /dev/urandom)." >&2; exit 1
    fi
    printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null || true
fi
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

# --- Figure out a reachable address for the shared URL --------------------
detect_ip() {
    local ip=""
    if command -v hostname &>/dev/null && hostname -I >/dev/null 2>&1; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
        ip="$(ipconfig 2>/dev/null | grep -iE 'IPv4' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | grep -v '^127\.' | head -1)"
    fi
    [[ -z "$ip" ]] && ip="$(hostname 2>/dev/null || echo '<server-address>')"
    echo "$ip"
}
[[ -z "$ADVERTISE" ]] && ADVERTISE="$(detect_ip)"

SCHEME="http"; $TLS && SCHEME="https"
ACCESS_URL="${SCHEME}://${ADVERTISE}:${PORT}/auth/bootstrap?devkit_token=${TOKEN}&next=/"

echo ""
echo "================================================================================"
echo "  airgap-cpp-devkit -- Team Server (Mode 1)"
echo "================================================================================"
echo "  Binding    : ${BIND_HOST}:${PORT}   (${SCHEME})"
echo "  Share this with your team (token-authenticated, one click):"
echo ""
echo "      ${ACCESS_URL}"
echo ""
echo "  Notes:"
echo "   - Tools installed via this UI land on THIS host (shared-host model)."
echo "   - The token above grants access. Rotate by deleting .devkit-token."
$TLS || echo "   - Unencrypted HTTP. Add --tls for HTTPS on untrusted networks."
echo "   - Ctrl+C to stop."
echo "================================================================================"
echo ""

LAUNCH_ARGS=(--host "$BIND_HOST" --port "$PORT" --no-browser)
$TLS && LAUNCH_ARGS+=(--tls)
exec bash "${SCRIPT_DIR}/launch.sh" "${LAUNCH_ARGS[@]}" "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}"
