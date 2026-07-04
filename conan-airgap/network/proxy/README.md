# Network profile: `proxy`

Same intent as `internal-mirror`, but the internal repo is only reachable through
a **corporate proxy** (and possibly a TLS-intercepting CA). Sets
`core.net.http:proxies` in [`global.conf`](global.conf) and points at an internal
remote in [`remotes.json`](remotes.json).

## Configure

1. In [`global.conf`](global.conf): set the proxy host/port; if TLS is intercepted,
   uncomment `core.net.http:cacert_path` and point it at your internal CA bundle.
2. In [`remotes.json`](remotes.json): set the internal repo URL.

## Apply during import

```bash
bash scripts/import-airgap.sh --bundle <bundle> --network proxy
```
