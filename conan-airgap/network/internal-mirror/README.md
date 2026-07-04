# Network profile: `internal-mirror`

For a "grey-net" environment that has **no internet but does have an internal
binary repository** (JFrog Artifactory or Sonatype Nexus with a Conan
repository). Conan pulls anything missing from the local cache off the internal
mirror instead of ConanCenter — so updates flow through your controlled repo.

## Configure

1. Edit [`remotes.json`](remotes.json) and replace `REPLACE-ME.internal` with your
   Artifactory/Nexus Conan repo URL.
2. If the mirror needs auth, after import run:
   ```bash
   conan remote login internal <user>
   ```
   or provide credentials via `CONAN_LOGIN_USERNAME_INTERNAL` /
   `CONAN_PASSWORD_INTERNAL` environment variables.

## Apply during import

```bash
bash scripts/import-airgap.sh --bundle <bundle> --network internal-mirror
```

The seeded cache still satisfies most requests; the mirror only serves what the
cache lacks. To push a seed bundle *into* the mirror instead of restoring it per
host, use `conan upload "*" -r internal --confirm` on a machine that can reach it.
