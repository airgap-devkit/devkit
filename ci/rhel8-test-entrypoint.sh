#!/usr/bin/env bash
# Default container entrypoint for the RHEL 8 integration test image.
# Installs the selected profile, then runs the full smoke-test suite.
# Override DEVKIT_PROFILE (env) to test a different profile.
set -euo pipefail

echo '==> airgap-devkit RHEL 8 integration test'
echo "    Profile: ${DEVKIT_PROFILE}"
echo "    glibc: $(ldd --version | head -1)"
echo ''
bash scripts/internal/install-cli.sh --yes --profile "${DEVKIT_PROFILE}"
echo ''
bash tests/run-tests.sh --verbose
