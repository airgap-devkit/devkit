# Author: Nima Shafie
# =============================================================================
# setup.ps1
# gRPC air-gap source build — full pipeline including HelloWorld demo.
# Also works with a prebuilt install (from install-prebuilt.ps1) by detecting
# whether the dest was populated by a source build or a prebuilt extract.
#
# Called via: setup.sh -> setup.bat -> setup.ps1
# Can also be run directly from Developer PowerShell:
#
#   cd frameworks\grpc
#   .\setup.ps1 -version 1.78.1 -dest "C:\Users\n1mz\AppData\Local\airgap-cpp-devkit\grpc-1.78.1"
#
# OPTIONS:
#   -version <ver>   gRPC version to build (1.78.1)
#   -dest    <path>  Install destination (if omitted, auto-detected)
#
# REQUIREMENTS:
#   - Visual Studio 2019 / 2022 / Insiders with Desktop C++ workload
#   - Git Bash (bash.exe) on PATH
#   - CMake installed to C:\Program Files\CMake\
#   - Run from: frameworks\grpc\ directory
#
# AIR-GAP GUARANTEE:
#   cmake is invoked with FETCHCONTENT_FULLY_DISCONNECTED=ON and all
#   dependency providers set to "module" (bundled third_party/ sources).
#   No network access is attempted during configure or build.
# =============================================================================

param(
    [string]$version = "",
    [string]$dest    = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptDir

# -----------------------------
# Helpers
# -----------------------------
function Info  { param($m) Write-Host "[INFO] $m" }
function Warn  { param($m) Write-Host "[WARNING] $m" -ForegroundColor Yellow }
function Err   { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Step  { param($m) Write-Host ""; Write-Host "*** $m ***" }
function Die   { param($m) Err $m; exit 1 }

function Require-Exit {
    param($code, $msg)
    if ($code -ne 0) { Die "$msg (exit $code)" }
}

# -----------------------------
# Step 1: Version selection
# -----------------------------
$GRPC_VERSION = $version

if (-not $GRPC_VERSION) {
    Write-Host ""
    Write-Host "============================================================"
    Write-Host " gRPC Air-Gap Source Build"
    Write-Host "============================================================"
    Write-Host ""
    Write-Host "  Available versions:"
    Write-Host "    [1] gRPC v1.78.1  (production-tested)"
    Write-Host ""
    $choice = Read-Host "  Select version (1)"
    switch ($choice) {
        "1" { $GRPC_VERSION = "1.78.1" }
        default { Die "Invalid selection. Enter 1." }
    }
}

switch ($GRPC_VERSION) {
    "1.78.1" { $GRPC_FOLDER = "grpc-1.78.1"; $EXTRACT_ROOT = "grpc-1.78.1" }
    default  { Die "Unknown version: $GRPC_VERSION. Supported: 1.78.1" }
}

Info "Selected: gRPC v$GRPC_VERSION"

# -----------------------------
# Step 2: Determine install dest
# -----------------------------
if ($dest) {
    $DEST_GRPC = $dest
    Info "Install destination (from caller): $DEST_GRPC"
} else {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        $DEST_ROOT = "C:\Program Files\airgap-cpp-devkit"
        Info "Admin rights detected. Installing system-wide."
    } else {
        $DEST_ROOT = "$env:LOCALAPPDATA\airgap-cpp-devkit"
        Warn "No admin rights. Installing for current user only."
        Warn "Other users on this machine will NOT have access."
        Warn "Re-run as Administrator for system-wide install."
    }
    $DEST_GRPC = "$DEST_ROOT\$GRPC_FOLDER"
    Info "Install destination: $DEST_GRPC"
}

$OUTPUT_DIR    = "$DEST_GRPC\outputs"
$GRPC_EXAMPLES = "$DEST_GRPC\examples\cpp\helloworld"
$GRPC_PROTOS   = "$DEST_GRPC\examples\protos"
$TARGET_CMAKE  = "$DEST_GRPC\examples\cpp\cmake"
$DEMO_DIR      = "$env:USERPROFILE\Desktop\grpc_demo"
$DEMO_HELLO    = "$DEMO_DIR\helloworld"
$GEN_DIR       = "$DEMO_HELLO\generated"
$DEMO_PROTOS   = "$DEMO_DIR\protos"
$LINK_CMAKE    = "$DEMO_DIR\cmake"

# -----------------------------
# Step 3: Locate VsDevCmd.bat
# -----------------------------
Step "Locating Visual Studio"

$VS_CANDIDATES = @(
    "C:\Program Files\Microsoft Visual Studio\18\Insiders\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Insiders\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Enterprise\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\Tools\VsDevCmd.bat",
    "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
)

$VSDEVCMD = $null
foreach ($candidate in $VS_CANDIDATES) {
    if (Test-Path $candidate) { $VSDEVCMD = $candidate; break }
}
if (-not $VSDEVCMD) {
    Die "VsDevCmd.bat not found. Install Visual Studio (2019/2022/Insiders) with Desktop C++ workload."
}
Info "Found VS: $VSDEVCMD"

# -----------------------------
# Locate cmake
# -----------------------------
$CMAKE_CANDIDATES = @(
    "C:\Program Files\CMake\bin\cmake.exe",
    "C:\Program Files (x86)\CMake\bin\cmake.exe"
)
$CmakeExe = $null
foreach ($c in $CMAKE_CANDIDATES) {
    if (Test-Path $c) { $CmakeExe = $c; break }
}
if (-not $CmakeExe) {
    $CmakeExe = "cmake"
    Warn "cmake not found at standard install path -- falling back to PATH cmake."
} else {
    Info "cmake: $CmakeExe"
}

# -----------------------------
# Step 4: Locate bash.exe
# -----------------------------
Step "Locating Git Bash"
$bashExe = Get-Command bash.exe -ErrorAction SilentlyContinue
if (-not $bashExe) { Die "bash.exe not found on PATH. Install Git for Windows." }
Info "bash.exe found: $($bashExe.Source)"

# -----------------------------
# Step 5: Verify vendor parts
# -----------------------------
Step "Verifying vendored source parts for v$GRPC_VERSION"
& bash.exe scripts/verify.sh $GRPC_VERSION
Require-Exit $LASTEXITCODE "Source verification failed"

# -----------------------------
# Step 6: Reassemble .tar.gz
# -----------------------------
Step "Reassembling source archive"
& bash.exe scripts/reassemble.sh $GRPC_VERSION
Require-Exit $LASTEXITCODE "Reassembly failed"

# -----------------------------
# Step 7: Extract source tree
# -----------------------------
Step "Extracting source tree"
$extractPath = Join-Path $ScriptDir "src\$EXTRACT_ROOT"
if (Test-Path $extractPath) {
    Info "src\$EXTRACT_ROOT already exists -- skipping extraction."
} else {
    & bash.exe -c "mkdir -p src && tar -xzf vendor/grpc-$GRPC_VERSION.tar.gz -C src/"
    Require-Exit $LASTEXITCODE "Extraction failed"
    Info "Source tree extracted to src\$EXTRACT_ROOT"
}

# -----------------------------
# Step 8: Copy source to dest
# (skipped if dest already populated — e.g. from install-prebuilt.ps1)
# -----------------------------
Step "Checking install location"
if (Test-Path $DEST_GRPC) {
    Info "Install directory exists at $DEST_GRPC"
} else {
    if (-not (Test-Path $extractPath)) { Die "Source folder not found: $extractPath" }
    Info "Copying gRPC source to $DEST_GRPC ..."
    & xcopy /E /I /Y "$extractPath\*" "$DEST_GRPC\" | Out-Null
    Require-Exit $LASTEXITCODE "Failed to copy gRPC source"
    Info "gRPC v$GRPC_VERSION copied to $DEST_GRPC"
}

# -----------------------------
# Step 9: Create demo directories
# -----------------------------
Step "Creating demo directories"
foreach ($d in @($DEMO_DIR, $DEMO_HELLO, $DEMO_PROTOS)) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Info "Created $d"
    }
}

# -----------------------------
# Step 10: Detect install type and build if needed
#
# Source build layout:  $DEST_GRPC\outputs\bin\grpc_cpp_plugin.exe
# Prebuilt layout:      $DEST_GRPC\bin\grpc_cpp_plugin.exe
#
# If prebuilt layout detected, populate outputs\ from bin\ and lib\.
# If neither found, run the full source build.
# -----------------------------
Step "Checking build status"

$pluginInOutputs = "$OUTPUT_DIR\bin\grpc_cpp_plugin.exe"
$pluginInBin     = "$DEST_GRPC\bin\grpc_cpp_plugin.exe"

if (Test-Path $pluginInOutputs) {
    # Source build layout already complete
    Info "Found grpc_cpp_plugin.exe in outputs\bin\ (source build layout)."
    $ans = Read-Host "Binaries present. Rebuild gRPC? (y/n)"
    if ($ans -notmatch '^[Yy]') {
        Info "Skipping gRPC build."
    } else {
        $needsBuild = $true
    }
} elseif (Test-Path $pluginInBin) {
    # Prebuilt layout — populate outputs\ from bin\ and lib\
    Info "Found grpc_cpp_plugin.exe in bin\ (prebuilt layout)."
    Info "Populating outputs\ from prebuilt install..."
    $outBin = "$OUTPUT_DIR\bin"
    $outLib = "$OUTPUT_DIR\lib"
    if (-not (Test-Path $outBin)) { New-Item -ItemType Directory -Path $outBin -Force | Out-Null }
    if (-not (Test-Path $outLib)) { New-Item -ItemType Directory -Path $outLib -Force | Out-Null }
    & xcopy /E /I /Y "$DEST_GRPC\bin\*" "$outBin\" | Out-Null
    & xcopy /E /I /Y "$DEST_GRPC\lib\*" "$outLib\" | Out-Null
    Info "outputs\ populated from prebuilt."
    $needsBuild = $false
} else {
    Warn "grpc_cpp_plugin.exe not found. Proceeding with source build..."
    $needsBuild = $true
}

if ($needsBuild) {
    Step "Building gRPC v$GRPC_VERSION (air-gap mode)"

    $cmakeBuildDir = "$DEST_GRPC\cmake\build"
    if (-not (Test-Path $cmakeBuildDir)) {
        New-Item -ItemType Directory -Path $cmakeBuildDir -Force | Out-Null
    }

    $buildScript = @"
@echo off
call "$VSDEVCMD" -arch=amd64
if errorlevel 1 exit /b 1
set CC=
set CXX=
cd /d "$cmakeBuildDir"
if errorlevel 1 exit /b 1
"$CmakeExe" -G Ninja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_CXX_STANDARD=17 ^
    -DCMAKE_INSTALL_PREFIX="$DEST_GRPC" ^
    -DgRPC_INSTALL=ON ^
    -DgRPC_BUILD_TESTS=OFF ^
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON ^
    -DgRPC_ABSL_PROVIDER=module ^
    -DgRPC_CARES_PROVIDER=module ^
    -DgRPC_PROTOBUF_PROVIDER=module ^
    -DgRPC_RE2_PROVIDER=module ^
    -DgRPC_SSL_PROVIDER=module ^
    -DgRPC_ZLIB_PROVIDER=module ^
    ..\..
if errorlevel 1 exit /b 1
"$CmakeExe" --build . --target install -j 4
if errorlevel 1 exit /b 1
"@

    $tmpBat = [System.IO.Path]::GetTempFileName() + ".bat"
    [System.IO.File]::WriteAllText($tmpBat, $buildScript, [System.Text.Encoding]::ASCII)

    Info "Activating VS environment (amd64) and running cmake build..."
    Info "Air-gap mode: all dependencies sourced from third_party/ -- no network access."
    cmd.exe /c "`"$tmpBat`""
    $buildExit = $LASTEXITCODE
    Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue
    Require-Exit $buildExit "gRPC build failed"
    Info "gRPC build complete."

    # Populate outputs\ after source build
    Step "Copying binaries to outputs folder"
    $outBin = "$OUTPUT_DIR\bin"
    $outLib = "$OUTPUT_DIR\lib"
    if (-not (Test-Path $outBin)) { New-Item -ItemType Directory -Path $outBin -Force | Out-Null }
    if (-not (Test-Path $outLib)) { New-Item -ItemType Directory -Path $outLib -Force | Out-Null }
    & xcopy /E /I /Y "$DEST_GRPC\bin\*" "$outBin\" | Out-Null
    & xcopy /E /I /Y "$DEST_GRPC\lib\*" "$outLib\" | Out-Null
    Info "Binaries copied."
}

# -----------------------------
# Step 11: Copy HelloWorld demo files
# Source build has examples\ under DEST_GRPC.
# Prebuilt install does not include examples\ — copy from the extracted src tree.
# -----------------------------
Step "Copying HelloWorld demo files"

if (Test-Path $GRPC_EXAMPLES) {
    Info "Using examples from install directory."
    & xcopy /E /I /H /Y "$GRPC_EXAMPLES\*" "$DEMO_HELLO\" | Out-Null
    Require-Exit $LASTEXITCODE "Failed to copy HelloWorld demo files"
    if (-not (Test-Path "$LINK_CMAKE\common.cmake")) {
        & xcopy /E /I /H /Y "$TARGET_CMAKE\*" "$LINK_CMAKE\" | Out-Null
    }
} elseif (Test-Path "$extractPath\examples\cpp\helloworld") {
    Info "Using examples from extracted source tree."
    & xcopy /E /I /H /Y "$extractPath\examples\cpp\helloworld\*" "$DEMO_HELLO\" | Out-Null
    Require-Exit $LASTEXITCODE "Failed to copy HelloWorld demo files from src tree"
    $srcCmake = "$extractPath\examples\cpp\cmake"
    if ((Test-Path $srcCmake) -and (-not (Test-Path "$LINK_CMAKE\common.cmake"))) {
        & xcopy /E /I /H /Y "$srcCmake\*" "$LINK_CMAKE\" | Out-Null
    }
    # Copy proto for prebuilt path
    $srcProtos = "$extractPath\examples\protos"
    if (Test-Path $srcProtos) {
        if (-not (Test-Path "$DEST_GRPC\examples\protos")) {
            New-Item -ItemType Directory -Path "$DEST_GRPC\examples\protos" -Force | Out-Null
        }
        & xcopy /E /I /Y "$srcProtos\*" "$DEST_GRPC\examples\protos\" | Out-Null
    }
} else {
    Die "HelloWorld examples not found in install dir or source tree. Run setup.ps1 after extracting the source tarball."
}
Info "Demo files copied."

# -----------------------------
# Step 12: Patch HelloWorld CMakeLists.txt
# -----------------------------
Step "Updating HelloWorld CMakeLists.txt"
$cmakeListsPath = "$DEMO_HELLO\CMakeLists.txt"
$content = Get-Content $cmakeListsPath -Raw
$content = $content -replace [regex]::Escape('../../protos/helloworld.proto'), '../protos/helloworld.proto'
Set-Content $cmakeListsPath $content
Info "CMakeLists.txt updated."

# -----------------------------
# Step 13: Generate protobuf sources
# -----------------------------
Step "Generating protobuf sources"

# Resolve proto source — prefer DEST_GRPC examples, fall back to src tree
$protoSrc = "$DEST_GRPC\examples\protos\helloworld.proto"
if (-not (Test-Path $protoSrc)) {
    $protoSrc = "$extractPath\examples\protos\helloworld.proto"
}
if (-not (Test-Path $protoSrc)) { Die "helloworld.proto not found." }

Copy-Item $protoSrc "$DEMO_PROTOS\helloworld.proto" -Force
if (-not (Test-Path $GEN_DIR)) { New-Item -ItemType Directory -Path $GEN_DIR -Force | Out-Null }

$protocExe  = "$OUTPUT_DIR\bin\protoc.exe"
$grpcPlugin = "$OUTPUT_DIR\bin\grpc_cpp_plugin.exe"

& "$protocExe" -I "$DEMO_PROTOS" `
    --cpp_out="$GEN_DIR" `
    --grpc_out="$GEN_DIR" `
    "--plugin=protoc-gen-grpc=$grpcPlugin" `
    helloworld.proto
Require-Exit $LASTEXITCODE "Protoc generation failed"
Info "Protobuf sources generated."

# -----------------------------
# Step 14: Build HelloWorld demo
# -----------------------------
Step "Building HelloWorld demo"
if (Test-Path "$DEMO_HELLO\.build") {
    Remove-Item "$DEMO_HELLO\.build" -Recurse -Force
}
New-Item -ItemType Directory -Path "$DEMO_HELLO\.build" -Force | Out-Null

$demoScript = @"
@echo off
call "$VSDEVCMD" -arch=amd64
if errorlevel 1 exit /b 1
set CC=
set CXX=
cd /d "$DEMO_HELLO\.build"
if errorlevel 1 exit /b 1
"$CmakeExe" -G Ninja ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_PREFIX_PATH="$DEST_GRPC" ^
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON ^
    ..
if errorlevel 1 exit /b 1
"$CmakeExe" --build . -j 4
if errorlevel 1 exit /b 1
"@

$tmpDemo = [System.IO.Path]::GetTempFileName() + ".bat"
[System.IO.File]::WriteAllText($tmpDemo, $demoScript, [System.Text.Encoding]::ASCII)

Info "Building HelloWorld demo..."
cmd.exe /c "`"$tmpDemo`""
$demoExit = $LASTEXITCODE
Remove-Item $tmpDemo -Force -ErrorAction SilentlyContinue
Require-Exit $demoExit "Demo build failed"
Info "Demo built successfully."

# -----------------------------
# Done
# -----------------------------
Write-Host ""
Write-Host "*********************"
Write-Host " gRPC v$GRPC_VERSION -- Complete"
Write-Host " Install location : $DEST_GRPC"
Write-Host " Build outputs    : $OUTPUT_DIR"
Write-Host " Demo             : $DEMO_HELLO\.build\"
Write-Host "*********************"
Write-Host ""

Info "Launching greeter_server.exe..."
Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "cd '$DEMO_HELLO\.build'; .\greeter_server.exe"

Info "Launching greeter_client.exe..."
Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "cd '$DEMO_HELLO\.build'; .\greeter_client.exe"

Write-Host ""
Write-Host "Please verify that both server and client are running as expected."