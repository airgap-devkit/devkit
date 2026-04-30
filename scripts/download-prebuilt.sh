#!/usr/bin/env bash
# scripts/download-prebuilt.sh
# Downloads, repackages, and stages all updated prebuilt binaries.
# Run from the repo root on an internet-connected machine.
#
# Usage:
#   bash scripts/download-prebuilt.sh [--small] [--large]
#   --small   Only small/medium tools (cmake, notepadpp, 7zip, conan, servy)
#   --large   Only large tools (llvm, dotnet, vscode) — can take 30+ min
#   (no flags) runs all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREBUILT_DIR="$REPO_ROOT/prebuilt"
TMP_DIR=$(mktemp -d)
PART_SIZE="50m"

RUN_SMALL=true
RUN_LARGE=true
for arg in "$@"; do
  case "$arg" in
    --small) RUN_LARGE=false ;;
    --large) RUN_SMALL=false ;;
  esac
done

trap 'echo "Cleaning up tmp..."; rm -rf "$TMP_DIR"' EXIT

log()  { echo ""; echo "==> $*"; }
ok()   { echo "    [OK] $*"; }
fail() { echo ""; echo "ERROR: $*" >&2; exit 1; }

# Download with curl; skip if already present
dl() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        ok "Already present: $(basename "$dest")"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    echo "    Downloading $(basename "$dest")..."
    curl -fL --progress-bar -o "$dest" "$url" \
        || fail "Download failed: $url"
}

sha256() { sha256sum "$1" | awk '{print $1}'; }

# Repackage a zip or tar.gz into tar.xz, stripping the top-level wrapper dir.
# cmake, conan Windows, etc. all wrap contents in cmake-VERSION-platform/ —
# we strip that so bin/cmake lands directly in $PREFIX after extraction.
repack_xz_strip1() {
    local src="$1" dest="$2"
    local tmp; tmp="$(mktemp -d -p "$TMP_DIR")"
    echo "    Extracting $(basename "$src")..."
    case "$src" in
        *.zip)           unzip -q "$src" -d "$tmp/raw" ;;
        *.tar.gz|*.tgz)  mkdir -p "$tmp/raw"; tar -xzf "$src" -C "$tmp/raw" ;;
        *)               fail "repack_xz_strip1: unsupported format: $src" ;;
    esac
    # Strip one level: use the single top-level dir as the new root
    local topdir
    topdir="$(ls "$tmp/raw" | head -1)"
    echo "    Repackaging → $(basename "$dest") (xz, no wrapper)..."
    tar -cJf "$dest" -C "$tmp/raw/$topdir" .
    rm -rf "$tmp"
}

# Repackage a zip/tar.gz as tar.xz WITHOUT stripping (contents already at root)
repack_xz_flat() {
    local src="$1" dest="$2"
    local tmp; tmp="$(mktemp -d -p "$TMP_DIR")"
    echo "    Extracting $(basename "$src")..."
    case "$src" in
        *.zip)           unzip -q "$src" -d "$tmp/raw" ;;
        *.tar.gz|*.tgz)  mkdir -p "$tmp/raw"; tar -xzf "$src" -C "$tmp/raw" ;;
        *)               fail "repack_xz_flat: unsupported format: $src" ;;
    esac
    echo "    Repackaging → $(basename "$dest") (xz, flat)..."
    tar -cJf "$dest" -C "$tmp/raw" .
    rm -rf "$tmp"
}

# Split file into 50MB parts and delete the source
split_parts() {
    local src="$1" dir="$2" basename="$3"
    echo "    Splitting into ${PART_SIZE} parts..."
    split -b "$PART_SIZE" "$src" "$dir/${basename}.part-"
    rm -f "$src"
    ok "Parts written: $dir/${basename}.part-*"
}

# ─────────────────────────────────────────────────────────────────────────────
# SMALL / MEDIUM DOWNLOADS
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$RUN_SMALL" == true ]]; then

  # ── CMake 4.3.2 (~50MB download, ~45MB tar.xz) ─────────────────────────────
  log "CMake 4.3.2"
  CMAKE_DIR="$PREBUILT_DIR/build-tools/cmake/4.3.2"
  mkdir -p "$CMAKE_DIR"

  dl "https://github.com/Kitware/CMake/releases/download/v4.3.2/cmake-4.3.2-windows-x86_64.zip" \
     "$TMP_DIR/cmake-win.zip"
  repack_xz_strip1 "$TMP_DIR/cmake-win.zip" "$CMAKE_DIR/cmake-4.3.2-windows-x86_64.tar.xz"

  dl "https://github.com/Kitware/CMake/releases/download/v4.3.2/cmake-4.3.2-linux-x86_64.tar.gz" \
     "$TMP_DIR/cmake-lin.tar.gz"
  repack_xz_strip1 "$TMP_DIR/cmake-lin.tar.gz" "$CMAKE_DIR/cmake-4.3.2-linux-x86_64.tar.xz"

  WIN_SHA=$(sha256 "$CMAKE_DIR/cmake-4.3.2-windows-x86_64.tar.xz")
  LIN_SHA=$(sha256 "$CMAKE_DIR/cmake-4.3.2-linux-x86_64.tar.xz")
  cat > "$CMAKE_DIR/manifest.json" << MEOF
{
  "tool": "cmake",
  "version": "4.3.2",
  "source": "https://github.com/Kitware/CMake/releases/tag/v4.3.2",
  "platforms": {
    "windows": {
      "archive": "cmake-4.3.2-windows-x86_64.tar.xz",
      "sha256": "$WIN_SHA",
      "reassemble": "tar -xJf cmake-4.3.2-windows-x86_64.tar.xz"
    },
    "linux-x64": {
      "archive": "cmake-4.3.2-linux-x86_64.tar.xz",
      "sha256": "$LIN_SHA",
      "reassemble": "tar -xJf cmake-4.3.2-linux-x86_64.tar.xz"
    }
  },
  "compression": "tar.xz"
}
MEOF
  ok "CMake 4.3.2 complete."

  # ── Notepad++ 8.9.4 (~6MB) ──────────────────────────────────────────────────
  log "Notepad++ 8.9.4"
  NPP_DIR="$PREBUILT_DIR/dev-tools/notepadpp/8.9.4"
  mkdir -p "$NPP_DIR"

  dl "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.4/npp.8.9.4.portable.x64.zip" \
     "$NPP_DIR/npp.8.9.4.portable.x64.zip"
  dl "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.4/npp.8.9.4.Installer.x64.exe" \
     "$NPP_DIR/npp.8.9.4.Installer.x64.exe"

  PORTABLE_SHA=$(sha256 "$NPP_DIR/npp.8.9.4.portable.x64.zip")
  INST_SHA=$(sha256     "$NPP_DIR/npp.8.9.4.Installer.x64.exe")
  cat > "$NPP_DIR/manifest.json" << MEOF
{
  "tool": "notepadpp",
  "version": "8.9.4",
  "source": "https://notepad-plus-plus.org/downloads/v8.9.4/",
  "platforms": {
    "windows": {
      "installer": "npp.8.9.4.Installer.x64.exe",
      "installer_sha256": "$INST_SHA",
      "portable": "npp.8.9.4.portable.x64.zip",
      "portable_sha256": "$PORTABLE_SHA",
      "install_portable": "unzip npp.8.9.4.portable.x64.zip -d <prefix>"
    }
  },
  "compression": "zip",
  "notes": "setup.sh uses the portable zip by default (no admin required)."
}
MEOF
  ok "Notepad++ 8.9.4 complete."

  # ── 7-Zip 26.01 (~2MB) ──────────────────────────────────────────────────────
  log "7-Zip 26.01"
  SZIP_DIR="$PREBUILT_DIR/dev-tools/7zip/26.01"
  mkdir -p "$SZIP_DIR"

  dl "https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.exe" \
     "$SZIP_DIR/7z2601-x64.exe"
  dl "https://github.com/ip7z/7zip/releases/download/26.01/7z2601-linux-x64.tar.xz" \
     "$SZIP_DIR/7z2601-linux-x64.tar.xz"

  WIN_SHA=$(sha256 "$SZIP_DIR/7z2601-x64.exe")
  LIN_SHA=$(sha256 "$SZIP_DIR/7z2601-linux-x64.tar.xz")
  cat > "$SZIP_DIR/manifest.json" << MEOF
{
  "tool": "7zip",
  "version": "26.01",
  "source": "https://www.7-zip.org/download.html",
  "platforms": {
    "windows": {
      "installer": "7z2601-x64.exe",
      "sha256": "$WIN_SHA",
      "install": "NSIS silent install"
    },
    "linux-x64": {
      "archive": "7z2601-linux-x64.tar.xz",
      "sha256": "$LIN_SHA",
      "reassemble": "tar -xJf 7z2601-linux-x64.tar.xz"
    }
  },
  "compression": "tar.xz"
}
MEOF
  ok "7-Zip 26.01 complete."

  # ── Conan 2.28.0 (~100MB Windows zip, ~50MB Linux tgz) ─────────────────────
  log "Conan 2.28.0"
  CONAN_DIR="$PREBUILT_DIR/dev-tools/conan/2.28.0"
  mkdir -p "$CONAN_DIR"

  dl "https://github.com/conan-io/conan/releases/download/2.28.0/conan-2.28.0-windows-x86_64.zip" \
     "$TMP_DIR/conan-win.zip"
  # conan zip root is a single conan-2.28.0-windows-x86_64/ wrapper — strip it
  repack_xz_strip1 "$TMP_DIR/conan-win.zip" "$CONAN_DIR/conan-2.28.0-windows-x86_64.tar.xz"

  dl "https://github.com/conan-io/conan/releases/download/2.28.0/conan-2.28.0-linux-x86_64.tgz" \
     "$CONAN_DIR/conan-2.28.0-linux-x86_64.tgz"

  WIN_SHA=$(sha256 "$CONAN_DIR/conan-2.28.0-windows-x86_64.tar.xz")
  LIN_SHA=$(sha256 "$CONAN_DIR/conan-2.28.0-linux-x86_64.tgz")
  cat > "$CONAN_DIR/manifest.json" << MEOF
{
  "tool": "conan",
  "version": "2.28.0",
  "source": "https://github.com/conan-io/conan/releases/tag/2.28.0",
  "platforms": {
    "windows": {
      "archive": "conan-2.28.0-windows-x86_64.tar.xz",
      "sha256": "$WIN_SHA",
      "reassemble": "tar -xJf conan-2.28.0-windows-x86_64.tar.xz"
    },
    "linux-x64": {
      "archive": "conan-2.28.0-linux-x86_64.tgz",
      "sha256": "$LIN_SHA",
      "reassemble": "tar -xzf conan-2.28.0-linux-x86_64.tgz -C <prefix>/bin --strip-components=1"
    }
  }
}
MEOF
  ok "Conan 2.28.0 complete."

  # ── Servy 8.3 ───────────────────────────────────────────────────────────────
  log "Servy 8.3"
  SERVY_DIR="$PREBUILT_DIR/dev-tools/servy/8.3"
  mkdir -p "$SERVY_DIR"

  dl "https://github.com/aelassas/servy/releases/download/v8.3/servy-8.3-x64-portable.7z" \
     "$TMP_DIR/servy-8.3-x64-portable.7z"

  # Extract .7z — try 7z binary (prebuilt or system), then 7zz
  SZIP_BIN=""
  for candidate in 7z 7zz "$PREBUILT_DIR/dev-tools/7zip/26.00/7z.exe" \
                          "$PREBUILT_DIR/dev-tools/7zip/26.01/7z.exe"; do
    if command -v "$candidate" &>/dev/null || [[ -f "$candidate" ]]; then
      SZIP_BIN="$candidate"; break
    fi
  done
  if [[ -z "$SZIP_BIN" ]]; then
    echo "    WARNING: 7z not found — cannot unpack Servy .7z." >&2
    echo "    Install 7-Zip first, then re-run: bash scripts/download-prebuilt.sh --small" >&2
    echo "    Storing raw .7z as fallback; Servy staging incomplete." >&2
    cp "$TMP_DIR/servy-8.3-x64-portable.7z" "$SERVY_DIR/"
  else
    mkdir -p "$TMP_DIR/servy-x"
    "$SZIP_BIN" e "$TMP_DIR/servy-8.3-x64-portable.7z" -o"$TMP_DIR/servy-x" -y > /dev/null
    echo "    Repackaging → servy-8.3-windows-x64.tar.xz..."
    tar -cJf "$SERVY_DIR/servy-8.3-windows-x64.tar.xz" -C "$TMP_DIR/servy-x" .
    WIN_SHA=$(sha256 "$SERVY_DIR/servy-8.3-windows-x64.tar.xz")
    cat > "$SERVY_DIR/manifest.json" << MEOF
{
  "tool": "servy",
  "version": "8.3",
  "source": "https://github.com/aelassas/servy/releases/tag/v8.3",
  "platforms": {
    "windows": {
      "archive": "servy-8.3-windows-x64.tar.xz",
      "sha256": "$WIN_SHA",
      "reassemble": "tar -xJf servy-8.3-windows-x64.tar.xz"
    }
  },
  "compression": "tar.xz",
  "notes": "Repackaged from servy-8.3-x64-portable.7z (.NET 8 variant)"
}
MEOF
    ok "Servy 8.3 complete."
  fi

fi  # RUN_SMALL

# ─────────────────────────────────────────────────────────────────────────────
# LARGE DOWNLOADS (LLVM ~1.2GB, dotnet ~400MB, VS Code ~200MB)
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$RUN_LARGE" == true ]]; then

  # ── LLVM/Clang 22.1.4 (Windows ~700MB, Linux ~500MB) ────────────────────────
  log "LLVM/Clang 22.1.4 — Windows (~700MB, downloading...)"
  LLVM_DIR="$PREBUILT_DIR/toolchains/llvm/22.1.4"
  mkdir -p "$LLVM_DIR"

  dl "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/clang%2Bllvm-22.1.4-x86_64-pc-windows-msvc.tar.xz" \
     "$TMP_DIR/llvm-win.tar.xz"
  split_parts "$TMP_DIR/llvm-win.tar.xz" "$LLVM_DIR" \
              "clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz"

  log "LLVM/Clang 22.1.4 — Linux (~500MB, downloading...)"
  dl "https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.4/LLVM-22.1.4-Linux-X64.tar.xz" \
     "$TMP_DIR/llvm-lin.tar.xz"
  split_parts "$TMP_DIR/llvm-lin.tar.xz" "$LLVM_DIR" \
              "LLVM-22.1.4-Linux-X64.tar.xz"

  WIN_PARTS_JSON="{"
  first=true
  for f in "$LLVM_DIR"/clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz.part-*; do
    [[ "$first" == false ]] && WIN_PARTS_JSON+=","
    WIN_PARTS_JSON+="\"$(basename "$f")\": \"$(sha256 "$f")\""
    first=false
  done
  WIN_PARTS_JSON+="}"

  LIN_PARTS_JSON="{"
  first=true
  for f in "$LLVM_DIR"/LLVM-22.1.4-Linux-X64.tar.xz.part-*; do
    [[ "$first" == false ]] && LIN_PARTS_JSON+=","
    LIN_PARTS_JSON+="\"$(basename "$f")\": \"$(sha256 "$f")\""
    first=false
  done
  LIN_PARTS_JSON+="}"

  cat > "$LLVM_DIR/manifest.json" << MEOF
{
  "tool": "llvm",
  "version": "22.1.4",
  "source": "https://github.com/llvm/llvm-project/releases/tag/llvmorg-22.1.4",
  "platforms": {
    "windows": {
      "archive": "clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz",
      "part_sha256": $WIN_PARTS_JSON,
      "reassemble": "cat clang+llvm-22.1.4-x86_64-pc-windows-msvc.tar.xz.part-* | tar -xJ"
    },
    "linux-x64": {
      "archive": "LLVM-22.1.4-Linux-X64.tar.xz",
      "part_sha256": $LIN_PARTS_JSON,
      "reassemble": "cat LLVM-22.1.4-Linux-X64.tar.xz.part-* | tar -xJ"
    }
  },
  "compression": "tar.xz",
  "part_size_mb": 50
}
MEOF
  ok "LLVM/Clang 22.1.4 complete."

  # ── .NET SDK 10.0.203 (Windows ~220MB, Linux ~170MB) ────────────────────────
  log ".NET SDK 10.0.203 — Windows (~220MB, downloading...)"
  DOTNET_DIR="$PREBUILT_DIR/languages/dotnet/10.0.203"
  mkdir -p "$DOTNET_DIR"

  dl "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.203/dotnet-sdk-10.0.203-win-x64.zip" \
     "$TMP_DIR/dotnet-win.zip"
  repack_xz_flat "$TMP_DIR/dotnet-win.zip" "$TMP_DIR/dotnet-win.tar.xz"
  split_parts "$TMP_DIR/dotnet-win.tar.xz" "$DOTNET_DIR" \
              "dotnet-sdk-10.0.203-win-x64.tar.xz"

  log ".NET SDK 10.0.203 — Linux (~170MB, downloading...)"
  dl "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.203/dotnet-sdk-10.0.203-linux-x64.tar.gz" \
     "$TMP_DIR/dotnet-lin.tar.gz"
  repack_xz_flat "$TMP_DIR/dotnet-lin.tar.gz" "$TMP_DIR/dotnet-lin.tar.xz"
  split_parts "$TMP_DIR/dotnet-lin.tar.xz" "$DOTNET_DIR" \
              "dotnet-sdk-10.0.203-linux-x64.tar.xz"

  WIN_PARTS_JSON="{"
  first=true
  for f in "$DOTNET_DIR"/dotnet-sdk-10.0.203-win-x64.tar.xz.part-*; do
    [[ "$first" == false ]] && WIN_PARTS_JSON+=","
    WIN_PARTS_JSON+="\"$(basename "$f")\": \"$(sha256 "$f")\""
    first=false
  done
  WIN_PARTS_JSON+="}"

  LIN_PARTS_JSON="{"
  first=true
  for f in "$DOTNET_DIR"/dotnet-sdk-10.0.203-linux-x64.tar.xz.part-*; do
    [[ "$first" == false ]] && LIN_PARTS_JSON+=","
    LIN_PARTS_JSON+="\"$(basename "$f")\": \"$(sha256 "$f")\""
    first=false
  done
  LIN_PARTS_JSON+="}"

  cat > "$DOTNET_DIR/manifest.json" << MEOF
{
  "tool": "dotnet",
  "version": "10.0.203",
  "source": "https://dotnet.microsoft.com/en-us/download/dotnet/10.0",
  "platforms": {
    "windows": {
      "archive": "dotnet-sdk-10.0.203-win-x64.tar.xz",
      "part_sha256": $WIN_PARTS_JSON,
      "reassemble": "cat dotnet-sdk-10.0.203-win-x64.tar.xz.part-* | tar -xJ"
    },
    "linux-x64": {
      "archive": "dotnet-sdk-10.0.203-linux-x64.tar.xz",
      "part_sha256": $LIN_PARTS_JSON,
      "reassemble": "cat dotnet-sdk-10.0.203-linux-x64.tar.xz.part-* | tar -xJ"
    }
  },
  "compression": "tar.xz",
  "part_size_mb": 50
}
MEOF
  ok ".NET SDK 10.0.203 complete."

  # ── VS Code 1.117.0 (Windows ~95MB, Linux RPM ~100MB) ───────────────────────
  log "VS Code 1.117.0 — Windows installer (~95MB, downloading...)"
  VSCODE_DIR="$PREBUILT_DIR/dev-tools/vscode/1.117.0"
  mkdir -p "$VSCODE_DIR"

  dl "https://update.code.visualstudio.com/1.117.0/win32-x64-user/stable" \
     "$VSCODE_DIR/VSCodeUserSetup-x64-1.117.0.exe"

  log "VS Code 1.117.0 — Linux RPM (~100MB, downloading...)"
  dl "https://update.code.visualstudio.com/1.117.0/linux-rpm-x64/stable" \
     "$VSCODE_DIR/code-1.117.0.el8.x86_64.rpm"

  WIN_SHA=$(sha256 "$VSCODE_DIR/VSCodeUserSetup-x64-1.117.0.exe")
  LIN_SHA=$(sha256 "$VSCODE_DIR/code-1.117.0.el8.x86_64.rpm")
  cat > "$VSCODE_DIR/manifest.json" << MEOF
{
  "tool": "vscode",
  "version": "1.117.0",
  "source": "https://code.visualstudio.com/updates/v1_117",
  "platforms": {
    "windows": {
      "installer": "VSCodeUserSetup-x64-1.117.0.exe",
      "sha256": "$WIN_SHA",
      "install": "InnoSetup silent: /VERYSILENT /NORESTART /MERGETASKS=!runcode"
    },
    "linux-x64": {
      "package": "code-1.117.0.el8.x86_64.rpm",
      "sha256": "$LIN_SHA",
      "install": "rpm -ivh --force code-1.117.0.el8.x86_64.rpm"
    }
  }
}
MEOF
  ok "VS Code 1.117.0 complete."

fi  # RUN_LARGE

echo ""
echo "============================================================"
echo " Prebuilt download complete."
echo " Next: bash scripts/generate-sbom.sh"
echo "============================================================"
