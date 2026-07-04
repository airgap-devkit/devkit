# Offline Distribution (Option B: binaries as artifacts)

Binaries no longer live in git history. The `prebuilt/` tree carries only
`manifest.json` files (tool + version + per-file SHA256). The actual archives are
published as **release artifacts** and rehydrated on demand. This keeps clones
small and bounded, and makes distribution work across fully air-gapped networks,
customer-run Bitbucket Server instances, and locked-down (no-admin) hosts.

## Archive formats

Every staged archive is in the format a bare host can extract with **OS-native
tooling and no admin rights** — no `xz`/7-Zip dependency:

| Platform | Format | Extracted by |
|----------|--------|--------------|
| Windows  | `.zip` | Explorer "Extract All", PowerShell `Expand-Archive`, `tar.exe` |
| Linux    | `.tar.gz` | base `tar` (gzip built in) |

`.7z` and `.tar.xz` are **rejected** — `bash scripts/internal/check-formats.sh`
fails the build if any appear under `prebuilt/`.

## The contract that makes it portable

Rehydration depends only on **a base location + a relative path + a SHA256** —
never a host-specific "releases" API. That is why the same mechanism works on
GitHub Releases, Bitbucket Server (which has *no* native release-asset feature),
Nexus/Artifactory, or a plain file share:

```
DEVKIT_ARTIFACT_BASE  +  <path under prebuilt/>   →   one artifact, checksum-verified
```

## Author / publish flow (connected machine)

```bash
# 1. Stage binaries in native format (repacks + regenerates manifests):
bash scripts/internal/download-prebuilt.sh          # bulk, or:
bash scripts/internal/apply-tool-update.sh <tool> <version>

# 2. Verify only native formats are present:
bash scripts/internal/check-formats.sh

# 3. Publish artifacts to the distribution point(s):
bash scripts/internal/publish-artifacts.sh --gh v1.3.5 --bundles          # public GitHub
bash scripts/internal/publish-artifacts.sh --dest /mnt/mirror/prebuilt    # export a mirror tree
```

`--bundles` also produces the offline transfer bundles in `dist/bundles/`.

## Customer install flows

### A. Fully air-gapped — offline bundle (no network at all)

The operator downloads/receives one self-contained file, transfers it (USB,
one-way gateway, etc.), and installs with zero network:

```bash
# Built by: bash scripts/internal/build-bundle.sh --platform windows|linux
# Windows:  airgap-devkit-<version>-windows.zip
# Linux:    airgap-devkit-<version>-linux.tar.gz
```

On the air-gapped host:

- **Windows** — right-click → *Extract All* (or `Expand-Archive`), open Git Bash
  in the folder, run `bash scripts/internal/install-cli.sh --yes --profile cpp-dev`.
- **Linux** — `tar -xzf …`, `cd`, run the same installer.

Every archive is SHA256-verified during install. All tools install into the
**user profile** (`%LOCALAPPDATA%` / `~/.local/share`) — **no admin required**.

### B. Semi-connected enclave — internal mirror

If install hosts can reach an internal mirror (the customer's Bitbucket, Nexus,
or a file share), point `DEVKIT_ARTIFACT_BASE` at it and rehydrate before install:

```bash
export DEVKIT_ARTIFACT_BASE=https://bitbucket.corp/rest/.../repos/prebuilt/raw   # or
export DEVKIT_ARTIFACT_BASE=/mnt/share/airgap-devkit/prebuilt

bash scripts/internal/fetch-artifacts.sh --platform windows   # SHA256-verified
bash scripts/internal/install-cli.sh --yes --profile cpp-dev
```

### Bitbucket Server note

Bitbucket Server/Data Center has no "release assets" store. Two supported options:

1. **Raw file path** — commit the artifact mirror tree (output of
   `publish-artifacts.sh --dest`) to a Bitbucket repo and point
   `DEVKIT_ARTIFACT_BASE` at that repo's raw URL. Different customer instances =
   just a different base URL; nothing else changes.
2. **Offline bundle** (flow A) — needs no Bitbucket feature at all; recommended
   for strict air-gap.

## Guarantees

- **Air-gapped:** flow A needs zero network; install verifies SHA256 locally.
- **Cross-Bitbucket:** the fetch contract is base-URL + path + checksum, so any
  Bitbucket instance (or none) works — no dependency on GitHub-only APIs.
- **No admin:** native extraction (`.zip`/`.tar.gz`) + user-profile install prefixes.
