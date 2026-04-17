#!/usr/bin/env bash
# =============================================================================
# scripts/generate-sbom.sh
#
# PURPOSE: Regenerate all SPDX 2.3 SBOM files for airgap-cpp-devkit.
#          Updates the creationInfo.created timestamp in every SBOM to now.
#          Recomputes SHA1 checksums for externalDocumentRefs in root SBOM.
#
# USAGE:
#   bash scripts/generate-sbom.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "============================================================"
echo " airgap-cpp-devkit -- SBOM Generator"
echo " Timestamp: ${TIMESTAMP}"
echo "============================================================"
echo ""

update_timestamp() {
  local sbom_file="$1"
  if [[ ! -f "${sbom_file}" ]]; then
    echo "[WARN] Not found, skipping: ${sbom_file}" >&2
    return
  fi
  sed -i "s/\"created\": \"[0-9T:Z-]*\"/\"created\": \"${TIMESTAMP}\"/" "${sbom_file}"
  echo "[OK] Updated timestamp: ${sbom_file}"
}

# ---------------------------------------------------------------------------
# Update timestamps
# ---------------------------------------------------------------------------
update_timestamp "${REPO_ROOT}/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/toolchains/llvm/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/toolchains/llvm/style-formatter/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/toolchains/llvm-mingw/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/toolchains/ninja/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/toolchains/gcc/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/toolchains/lcov/sbom.spdx.json"
update_timestamp "${REPO_ROOT}/tools/dev-tools/git-bundle/sbom.spdx.json"

echo ""

# ---------------------------------------------------------------------------
# Recompute SHA1 hashes for externalDocumentRefs in root SBOM
# ---------------------------------------------------------------------------
echo "Updating externalDocumentRefs SHA1 checksums in root SBOM..."
ROOT_SBOM="${REPO_ROOT}/sbom.spdx.json"

update_sha1() {
  local file="$1"
  local sha1
  sha1=$(sha1sum "${file}" | awk '{print $1}')
  echo "  ${file#${REPO_ROOT}/} -> ${sha1}"
  echo "${sha1}"
}

# Compute SHA1 for any sub-SBOMs that exist; skip missing ones gracefully
python3 - "${ROOT_SBOM}" "${REPO_ROOT}/tools" << 'PYEOF'
import json, sys, hashlib
from pathlib import Path
root_sbom, tools_root = sys.argv[1], Path(sys.argv[2])
with open(root_sbom) as f:
    doc = json.load(f)
updated = 0
for ref in doc.get("externalDocumentRefs", []):
    url = ref.get("spdxDocument", "")
    rel = url.replace("https://airgap-cpp-devkit.internal/tools/", "")
    candidate = tools_root / rel
    if candidate.exists():
        sha1 = hashlib.sha1(candidate.read_bytes()).hexdigest()
        ref["checksum"]["checksumValue"] = sha1
        updated += 1
with open(root_sbom, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print(f"[OK] SHA1 checksums updated ({updated} sub-SBOMs found).")
PYEOF

echo ""

# ---------------------------------------------------------------------------
# Verify all files exist and are valid JSON
# ---------------------------------------------------------------------------
echo "Verifying JSON syntax..."
ALL_OK=true
for sbom in \
  "${REPO_ROOT}/sbom.spdx.json"
do
  if [[ ! -f "${sbom}" ]]; then
    echo "  [FAIL] Missing: ${sbom}" >&2
    ALL_OK=false
    continue
  fi
  if python3 -c "import json,sys; json.load(open('${sbom}'))" 2>/dev/null; then
    echo "  [PASS] ${sbom#${REPO_ROOT}/}"
  else
    echo "  [FAIL] Invalid JSON: ${sbom}" >&2
    ALL_OK=false
  fi
done

echo ""

if [[ "${ALL_OK}" == "true" ]]; then
  echo "============================================================"
  echo " [SUCCESS] All SBOM files updated and valid."
  echo ""
  echo " Files:"
  echo "   sbom.spdx.json                                 (root)"
  echo "   Sub-SBOMs: updated where present under tools/"
  echo ""
  echo " Validate online: https://tools.spdx.org/app/validate/"
  echo "============================================================"
else
  echo "[FAIL] One or more SBOM files have issues." >&2
  exit 1
fi