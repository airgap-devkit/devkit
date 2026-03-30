# languages/dotnet

### Author: Nima Shafie

Portable .NET 10 SDK for air-gapped Windows and Linux environments.
No installer required -- extract and use.
Part of the `airgap-cpp-devkit` suite.

---

## Version

| Component | Version | Support |
|-----------|---------|---------|
| .NET SDK | 10.0.201 | LTS -- supported until November 2028 |
| .NET Runtime | 10.0.5 | Included in SDK |
| ASP.NET Core Runtime | 10.0.5 | Included in SDK |
| C# | 14 | Included in SDK |

---

## Quickstart -- Prebuilt (Recommended)

No build tools required. Just extract and use.

**Windows (Developer PowerShell or any PowerShell):**
```powershell
cd languages\dotnet
.\install-prebuilt.ps1
```

**Linux / Git Bash:**
```bash
bash languages/dotnet/setup.sh
```

After install, verify:
```bash
dotnet --version
# Expected: 10.0.201
```

---

## What is Included

The SDK package contains everything needed to build and run C# applications:

| Component | Description |
|-----------|-------------|
| `dotnet` CLI | Build, run, publish, test commands |
| C# compiler (`csc` / Roslyn) | Compiles C# 14 source to IL |
| .NET Runtime | Runs compiled .NET applications |
| ASP.NET Core Runtime | Runs web/server applications |
| NuGet client | Package management (offline use only in air-gap) |
| MSBuild | Project build system |
| `dotnet-script` support | Run C# scripts directly |

This is the **zip/tar.gz extract** distribution -- no system-level installer,
no registry changes, no elevation required. The SDK lives entirely in the
install directory.

---

## Install Locations

| Mode | Windows | Linux |
|------|---------|-------|
| Admin | `C:\Program Files\airgap-cpp-devkit\dotnet\` | `/opt/airgap-cpp-devkit/dotnet/` |
| User | `%LOCALAPPDATA%\airgap-cpp-devkit\dotnet\` | `~/.local/share/airgap-cpp-devkit/dotnet/` |
| Custom | Pass `-dest <path>` to `install-prebuilt.ps1` or `--prefix` to `setup.sh` | |

The install script writes `dotnet` to the install directory and registers
it in the devkit PATH via `install_env_register`.

---

## Usage After Install

**Windows -- add to PATH for current session:**
```powershell
$env:PATH = "C:\Users\n1mz\AppData\Local\airgap-cpp-devkit\dotnet;$env:PATH"
dotnet --version
```

**Linux -- add to PATH for current session:**
```bash
export PATH="$HOME/.local/share/airgap-cpp-devkit/dotnet:$PATH"
dotnet --version
```

**Create and build a C# console app:**
```bash
dotnet new console -n MyApp
cd MyApp
dotnet build
dotnet run
```

**Build a self-contained executable (no runtime needed on target machine):**
```bash
dotnet publish -c Release -r win-x64 --self-contained true
dotnet publish -c Release -r linux-x64 --self-contained true
```

---

## Air-Gap NuGet Usage

In an air-gapped environment, NuGet packages cannot be downloaded from
nuget.org. Two options:

**Option 1 -- local NuGet feed:** Copy `.nupkg` files to a local directory
and configure `nuget.config` to point to it:
```xml
<configuration>
  <packageSources>
    <add key="local" value="C:\MyNuGetFeed" />
  </packageSources>
</configuration>
```

**Option 2 -- pre-restore on an internet-connected machine:** Run
`dotnet restore` with internet access, then copy the entire
`~/.nuget/packages/` cache to the air-gapped machine.

---

## Integrity

SHA256 hashes are pinned in `manifest.json` and verified against official
Microsoft release checksums before extraction. Nothing is extracted if
verification fails.

---

## Layout

```
languages/dotnet/
|- install-prebuilt.ps1   <- Windows install from prebuilt-binaries/
|- setup.sh               <- Linux/bash entry point
|- manifest.json          <- SDK version and upstream reference
|- sbom.spdx.json         <- SPDX component record
|- README.md
```

Prebuilt archives live in:
```
prebuilt-binaries/languages/dotnet/10.0.201/
|- dotnet-sdk-10.0.201-win-x64.zip.part-*    <- Windows zip split parts
|- dotnet-sdk-10.0.201-win-x64.7z.part-*     <- Windows .7z split parts (smaller)
|- dotnet-sdk-10.0.201-linux-x64.tar.gz.part-* <- Linux tar.gz split parts
|- manifest.json                               <- SHA256 for all parts
```