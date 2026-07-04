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
    # Beyond bare "linux": distro/host tags (e.g. llvm-mingw's *ubuntu* build).
    linux_tags = ("linux", "ubuntu", "debian", "rhel", "el8", "el9", "musl", "-gnu")
    return any(t in n for t in linux_tags) or n.endswith(".rpm") or n.endswith(".deb")


def _extract_cmd(fname: str) -> str:
    """Return the OS-native extraction command for a whole archive."""
    if fname.endswith(".zip"):
        return f"unzip -o {fname}"
    if fname.endswith(".tar.gz") or fname.endswith(".tgz"):
        return f"tar -xzf {fname}"
    if fname.endswith(".tar.xz"):
        return f"tar -xJf {fname}"
    return ""


def _reassemble_cmd(base: str) -> str:
    """Return the command that concatenates parts and extracts the whole archive."""
    if base.endswith(".zip"):
        return f"cat {base}.part-* > {base} && unzip -o {base}"
    if base.endswith(".tar.gz") or base.endswith(".tgz"):
        return f"cat {base}.part-* | tar -xz"
    if base.endswith(".tar.xz"):
        return f"cat {base}.part-* | tar -xJ"
    return f"cat {base}.part-* > {base}"


def make_entry(fname: str, sha: str = None, parts: dict = None) -> dict:
    if parts:
        return {
            "archive": fname,
            "part_sha256": dict(sorted(parts.items())),
            "reassemble": _reassemble_cmd(fname),
        }
    cmd = _extract_cmd(fname)
    if cmd:
        return {"archive": fname, "sha256": sha, "reassemble": cmd}
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
        and os.path.isfile(os.path.join(dest_dir, f))   # skip subdirs (e.g. wheels/)
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

    # Canonical staged formats: .zip (Windows) / .tar.gz (Linux). Report whichever
    # formats actually appear so the manifest self-documents without assuming xz.
    def _fmt(entry: dict) -> str:
        name = entry.get("archive") or entry.get("package") or entry.get("installer") or ""
        for ext in (".tar.gz", ".tar.xz", ".zip", ".rpm", ".deb", ".exe"):
            if name.endswith(ext):
                return ext.lstrip(".")
        return ""

    formats = sorted({f for f in (_fmt(e) for e in platforms.values()) if f})

    manifest: dict = {
        "tool":        tool_id,
        "version":     version,
        "source":      f"https://github.com/{github_repo}/releases/tag/{tag}" if github_repo else "",
        "platforms":   platforms,
        "compression": "+".join(formats) if formats else "",
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
