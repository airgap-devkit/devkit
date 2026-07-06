# CONTINUE — native-format migration + Option B distribution

Handoff notes to resume the `.7z`/`.tar.xz` → `.zip`/`.tar.gz` migration and the
"binaries as artifacts" (Option B) distribution work. Safe to pick up cold.

## Status: code complete + validated; full re-stage NOT yet run

- **Phase 1** (native format `.zip` Windows / `.tar.gz` Linux) — code complete.
- **Phase 2** (fetch / bundle / publish + docs) — code complete, smoke-tested.
- **Validated** by real `setup.sh` installs on this machine:
  - cmake [win+linux] ✅, ninja [win+linux] ✅
  - conan linux layout ✅, python linux layout ✅ (strip 2→0 confirmed)
- **3 bugs found & fixed during validation** (2 were pre-existing latent bugs):
  1. `devkit_repack` mis-stripped a single *file* archive (ninja) — now `auto`
     mode strips only a sole *directory*.
  2. `generate-manifest.py` tried to checksum subdirs (`python/wheels/`) — now
     files-only.
  3. `devkit_manifest_sha256` grep exited non-zero on "no hash" (normal for split
     archives) and tripped `set -e` in setup.sh — added `|| true`.

## What is NOT done yet

1. **Full in-place re-stage** of all 225 legacy archives. Was started, then
     stopped cleanly for shutdown and the partial (cmake/4.3.1) reverted — so
     `prebuilt/` is back to baseline (225 legacy archives). Nothing corrupt.
2. **Phase 3** (git history rewrite to reclaim ~16 GB in the `prebuilt-binaries`
     submodule) — still pending Nima's go-ahead. Separate from this work.
3. **CI wiring** of `check-formats.sh` and a `release.sh` publish step — optional,
     not done.

## Resume steps

```bash
cd "$HOME/Desktop/airgap-devkit"

# 1. Finish the offline re-stage (no internet needed; self-healing/resumable;
#    converts every existing .tar.xz/.7z to native, regenerates manifests).
#    Heavy: llvm×3 + dotnet×3 are multi-GB extract+rezip (~1h+ total).
bash scripts/internal/restage-local.sh --all        # or pass specific dirs

# 2. Confirm no legacy formats remain (expect: all native).
bash scripts/internal/check-formats.sh

# 3. (Optional) run the standard smoke tests after installing into a prefix.
bash tests/run-tests.sh --verbose
```

Tip: to re-stage in a temp dir instead of in place (validation, no submodule
churn): `bash scripts/internal/restage-local.sh --dest /tmp/stage <version-dir>...`

## Files I changed this session (all on disk; survive reboot)

MAIN repo (`scripts/`, `docs/`):
- Modified: `scripts/internal/lib/devkit-prebuilt.sh` (repack helpers, `devkit_repack` auto),
  `scripts/internal/lib/generate-manifest.py` (format-aware + files-only),
  `scripts/internal/apply-tool-update.sh`, `scripts/internal/download-prebuilt.sh`
- New: `scripts/internal/lib/enumerate-artifacts.py`, `scripts/internal/check-formats.sh`,
  `scripts/internal/fetch-artifacts.sh`, `scripts/internal/build-bundle.sh`,
  `scripts/internal/publish-artifacts.sh`, `scripts/internal/restage-local.sh`,
  `docs/OFFLINE-DISTRIBUTION.md`, this file.

TOOLS submodule (`tools/`):
- `tools/lib/devkit-install.sh` (`devkit_resolve_archive`, sha256-parse fix, `|| true`)
- setup.sh routed through `devkit_extract`/resolver: cmake, conan, sqlite, dotnet,
  python, llvm, ninja, gcc, grpc, lcov (build-tools + toolchains).

PREBUILT submodule (`prebuilt/`):
- Staged removal of orphaned `dev-tools/servy/8.3/servy-8.3-x64-portable.7z`.

NOTE: there was substantial PRE-EXISTING uncommitted work in all three repos
before this session (other setup.sh, docs/TOOLS.md, install-cli.sh, tools/lib/zlib,
various prebuilt changes). None of it was touched. Nothing is committed.

## CRITICAL design correction (symlinks) — 2026-07-04

The first full re-stage attempt aborted at **llvm linux**: MSYS `tar` on Windows
cannot recreate the **48 POSIX symlinks** in the LLVM tarball ("Cannot create
symlink"). Extract-and-repack on Windows is therefore WRONG for Linux archives —
it corrupts/loses symlinks. Corrected design:

- **Linux `.tar.xz` → `.tar.gz`: TRANSCODE the stream** (`xz -dc | gzip`, or Python
  `lzma`→`gzip` fallback) — never extract. Preserves the tar byte-for-byte
  (symlinks + layout). Helper: `devkit_transcode_targz` in `lib/devkit-prebuilt.sh`.
  Used by restage-local, download-prebuilt, apply-tool-update for all Linux targets.
- **Windows `.tar.xz`/`.7z` → `.zip`: extract→zip** with auto-strip of a sole
  wrapper dir (Windows payloads have no symlinks; `unzip` can't strip at install).
- **Install: `devkit_install_archive`** (in `tools/lib/devkit-install.sh`) extracts
  and auto-strips a SOLE wrapper directory (never a bare file), then moves payload
  to the target. This runs on the real target host (Linux symlinks OK) and removes
  all per-tool `--strip-components` guessing. Payload setups (cmake, conan, sqlite,
  dotnet, python, llvm, ninja) now call it; lcov/gcc keep plain `devkit_extract`
  (they want the wrapper / a flat bundle).

Validated: transcode preserved llvm's 48 symlinks; cmake/ninja/dotnet/conan/
sqlite installs pass (wrapper-strip, flat, and bare-file cases). NOTE: the conan
2.28.0 *windows* archive contains no `conan.exe` — a PRE-EXISTING staging content
bug, unrelated to format.

## Stale-version prune — 2026-07-04

Removed 18 stale older-version dirs from `prebuilt/` (kept newest per tool),
freeing 7.56 GB and cutting the legacy set 225 → 87 archives. Removed:
cmake 4.3.1/4.3.2 (kept 4.3.3), 7zip 26.00 (26.01), conan 2.27.1/2.28.0 (2.29.1),
notepadpp 8.9.3/8.9.4 (8.9.6.4), servy 7.9/8.3/8.4 (8.5), sqlite 3.53.0/3.53.2
(3.53.3), vscode 1.117.0/1.124.2 (1.127.0), dotnet 10.0.202/10.0.203 (10.0.301),
llvm 22.1.3/22.1.4 (22.1.8). Staged as submodule deletions (uncommitted).
NOTE drift: conan setup.sh wants 2.30.0 but newest staged is 2.29.1 (pre-existing).

## Bump-to-latest + one-version-per-tool — 2026-07-04

All tools verified against upstream: nearly all already at latest. Now exactly ONE
staged version per tool. Bumped the real gaps: conan **2.30.0** (added
`asset_exclude:"installer"` to its devkit.json; used `--all-platforms`) and 7zip
**26.02**; old versions removed; conan installs verified both platforms.

STILL BEHIND (could not auto-bump — no github_repo/template or odd tag):
- git 2.54.0→2.55.0 (tag `v2.55.0.windows.2`, asset ver `2.55.0.2`; Windows-only)
- grpc 1.80.0→1.81.1 (custom VS build)
- putty 0.83→0.84 (vendor site greenend.org.uk)
- sourcetree 3.4.30→3.4.31 (Atlassian CDN)
These need manual vendor staging (download → put under prebuilt/<...>/<newver>/ →
`generate-manifest.py` → remove old dir → bump devkit.json/setup.sh version).

CAUTION LEARNED: reverting a bad change with `git -C <sub> checkout -- <file>`
DESTROYS uncommitted work (it happened to conan/setup.sh — reconstructed). Commit
this migration soon to de-risk. Nothing is committed yet.

## Key design facts (so a cold start doesn't re-derive)

- Format decision: `.zip` (Windows, native Explorer/Expand-Archive, no admin) and
  `.tar.gz` (Linux, base tar). Never `.tar.xz`/`.7z`. WinZip is NOT required.
- Invariant: authoring normalizes payload to the archive ROOT; install extracts
  with `--strip-components=0`. `devkit_repack ... auto` enforces this.
- Option B contract: `DEVKIT_ARTIFACT_BASE` (any URL/path) + relative path + SHA256.
  Works on GitHub Releases, any Bitbucket Server (raw path), Nexus, or a file share.
  Fully air-gapped path = offline bundle from `build-bundle.sh`. No admin anywhere.
- `download-prebuilt.sh` versions have drifted behind setup.sh; `apply-tool-update.sh`
  is the accurate per-tool upstream path. `restage-local.sh` sidesteps drift entirely
  (reformats existing binaries, no version change).
