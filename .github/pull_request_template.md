## Summary

<!-- One or two sentences: what does this PR do and why? -->

## Type of Change

- [ ] Bug fix
- [ ] New tool
- [ ] Feature / enhancement
- [ ] Refactor / cleanup
- [ ] Docs / SBOM update
- [ ] CI / build change

## Checklist

- [ ] `bash -n <changed-scripts.sh> && echo OK` — all shell scripts pass syntax check
- [ ] `bash tests/run-tests.sh --verbose` — smoke tests pass
- [ ] No compiled binaries added to the main repo (binaries go in `prebuilt/` submodule)
- [ ] `manifest.json` SHA256 checksums updated (if tool version changed)
- [ ] `sbom.spdx.json` updated via `bash scripts/generate-sbom.sh` (if tool added/bumped)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `README.md` / `TOOLS.md` updated (if a tool was added or removed)

## Testing Notes

<!-- How was this tested? Which platform(s)? What edge cases were exercised? -->

## Related Issues

<!-- Closes #xxx, or "no related issue" -->
