# dso-jenkins-lib — shared CI backbone

airgap-devkit's `Jenkinsfile` opts into the **dso-suite Jenkins shared library**
(`dso-jenkins-lib`) as the common CI backbone across the dso-suite family
(airgap-devkit, oxide-sloc, and the dso-suite tool pipelines themselves). This is
**loose coupling**: the library is loaded from its own SCM repo at build time —
airgap-devkit does **not** submodule or vendor dso-suite, and stays independently
releasable.

## What the pipeline uses

| Library step | Where | Purpose |
|--------------|-------|---------|
| `computeVersion()` | Configure stage | Offline, network-identical version string from `git describe`. |
| `stampBuild(...)` | Configure stage | Sets the Jenkins build display name/description. |
| `notify(...)` | `post { success/failure }` | Config-driven email + optional chat. No-ops when targets are blank (correct air-gapped). |

Every call is wrapped in `try/catch` (or degrades via blank config), so a
controller that has **not** registered the library still runs the pipeline — the
library steps simply skip with a log line. Registering the library switches them on.

## One-time controller setup

1. **Register the library** — Manage Jenkins → System → Global Pipeline
   Libraries → Add:
   - **Name:** `dso-jenkins-lib`
   - **Default version:** `v1` (a git tag) — matches `@Library('dso-jenkins-lib@v1')`
   - **Retrieval:** Modern SCM → Git → the `dso-suite/dso-jenkins-lib` repo URL
   - Leave *Load implicitly* **off** (the Jenkinsfile opts in explicitly).

   Full walkthrough: `dso-suite/dso-jenkins-lib/SETUP.md`.

2. **Per-network config** — copy [`dso-ci.properties.example`](../../dso-ci.properties.example)
   to `dso-ci.properties` at the repo root on the controller and fill in the
   network-specific values (Nexus, email, proxy, downstream job names). This file
   is `.gitignore`d and is the only thing that differs between networks; the
   Jenkinsfile stays byte-for-byte identical. An all-blank file is a valid,
   fully air-gapped (silent) configuration.

3. **Credentials** — create the IDs referenced in `dso-ci.properties`
   (`gitCredentialsId`, `nexusCredentialsId`, …) in the Jenkins credential store.

## Downstream integration

`checksumJobName` and `bundleJobName` in `dso-ci.properties` point the pipeline at
the dso-suite **checksum_generator** (integrity drift gate) and **git_bundles**
(air-gap transfer) jobs on the same controller — the upstream→downstream loop
that ties airgap-devkit into the shared tooling. See
[`ci/DSO-INTEGRATION.md`](../DSO-INTEGRATION.md).
