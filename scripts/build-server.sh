#!/usr/bin/env bash
# Build the Go devkit server for Windows amd64 and Linux amd64.
# Run from the repo root: bash scripts/build-server.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$REPO_ROOT/server"
OUT_DIR="$REPO_ROOT/prebuilt/bin"

# On MINGW64/Git Bash, Go may live in Program Files but not be on the bash PATH
for _d in "/c/Program Files/Go/bin" "/c/Go/bin" "$HOME/go/bin" "/usr/local/go/bin"; do
  [[ -x "$_d/go" || -x "$_d/go.exe" ]] && export PATH="$PATH:$_d" && break
done

if ! command -v go &>/dev/null; then
  echo "ERROR: 'go' is not on PATH. Install Go 1.21+ to build the server." >&2
  exit 1
fi

GO_VER="$(go version)"
echo "Go: $GO_VER"
echo "Building devkit server → $OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$SERVER_DIR"

# Resolve and download module deps
go mod tidy
go mod download

echo ""
echo "Building devkit-server-linux-amd64 ..."
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o "$OUT_DIR/devkit-server-linux-amd64" .
echo "  → $OUT_DIR/devkit-server-linux-amd64"

echo ""
echo "Building devkit-server-windows-amd64.exe ..."
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o "$OUT_DIR/devkit-server-windows-amd64.exe" .
echo "  → $OUT_DIR/devkit-server-windows-amd64.exe"

echo ""
echo "Build complete."
ls -lh "$OUT_DIR"/devkit-server-*
