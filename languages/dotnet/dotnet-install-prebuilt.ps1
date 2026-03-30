# Author: Nima Shafie
# =============================================================================
# install-prebuilt.ps1
# Installs .NET 10 SDK from prebuilt-binaries submodule.
# No internet access, no system installer, no elevation required for user install.
#
# Run from: languages/dotnet/ OR repo root
# Run in:   any PowerShell
#
# USAGE:
#   cd languages\dotnet
#   .\install-prebuilt.ps1
#   .\install-prebuilt.ps1 -dest "C:\MyPath\dotnet"
#   .\install-prebuilt.ps1 -format zip
#
# OPTIONS:
#   -dest   <path>    Install destination (default: auto-detected)
#   -format 7z|zip    Archive format (default: 7z if 7-Zip found, else zip)
# =============================================================================

param(
    [string]$dest   = "",
    [string]$format = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot     = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$SDK_VERSION  = "10.0.201"
$PrebuiltDir  = Join-Path $RepoRoot "prebuilt-binaries\languages\dotnet\$SDK_VERSION"
$VendoredDir  = Join-Path $RepoRoot "prebuilt-binaries\dev-tools\7zip"

function Info  { param($m) Write-Host "[INFO] $m" }
function Warn  { param($m) Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Err   { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Step  { param($m) Write-Host ""; Write-Host "*** $m ***" }
function Die   { param($m) Err $m; exit 1 }
function OK    { param($m) Write-Host "[OK] $m" -ForegroundColor Green }

function Require-Exit {
    param($code, $msg)
    if ($code -ne 0) { Die "$msg (exit $code)" }
}

function Format-Size {
    param($bytes)
    if ($bytes -gt 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    if ($bytes -gt 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    return "{0:N0} KB" -f ($bytes / 1KB)
}

# -----------------------------
# Step 1: Determine install dest
# -----------------------------
Step "Determining install destination"
if (-not $dest) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        $dest = "C:\Program Files\airgap-cpp-devkit\dotnet"
        Info "Admin rights detected. Installing system-wide."
    } else {
        $dest = "$env:LOCALAPPDATA\airgap-cpp-devkit\dotnet"
        Warn "No admin rights. Installing for current user only."
        Warn "Re-run as Administrator for system-wide install."
    }
}
Info "Install destination: $dest"

# -----------------------------
# Step 2: Locate 7-Zip
# -----------------------------
function Find-SevenZip {
    $candidates = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\7-Zip\7z.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    $fromPath = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($fromPath) { return $fromPath.Source }
    $vendored = Join-Path $VendoredDir "7z2600-x64.exe"
    if (Test-Path $vendored) {
        Info "Using vendored 7-Zip from prebuilt-binaries/dev-tools/7zip/"
        return $vendored
    }
    return $null
}

$sevenZipExe = Find-SevenZip

# -----------------------------
# Step 3: Check prebuilt parts exist
# -----------------------------
Step "Locating prebuilt parts"
if (-not (Test-Path $PrebuiltDir)) {
    Die "Prebuilt directory not found: $PrebuiltDir`nRun: git submodule update --init prebuilt-binaries"
}

$has7z  = (Get-ChildItem $PrebuiltDir -Filter "dotnet-sdk-$SDK_VERSION-win-x64.7z.part-*"  -ErrorAction SilentlyContinue).Count -gt 0
$hasZip = (Get-ChildItem $PrebuiltDir -Filter "dotnet-sdk-$SDK_VERSION-win-x64.zip.part-*" -ErrorAction SilentlyContinue).Count -gt 0

if (-not $has7z -and -not $hasZip) {
    Die "No prebuilt parts found in $PrebuiltDir for SDK $SDK_VERSION"
}

if (-not $format) {
    if ($has7z -and $sevenZipExe) { $format = "7z" }
    elseif ($hasZip)              { $format = "zip"; Warn "7-Zip not found -- falling back to .zip format." }
    else { Die "No suitable format available." }
}
Info "Archive format: .$format"

if ($format -eq "7z" -and -not $sevenZipExe) {
    Die "7-Zip required for .7z but not found. Install 7-Zip or use -format zip"
}

# -----------------------------
# Step 4: Reassemble
# -----------------------------
Step "Reassembling archive from parts"

if ($format -eq "7z") {
    $archiveName = "dotnet-sdk-$SDK_VERSION-win-x64.7z"
} else {
    $archiveName = "dotnet-sdk-$SDK_VERSION-win-x64.zip"
}

$parts = Get-ChildItem $PrebuiltDir -Filter "$archiveName.part-*" | Sort-Object Name
Info "Found $($parts.Count) part(s):"
foreach ($p in $parts) { Info "  $($p.Name)  ($(Format-Size $p.Length))" }

$tmpDir     = Join-Path $env:TEMP "dotnet-prebuilt-$SDK_VERSION"
$tmpArchive = Join-Path $tmpDir $archiveName
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

Info "Reassembling..."
$outStream = [System.IO.File]::OpenWrite($tmpArchive)
try {
    foreach ($p in $parts) {
        $bytes = [System.IO.File]::ReadAllBytes($p.FullName)
        $outStream.Write($bytes, 0, $bytes.Length)
    }
} finally { $outStream.Close() }
OK "Reassembled: $(Format-Size (Get-Item $tmpArchive).Length)"

# -----------------------------
# Step 5: Verify SHA256
# -----------------------------
Step "Verifying integrity"
$manifestPath = Join-Path $PrebuiltDir "manifest.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $archiveKey = if ($format -eq "7z") { "7z" } else { "zip" }
    $expectedHash = $manifest.archives."windows-x64".$archiveKey.sha256
    if ($expectedHash) {
        $actualHash = (Get-FileHash $tmpArchive -Algorithm SHA256).Hash.ToLower()
        if ($actualHash -ne $expectedHash.ToLower()) {
            Remove-Item $tmpDir -Recurse -Force
            Die "SHA256 mismatch!`n  Expected: $expectedHash`n  Actual:   $actualHash"
        }
        OK "SHA256 verified."
    } else {
        Warn "No hash in manifest for .$format -- skipping verification."
    }
} else {
    Warn "manifest.json not found -- skipping integrity check."
}

# -----------------------------
# Step 6: Extract
# -----------------------------
Step "Extracting to $dest"
if (Test-Path $dest) {
    $ans = Read-Host "Destination already exists. Overwrite? (y/n)"
    if ($ans -notmatch '^[Yy]') { Die "Aborted." }
    Remove-Item $dest -Recurse -Force
}
New-Item -ItemType Directory -Path $dest -Force | Out-Null

if ($format -eq "7z") {
    & "$sevenZipExe" x "$tmpArchive" -o"$dest" -y
    Require-Exit $LASTEXITCODE "Extraction failed"
} else {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tmpArchive, $dest)
}

Remove-Item $tmpDir -Recurse -Force

# -----------------------------
# Step 7: Verify
# -----------------------------
Step "Verifying installation"
$dotnetExe = Join-Path $dest "dotnet.exe"
if (Test-Path $dotnetExe) {
    $version = & "$dotnetExe" --version 2>&1
    OK "dotnet.exe found: $version"
} else {
    Die "dotnet.exe not found at $dest -- extraction may have failed."
}

# -----------------------------
# Done
# -----------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " .NET SDK $SDK_VERSION installed successfully" -ForegroundColor Green
Write-Host " Location : $dest" -ForegroundColor Green
Write-Host " dotnet   : $dest\dotnet.exe" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Add to PATH for this session:"
Write-Host "  `$env:PATH = `"$dest;`$env:PATH`""
Write-Host ""
Write-Host "Verify:"
Write-Host "  dotnet --version"
Write-Host "  dotnet new console -n HelloWorld"
Write-Host "  cd HelloWorld && dotnet run"