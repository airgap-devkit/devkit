#!/usr/bin/env python3
"""
scripts/fetch-vscode-extensions.py

Run on an internet-connected machine to mirror VS Code extensions as .vsix files
for later offline installation via dev-tools/vscode-extensions/setup.sh.

USAGE
-----
  # Mirror whatever is installed in your local VS Code right now:
  python3 scripts/fetch-vscode-extensions.py --from-installed

  # Mirror a specific list of extension IDs:
  python3 scripts/fetch-vscode-extensions.py ms-vscode.cpptools ms-python.python

  # Choose output dir and target platforms:
  python3 scripts/fetch-vscode-extensions.py --from-installed \\
      --out dev-tools/vscode-extensions/vendor \\
      --platforms win32-x64 linux-x64

  # Dry-run (print what would be downloaded, no files written):
  python3 scripts/fetch-vscode-extensions.py --from-installed --dry-run

OUTPUT
------
  <out>/
    publisher.name-version-platform.vsix   (or universal)
    ...
  manifest-new.json   — drop-in replacement for dev-tools/vscode-extensions/manifest.json

SPLIT
-----
  Files larger than SPLIT_THRESHOLD_MB are automatically split into <filename>.part-aa,
  .part-ab, ... matching the format setup.sh expects.
"""

import argparse
import hashlib
import json
import math
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

MARKETPLACE_QUERY_URL = (
    "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
)
MARKETPLACE_DOWNLOAD_URL = (
    "https://marketplace.visualstudio.com/_apis/public/gallery/publishers"
    "/{publisher}/vsextensions/{name}/{version}/vspackage"
)

SPLIT_THRESHOLD_MB = 95
SPLIT_CHUNK_BYTES = SPLIT_THRESHOLD_MB * 1024 * 1024

# Platforms that may have dedicated .vsix builds in the marketplace.
# "universal" means no targetPlatform query param.
KNOWN_PLATFORMS = ["universal", "win32-x64", "linux-x64", "darwin-x64", "alpine-x64"]

# ---------------------------------------------------------------------------
# Marketplace API
# ---------------------------------------------------------------------------

def _query_marketplace(ext_ids: list[str]) -> dict:
    """
    Returns a dict of ext_id -> {publisher, name, latest_version,
    platform_versions: {plat: version}}.
    """
    criteria = [{"filterType": 7, "value": eid} for eid in ext_ids]
    payload = json.dumps({
        "filters": [{"criteria": criteria, "pageSize": 100}],
        "flags": 0x200 | 0x100 | 0x80 | 0x2 | 0x1,  # versions + files + categories + assets + latest
    }).encode()

    req = urllib.request.Request(
        MARKETPLACE_QUERY_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json;api-version=7.1-preview.1",
            "User-Agent": "airgap-cpp-devkit/fetch-vscode-extensions",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp)

    result = {}
    for ext in data.get("results", [{}])[0].get("extensions", []):
        publisher = ext["publisher"]["publisherName"]
        name      = ext["extensionName"]
        full_id   = f"{publisher}.{name}"

        # The first version entry is the latest universal build.
        # Additional entries may be platform-specific (targetPlatform field).
        versions     = ext.get("versions", [])
        plat_versions: dict[str, str] = {}

        for v in versions:
            ver  = v["version"]
            plat = v.get("targetPlatform") or "universal"
            if plat not in plat_versions:          # first occurrence = latest
                plat_versions[plat] = ver

        result[full_id.lower()] = {
            "publisher": publisher,
            "name":      name,
            "full_id":   full_id,
            "platform_versions": plat_versions,
        }

    return result


# ---------------------------------------------------------------------------
# Download helpers
# ---------------------------------------------------------------------------

def _download_url(publisher: str, name: str, version: str, platform: str) -> str:
    base = MARKETPLACE_DOWNLOAD_URL.format(
        publisher=publisher, name=name, version=version
    )
    if platform != "universal":
        base += f"?targetPlatform={platform}"
    return base


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _split_file(path: Path) -> list[dict]:
    """Split path into <path>.part-aa, .part-ab, ... Return list of part dicts."""
    size   = path.stat().st_size
    n_parts = math.ceil(size / SPLIT_CHUNK_BYTES)
    suffix_gen = _alpha_suffixes()
    parts = []

    with open(path, "rb") as src:
        for _ in range(n_parts):
            suffix     = next(suffix_gen)
            part_path  = Path(str(path) + f".part-{suffix}")
            chunk      = src.read(SPLIT_CHUNK_BYTES)
            part_path.write_bytes(chunk)
            parts.append({
                "filename": part_path.name,
                "sha256":   _sha256(part_path),
            })
            print(f"    split → {part_path.name}  ({len(chunk)/1024/1024:.1f} MB)")

    return parts


def _alpha_suffixes():
    """Yields aa, ab, ac, ..., az, ba, bb, ..."""
    import string
    for a in string.ascii_lowercase:
        for b in string.ascii_lowercase:
            yield a + b


def _download(url: str, dest: Path, label: str) -> bool:
    print(f"  ↓ {label}")
    print(f"    {url}")
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "airgap-cpp-devkit/fetch-vscode-extensions"},
        )
        with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as out:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            while chunk := resp.read(65536):
                out.write(chunk)
                downloaded += len(chunk)
                if total:
                    pct = downloaded * 100 // total
                    print(f"\r    {downloaded/1024/1024:.1f} / {total/1024/1024:.1f} MB  ({pct}%)", end="", flush=True)
            print()
        return True
    except urllib.error.HTTPError as e:
        print(f"    [skip] HTTP {e.code} — no {label} variant")
        if dest.exists():
            dest.unlink()
        return False
    except Exception as exc:
        print(f"    [error] {exc}")
        if dest.exists():
            dest.unlink()
        return False


# ---------------------------------------------------------------------------
# Installed-extension detection
# ---------------------------------------------------------------------------

def _get_installed_extensions() -> list[str]:
    """Return list of extension IDs from the local VS Code installation."""
    for candidate in ["code", "code-insiders"]:
        try:
            r = subprocess.run(
                [candidate, "--list-extensions"],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                ids = [l.strip() for l in r.stdout.splitlines() if l.strip()]
                print(f"  Detected {len(ids)} extension(s) via '{candidate}'")
                return ids
        except FileNotFoundError:
            continue
    print("[WARN] 'code' not found on PATH - cannot auto-detect installed extensions.")
    print("       Pass extension IDs explicitly or ensure VS Code is on PATH.")
    return []


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="Mirror VS Code extensions as .vsix for offline installation."
    )
    ap.add_argument(
        "extensions",
        nargs="*",
        metavar="publisher.name",
        help="Extension IDs to download (e.g. ms-vscode.cpptools)",
    )
    ap.add_argument(
        "--from-installed",
        action="store_true",
        help="Add all extensions currently installed in local VS Code",
    )
    ap.add_argument(
        "--out",
        default="dev-tools/vscode-extensions/vendor",
        metavar="DIR",
        help="Output directory for .vsix files (default: dev-tools/vscode-extensions/vendor)",
    )
    ap.add_argument(
        "--platforms",
        nargs="+",
        default=["win32-x64", "linux-x64"],
        metavar="PLAT",
        help="Platform-specific variants to download (default: win32-x64 linux-x64). "
             "Universal builds are always included when available.",
    )
    ap.add_argument(
        "--no-split",
        action="store_true",
        help="Skip splitting large files (> 95 MB)",
    )
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be downloaded without writing any files",
    )
    args = ap.parse_args()

    # Collect extension IDs
    ext_ids: list[str] = list(args.extensions)
    if args.from_installed:
        ext_ids = list(dict.fromkeys(ext_ids + _get_installed_extensions()))  # dedup, preserve order

    if not ext_ids:
        ap.error("No extensions specified. Pass IDs as arguments or use --from-installed.")

    out_dir = Path(args.out)
    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nQuerying VS Code marketplace for {len(ext_ids)} extension(s)...")
    try:
        info = _query_marketplace(ext_ids)
    except Exception as exc:
        sys.exit(f"[ERROR] Marketplace query failed: {exc}")

    manifest_entries: list[dict] = []
    want_platforms = set(args.platforms)

    for eid in ext_ids:
        eid_lower = eid.lower()
        if eid_lower not in info:
            print(f"\n[WARN] '{eid}' not found in marketplace — skipping")
            continue

        meta       = info[eid_lower]
        publisher  = meta["publisher"]
        name       = meta["name"]
        full_id    = meta["full_id"]
        plat_vers  = meta["platform_versions"]

        print(f"\n-- {full_id}")

        # Determine which (platform, version) pairs to download
        downloads: list[tuple[str, str]] = []  # (platform, version)

        if "universal" in plat_vers:
            downloads.append(("universal", plat_vers["universal"]))

        for plat in sorted(want_platforms):
            if plat in plat_vers:
                downloads.append((plat, plat_vers[plat]))
            elif "universal" not in plat_vers:
                # No universal and no platform build → try anyway (may 404)
                latest_ver = next(iter(plat_vers.values())) if plat_vers else "latest"
                downloads.append((plat, latest_ver))

        if not downloads:
            print(f"  [WARN] No version info — skipping")
            continue

        for platform, version in downloads:
            safe_plat = f"-{platform}" if platform != "universal" else ""
            filename  = f"{full_id}-{version}{safe_plat}.vsix"
            dest      = out_dir / filename
            url       = _download_url(publisher, name, version, platform)

            if args.dry_run:
                print(f"  [dry-run] Would download: {filename}")
                print(f"            {url}")
                manifest_entries.append({
                    "id": full_id, "name": name, "publisher": publisher,
                    "version": version, "platform": platform,
                    "filename": filename, "sha256": "DRY_RUN", "split": False,
                    "marketplace_url": f"https://marketplace.visualstudio.com/items?itemName={full_id}",
                })
                continue

            # Skip if already downloaded and non-zero
            if dest.exists() and dest.stat().st_size > 0:
                print(f"  [cached] {filename}")
                sha = _sha256(dest)
            else:
                ok = _download(url, dest, f"{filename} ({platform})")
                if not ok:
                    continue
                sha = _sha256(dest)
                print(f"    sha256: {sha}")

            size_mb = dest.stat().st_size / 1024 / 1024
            entry: dict = {
                "id": full_id,
                "name": name,
                "publisher": publisher,
                "version": version,
                "platform": platform,
                "filename": filename,
                "sha256": sha,
                "split": False,
                "marketplace_url": f"https://marketplace.visualstudio.com/items?itemName={full_id}",
            }

            if not args.no_split and size_mb > SPLIT_THRESHOLD_MB:
                print(f"    {size_mb:.1f} MB > {SPLIT_THRESHOLD_MB} MB threshold — splitting...")
                parts = _split_file(dest)
                dest.unlink()  # remove assembled file; setup.sh will cat it back
                entry["split"]  = True
                entry["parts"]  = parts
                entry["sha256"] = sha  # sha of the assembled file

            manifest_entries.append(entry)

    # Write manifest
    manifest_out = out_dir / "manifest-new.json" if not args.dry_run else None
    manifest = {
        "_comment": (
            "Generated by scripts/fetch-vscode-extensions.py. "
            "Copy relevant entries into dev-tools/vscode-extensions/manifest.json."
        ),
        "schema_version": "1.0",
        "generated": __import__("datetime").date.today().isoformat(),
        "extensions": manifest_entries,
    }
    manifest_json = json.dumps(manifest, indent=2)

    if args.dry_run or manifest_out is None:
        print("\n-- Manifest (dry-run) --")
        print(manifest_json)
    else:
        manifest_out.write_text(manifest_json)
        print(f"\n  Manifest written to: {manifest_out}")
        print("  Review it, then replace dev-tools/vscode-extensions/manifest.json.")

    print("\nDone.")


if __name__ == "__main__":
    main()
