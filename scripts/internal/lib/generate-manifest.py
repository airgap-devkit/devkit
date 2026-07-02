#!/usr/bin/env python3
"""
scripts/internal/lib/generate-manifest.py
Generates prebuilt/<category>/<tool>/<version>/manifest.json by scanning
the staged directory for whole files and split-part archives.

Usage:
    python3 generate-manifest.py <dest_dir> <tool_id> <version> <github_repo> <tag>

Handles:
  - Whole archives (.tar.xz, .exe, .rpm, .deb) → direct sha256
  - Split-part files (*.part-aa, *.part-ab, ...) → part_sha256 map
  - Platform assignment by filename heuristic (linux vs windows)
"""

import hashlib
import json
import os
import sys


def sha256file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def is_linux(name: str) -> bool:
    n = name.lower()
    return "linux" in n or n.endswith(".rpm") or n.endswith(".deb")


def make_entry(fname: str, sha: str = None, parts: dict = None) -> dict:
    if parts:
        return {
            "archive": fname,
            "part_sha256": dict(sorted(parts.items())),
            "reassemble": f"cat {fname}.part-* | tar -xJ",
        }
    if fname.endswith(".tar.xz"):
        return {"archive": fname, "sha256": sha, "reassemble": f"tar -xJf {fname}"}
    ext = fname.rsplit(".", 1)[-1]
    key = "package" if ext in ("rpm", "deb") else ("installer" if ext == "exe" else "archive")
    return {key: fname, "sha256": sha}


def main():
    if len(sys.argv) < 6:
        print(f"Usage: {sys.argv[0]} <dest_dir> <tool_id> <version> <github_repo> <tag>",
              file=sys.stderr)
        sys.exit(1)

    dest_dir, tool_id, version, github_repo, tag = sys.argv[1:6]

    all_entries = [
        f for f in os.listdir(dest_dir)
        if not f.startswith(".") and f != "manifest.json"
    ]
    part_files  = [f for f in all_entries if ".part-" in f]
    whole_files = [f for f in all_entries if ".part-" not in f]

    # Group part files by base archive name
    parts_by_base: dict[str, dict] = {}
    for pf in sorted(part_files):
        base = pf[: pf.index(".part-")]
        parts_by_base.setdefault(base, {})[pf] = sha256file(os.path.join(dest_dir, pf))

    platforms: dict = {}

    for fn in sorted(whole_files):
        entry = make_entry(fn, sha256file(os.path.join(dest_dir, fn)))
        plat  = "linux-x64" if is_linux(fn) else "windows"
        platforms.setdefault(plat, entry)

    for base, parts in sorted(parts_by_base.items()):
        entry = make_entry(base, parts=parts)
        plat  = "linux-x64" if is_linux(base) else "windows"
        platforms.setdefault(plat, entry)

    manifest: dict = {
        "tool":        tool_id,
        "version":     version,
        "source":      f"https://github.com/{github_repo}/releases/tag/{tag}" if github_repo else "",
        "platforms":   platforms,
        "compression": "tar.xz",
    }
    if part_files:
        manifest["part_size_mb"] = 50

    manifest_path = os.path.join(dest_dir, "manifest.json")
    with open(manifest_path, "w") as mf:
        json.dump(manifest, mf, indent=2)
        mf.write("\n")

    print(f"  OK  {manifest_path}  ({len(platforms)} platform(s))")


if __name__ == "__main__":
    main()
