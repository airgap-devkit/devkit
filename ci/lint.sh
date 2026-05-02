#!/usr/bin/env bash
# Syntax-checks every tracked shell script; runs shellcheck when available.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail=0
while IFS= read -r -d '' script; do
  bash -n "$script" || { echo "SYNTAX ERROR: $script" >&2; fail=1; }
done < <(git ls-files -z '*.sh')

[[ $fail -eq 0 ]] || exit 1
echo "bash -n: all scripts OK"

if command -v shellcheck &>/dev/null; then
  while IFS= read -r -d '' script; do
    shellcheck --severity=warning "$script" || fail=1
  done < <(git ls-files -z '*.sh')
  [[ $fail -eq 0 ]] || exit 1
  echo "shellcheck: all scripts OK"
fi
