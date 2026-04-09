# Python 3.14.4 -- Prebuilt Module

Vendors [Python 3.14.4](https://www.python.org/downloads/release/python-3144/) for
air-gapped environments. Installs a portable interpreter alongside any existing system
Python without modifying PATH until `env-setup.sh` is sourced.

Also installs a curated set of vendored pip packages from `pip-packages/`.

## Vendored Assets

| File | Size | Platform | Description |
|------|------|----------|-------------|
| `python-3.14.4-embed-amd64.zip` | ~12 MB | Windows x64 | Embeddable archive, single file |
| `cpython-3.14.4+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz.part-aa` | ~99 MB | Linux x86_64 | Split part 1 of 2 |
| `cpython-3.14.4+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz.part-ab` | ~21 MB | Linux x86_64 | Split part 2 of 2 |

Reassembled Linux archive SHA256: `2431e22d39c0dee2c4d785250e2974bea863a61951a2e7edab88a14657a39d73`

Reassemble with:
```bash
cat cpython-3.14.4+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz.part-* \
  > cpython-3.14.4+20260408-x86_64-unknown-linux-gnu-install_only.tar.gz
```

## Vendored Pip Packages

All packages are installed offline from `.whl` files in `pip-packages/`.
No internet access required.

| Package | Version | License | Purpose |
|---------|---------|---------|---------|
| `numpy` | 2.4.4 | BSD-3-Clause | Numerical computing -- arrays, linear algebra, FFT |
| `pandas` | 3.0.2 | BSD-3-Clause | Data analysis -- DataFrames, CSV/Excel/SQL I/O |
| `plotly` | 6.6.0 | MIT | Interactive visualizations -- charts, dashboards |
| `streamlit` | 1.56.0 | Apache-2.0 | Data app framework -- web UIs in pure Python |
| `requests` | 2.32.3 | Apache-2.0 | HTTP client -- REST APIs, file downloads |
| `PyYAML` | 6.0.2 | MIT | YAML parsing -- config files, CI definitions |
| `Jinja2` | 3.1.5 | BSD-3-Clause | Templating -- used by Conan, CMake, code gen tools |
| `click` | 8.1.8 | BSD-3-Clause | CLI framework -- write devkit helper scripts |
| `rich` | 14.0.0 | MIT | Terminal output -- colored tables, progress bars |
| `pytest` | 8.3.5 | MIT | Test runner -- for Python scripts in the devkit |

## Install Matrix

| Mode | Windows | Linux |
|------|---------|-------|
| **Admin** | `C:\Program Files\airgap-cpp-devkit\python\` | `/opt/airgap-cpp-devkit/python/` |
| **User** | `%LOCALAPPDATA%\airgap-cpp-devkit\python\` | `~/.local/share/airgap-cpp-devkit/python/` |

## Usage

```bash
# Install Python + all vendored pip packages
bash languages/python/setup.sh

# Install Python only (skip pip packages)
bash languages/python/setup.sh --skip-pip

# Force a custom prefix
bash languages/python/setup.sh --prefix /opt/my-python

# Force reinstall
bash languages/python/setup.sh --rebuild
```

Activate the interpreter:
```bash
source languages/python/scripts/env-setup.sh
python3 --version   # Python 3.14.4
pip list
```

## Notes

- Does **not** modify system Python or global PATH until `env-setup.sh` is sourced.
- Other devkit tools that require Python will prefer this interpreter if active,
  and fall back to system Python otherwise.
- The Windows embeddable distribution does not include `pip` by default.
  `setup.sh` bootstraps it from `vendor/get-pip.py` automatically if present.

## Upstream

- Version: 3.14.4 (2026-04-07)
- License: PSF-2.0
- Source: https://www.python.org/downloads/release/python-3144/
- Linux standalone: https://github.com/astral-sh/python-build-standalone/releases/tag/20260408