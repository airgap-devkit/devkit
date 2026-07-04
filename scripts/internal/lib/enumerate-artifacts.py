#!/usr/bin/env python3
"""
scripts/internal/lib/enumerate-artifacts.py
List the artifact files a prebuilt manifest.json requires for a given platform,
one per line as "<filename>\t<sha256>".

Handles whole archives, installers/packages, split .part-* sets, and tools that
ship both an installer and a portable archive.

Usage:
    python3 enumerate-artifacts.py <manifest.json> <windows|linux|all>
"""
import json
import sys


def want_platform(key: str, want: str) -> bool:
    if want == "all":
        return True
    if want == "windows":
        return key == "windows"
    return key.startswith("linux")   # linux, linux-x64, ...


def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("usage: enumerate-artifacts.py <manifest.json> <windows|linux|all>\n")
        return 2
    manifest, want = sys.argv[1], sys.argv[2]
    try:
        d = json.load(open(manifest))
    except Exception as e:
        sys.stderr.write(f"skip (unreadable manifest): {manifest}: {e}\n")
        return 0

    for key, entry in (d.get("platforms") or {}).items():
        if not want_platform(key, want) or not isinstance(entry, dict):
            continue

        parts = entry.get("part_sha256")
        if parts:
            for name, sha in parts.items():
                print(f"{name}\t{sha}")
            continue

        # Whole file: the primary archive/installer/package.
        name = (entry.get("archive") or entry.get("installer")
                or entry.get("package") or entry.get("portable"))
        sha = (entry.get("sha256") or entry.get("installer_sha256")
               or entry.get("portable_sha256"))
        if name and sha:
            print(f"{name}\t{sha}")

        # Some tools list an installer AND a separate portable archive.
        portable = entry.get("portable")
        portable_sha = entry.get("portable_sha256")
        if portable and portable_sha and portable != name:
            print(f"{portable}\t{portable_sha}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
