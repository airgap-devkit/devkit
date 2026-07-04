# DSO-suite integration

How airgap-devkit interoperates with **oxide-sloc** and **dso-suite** for
air-gapped C++ delivery.

## Architecture: hub + independent spokes

- **dso-suite** is the shared-infra **hub**: the Jenkins shared library, the
  checksum engine, git-bundle transfer, Bitbucket bulk-sync, and the prebuilt
  gRPC distribution all originate there.
- **airgap-devkit** and **oxide-sloc** are independently releasable **spokes**.
  They never submodule dso-suite. They integrate through three loose contracts:
  1. **CI backbone** — the `dso-jenkins-lib` shared library, loaded from SCM at
     build time (`@Library('dso-jenkins-lib@v1')`).
  2. **Vendored artifacts, pinned by version + SHA-256** — each spoke imports
     exactly the dso artifact it needs; provenance stays upstream.
  3. **Shared conventions** — the checksum manifest format, the git-bundle
     transfer package, the Conan bundle format, and `dsoConfig` keys.

Coupling is always a *pinned artifact* or a *build-time library load*, never a
live source dependency — so the two products stay releasable on their own while
everything can still flow upstream and downstream.

## What is wired today

| Contract | Mechanism | Entry point |
|----------|-----------|-------------|
| CI backbone | `dso-jenkins-lib` via `@Library` — version stamp, build name, config-driven notify | `Jenkinsfile` + `dso-ci.properties` · [ci/jenkins/DSO-SHARED-LIBRARY.md](jenkins/DSO-SHARED-LIBRARY.md) |
| gRPC (vendored artifact) | dso-suite prebuilt 1.81.1, per MSVC toolset, split into `prebuilt/` | `scripts/internal/import-grpc-prebuilt.sh` |
| Conan (ABI-matched) | Static-runtime profiles matched to each gRPC toolset | `conan-airgap/config/profiles/windows-msvc-v14{2,3,5}-grpc` |
| Integrity (shared engine) | Vendored `checksum_generator` — whole-tree drift gate (exit 3) | `scripts/internal/checksum-verify.sh` |
| Air-gap transfer | git bundles + SHA256SUMS + self-verifying `verify.sh` | `scripts/internal/airgap-transfer.sh` |

## Upstream → downstream flow

```
        dso-suite (hub, connected side)                 spokes (this repo, oxide-sloc)
        ───────────────────────────────                ───────────────────────────────
  grpc/  ── import-grpc-prebuilt.sh ─────────────────▶  prebuilt/  (pinned, checksummed)
  checksum_generator/ ── vendored ──────────────────▶  scripts/internal/lib/checksum_generator.py
  dso-jenkins-lib ── @Library (SCM, build time) ─────▶  Jenkinsfile
  git_bundles / airgap-package ── same contract ────▶  scripts/internal/airgap-transfer.sh
                                                        │
  spoke artifacts (SLOC reports, devkit bundles) ◀──── build outputs
        └── flow back through the hub's checksum + git-bundle + publish machinery
```

## Cross-project operations (hub side)

dso-suite's tools already operate over **any** repo, so they work across all
three projects without change:

```bash
# Bulk-sync every project's repos across the air-gap (headless)
bash dso-suite/bitbucket_project_download/bitbucket-manager.sh --ci ...

# One-shot self-verifying transfer package of any super-repo + submodules
make -C dso-suite transfer ARGS="--repo /path/to/airgap-devkit --out /transfer"
```

Spoke side, the equivalent self-contained commands (no dso-suite checkout needed):

```bash
# Build a verifiable transfer package of THIS repo + its submodules
bash scripts/internal/airgap-transfer.sh build --out /transfer
# Far side:
cd /transfer/airgap-devkit-airgap-* && bash verify.sh   # exit 0 intact, 3 drift

# Whole-tree integrity gate (CI or ad hoc), shared format across all projects
bash scripts/internal/checksum-verify.sh generate
bash scripts/internal/checksum-verify.sh verify --baseline checksums/checksums.csv
```

## Independence guarantees

- Removing dso-suite from disk does not break airgap-devkit or oxide-sloc: the
  gRPC binaries, the checksum engine, and the transfer tooling are all vendored.
- The shared Jenkins library is the only build-time dependency, and every call is
  guarded so a controller without it still runs the pipeline.
