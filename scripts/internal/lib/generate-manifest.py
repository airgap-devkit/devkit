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

EXT_TAR_GZ = ".tar.gz"
EXT_TAR_XZ = ".tar.xz"
PART_MARKER = ".part-"


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
    if fname.endswith(EXT_TAR_GZ) or fname.endswith(".tgz"):
        return f"tar -xzf {fname}"
    if fname.endswith(EXT_TAR_XZ):
        return f"tar -xJf {fname}"
    return ""


def _reassemble_cmd(base: str) -> str:
    """Return the command that concatenates parts and extracts the whole archive."""
    if base.endswith(".zip"):
        return f"cat {base}.part-* > {base} && unzip -o {base}"
    if base.endswith(EXT_TAR_GZ) or base.endswith(".tgz"):
        return f"cat {base}.part-* | tar -xz"
    if base.endswith(EXT_TAR_XZ):
        return f"cat {base}.part-* | tar -xJ"
    return f"cat {base}.part-* > {base}"


def _payload_key(ext: str) -> str:
    """Map a bare file extension to its manifest payload key."""
    if ext in ("rpm", "deb"):
        return "package"
    if ext == "exe":
        return "installer"
    return "archive"


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
    return {_payload_key(ext): fname, "sha256": sha}


def _build_platforms(dest_dir: str, all_entries: list) -> tuple:
    """Build the platforms map from staged files. Returns (platforms, has_parts)."""
    part_files = [f for f in all_entries if PART_MARKER in f]
    whole_files = [f for f in all_entries if PART_MARKER not in f]

    # Group part files by base archive name
    parts_by_base: dict[str, dict] = {}
    for pf in sorted(part_files):
        base = pf[: pf.index(PART_MARKER)]
        parts_by_base.setdefault(base, {})[pf] = sha256file(os.path.join(dest_dir, pf))

    platforms: dict = {}
    for fn in sorted(whole_files):
        entry = make_entry(fn, sha256file(os.path.join(dest_dir, fn)))
        platforms.setdefault("linux-x64" if is_linux(fn) else "windows", entry)
    for base, parts in sorted(parts_by_base.items()):
        entry = make_entry(base, parts=parts)
        platforms.setdefault("linux-x64" if is_linux(base) else "windows", entry)

    return platforms, bool(part_files)


def _archive_format(entry: dict) -> str:
    """Return the canonical compression suffix for a manifest entry (or "")."""
    name = entry.get("archive") or entry.get("package") or entry.get("installer") or ""
    for ext in (EXT_TAR_GZ, EXT_TAR_XZ, ".zip", ".rpm", ".deb", ".exe"):
        if name.endswith(ext):
            return ext.lstrip(".")
    return ""


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

    # Canonical staged formats: .zip (Windows) / .tar.gz (Linux). Report whichever
    # formats actually appear so the manifest self-documents without assuming xz.
    platforms, has_parts = _build_platforms(dest_dir, all_entries)
    formats = sorted({f for f in (_archive_format(e) for e in platforms.values()) if f})

    manifest: dict = {
        "tool":        tool_id,
        "version":     version,
        "source":      f"https://github.com/{github_repo}/releases/tag/{tag}" if github_repo else "",
        "platforms":   platforms,
        "compression": "+".join(formats) if formats else "",
    }
    if has_parts:
        manifest["part_size_mb"] = 50

    manifest_path = os.path.join(dest_dir, "manifest.json")
    with open(manifest_path, "w") as mf:
        json.dump(manifest, mf, indent=2)
        mf.write("\n")

    print(f"  OK  {manifest_path}  ({len(platforms)} platform(s))")


if __name__ == "__main__":
    main()
