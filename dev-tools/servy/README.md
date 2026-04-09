# Servy 7.8 -- Prebuilt Module

Vendors [Servy 7.8](https://github.com/aelassas/servy) for air-gapped Windows environments.
Servy turns any executable into a native Windows service -- a full-featured alternative to
NSSM, WinSW, and FireDaemon Pro.

> **Windows only.** Running `setup.sh` on Linux prints an informational message and exits cleanly.

## Vendored Assets

Binary is stored as a single file in `prebuilt-binaries/dev-tools/servy-7.8/` (under 100MB):

| File | Size | Description |
|------|------|-------------|
| `servy-7.8-x64-portable.7z` | ~80 MB | Single file -- no split required |

Archive SHA256: `e0133ed93f9c4ba44dc2731777a27be1385ca1e0cc626ce5d600a39e2d632613`

## What Gets Installed

| File | Purpose |
|------|---------|
| `Servy.exe` | GUI desktop application -- create and manage services interactively |
| `Servy.Manager.exe` | Real-time monitoring of all installed Servy services |
| `servy-cli.exe` | CLI -- scriptable service management for CI/CD and automation |
| `Servy.psm1` | PowerShell module -- place alongside `servy-cli.exe` |
| `Servy.psd1` | PowerShell module manifest -- required for module import |
| `taskschd/` | Task Scheduler helpers for failure email/notification alerts |

## Install Matrix

| Mode | Install Path |
|------|-------------|
| **Admin** | `C:\Program Files\servy\` (requires elevation) |
| **User** | `%LOCALAPPDATA%\airgap-cpp-devkit\servy\` (no elevation) |

PATH is registered automatically at the appropriate scope (Machine for admin, User for user).

## Prerequisites

**7-Zip must be installed first.** The install script uses `7z.exe` or `7za.exe` to extract
the portable archive. Install via:

```bash
bash dev-tools/7zip/setup.sh
```

## Usage

```bash
# From repo root -- install mode is auto-detected
bash dev-tools/servy/setup.sh

# Force a custom prefix
bash dev-tools/servy/setup.sh --prefix "C:/tools/servy"
```

## Quick Start (after install)

Open a new terminal (for PATH to take effect), then:

```powershell
# Install an app as a Windows service
servy-cli.exe install --name="MyApp" --path="C:\MyApp\MyApp.exe" --startupType="Automatic"

# Start it
servy-cli.exe start --name="MyApp"

# Check status
servy-cli.exe status --name="MyApp"

# Stop and uninstall
servy-cli.exe stop --name="MyApp"
servy-cli.exe uninstall --name="MyApp"
```

## PowerShell Module

```powershell
Import-Module "C:\Program Files\servy\Servy.psm1"
Install-ServyService -Name "MyApp" -Path "C:\MyApp\MyApp.exe" -StartupType Automatic -EnableHealth
```

## Upstream

- Version: 7.8 (2026-04-04)
- Author: Akram El Assas
- License: MIT
- Source: https://github.com/aelassas/servy
- Release: https://github.com/aelassas/servy/releases/tag/v7.8