# airgap-devkit Python package

Thin Python wrapper that ships the DevKit Manager binary and exposes an
`airgap-devkit` console entry point.

## Build the wheel

**Step 1 — build (or verify) the server binaries:**
```bash
bash scripts/build-server.sh
```

**Step 2 — stage binaries into the package:**
```bash
bash packages/python/scripts/stage-binaries.sh
```

**Step 3 — build the wheel:**
```bash
pip install build
python -m build packages/python/ --outdir dist/python/
```

This produces `dist/python/airgap_devkit-<version>-py3-none-any.whl`.

## Install in an air-gapped environment

Copy the `.whl` file to the target machine, then:
```bash
pip install airgap_devkit-1.0.1rc2-py3-none-any.whl --no-index
```

## Use

```bash
airgap-devkit               # starts the server and opens the browser
airgap-devkit --no-browser  # headless / CI mode
airgap-devkit --port 8080
```
