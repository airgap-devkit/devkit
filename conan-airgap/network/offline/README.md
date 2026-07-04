# Network profile: `offline`

Pure air-gap. **Zero remotes** — Conan resolves everything from the local cache
that was populated by `conan cache restore`. Nothing ever touches the network.

This is the default. Use it on fully isolated hosts.

Apply during import:

```bash
bash scripts/import-airgap.sh --bundle <bundle> --network offline
```
