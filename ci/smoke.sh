#!/usr/bin/env bash
# Starts the devkit server binary, verifies three API endpoints, then stops it.
# Required env: DEVKIT_BINARY (path to the platform binary)
set -euo pipefail

: "${DEVKIT_BINARY:?DEVKIT_BINARY must be set to the server binary path}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$OSTYPE" == "linux-gnu"* ]] && chmod +x "$DEVKIT_BINARY"
echo '{"setup_complete": true}' > devkit.config.json

"$DEVKIT_BINARY" --tools tools --prebuilt prebuilt --port 8080 --no-browser &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; rm -f devkit.config.json' EXIT

for i in $(seq 1 15); do
  curl -sf http://127.0.0.1:8080/health && echo "Server ready." && break
  [[ $i -eq 15 ]] && { echo "ERROR: server did not become ready" >&2; exit 1; }
  sleep 1
done

TOKEN=$(cat .devkit-token 2>/dev/null || echo "")

curl -sf http://127.0.0.1:8080/health

resp=$(curl -sf -H "X-DevKit-Token: $TOKEN" http://127.0.0.1:8080/api/tools)
count=$(python3 -c "import json,sys; print(len(json.load(sys.stdin)))" <<< "$resp")
echo "Discovered $count tools"
[[ "$count" -gt 0 ]] || { echo "ERROR: /api/tools returned no tools" >&2; exit 1; }

curl -sf -H "X-DevKit-Token: $TOKEN" http://127.0.0.1:8080/api/profiles
echo "Smoke test passed."
