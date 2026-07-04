#!/usr/bin/env python3
# * UNCLASSIFIED                 UNCLASSIFIED                 UNCLASSIFIED *
# ==============================================================================
# Author: Nima Shafie [DS] (N56332)
# Script Name : checksum_generator.py
# Target Platforms: RHEL 8/9 (bash), Windows 10/11 (Git Bash / native Python)
# Compatibility : Python 3.6+ (standard library only, zero pip dependencies)
# ==============================================================================
"""Cross-platform file integrity manifest generator.

Recursively walks a directory tree, computes a CRC32 + cryptographic hash for
every file, and writes three artifacts into the output directory:

    checksums.txt   human-readable report grouped by directory
    checksums.csv   flat spreadsheet data (Excel-safe ="VALUE" wrapping)
    summary.txt     80-char aggregate receipt (counts, timing, delta metrics)

Supports delta comparison against a prior manifest (--baseline) and an
integrity gate that fails the process on drift (--verify / --fail-on-modified).
"""
import argparse
import csv
import fnmatch
import hashlib
import os
import subprocess
import sys
import time
import zlib

__version__ = "2.0.0"

# Exit codes
EXIT_OK = 0
EXIT_LOCK_ERRORS = 2      # one or more files could not be read (degrade to UNSTABLE)
EXIT_VERIFY_DRIFT = 3     # --verify found added/modified/deleted files
EXIT_FAIL_ON_MODIFIED = 4  # --fail-on-modified found modified/deleted files


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        prog="checksum_generator",
        description="Generate CRC32 + hash manifests for a directory tree, "
                    "with optional delta comparison against a baseline.",
    )
    parser.add_argument("--root", default=".",
                        help="Directory tree to scan (default: current directory).")
    parser.add_argument("--out-dir", default="checksums",
                        help="Directory to write manifest artifacts into "
                             "(default: ./checksums).")
    parser.add_argument("--ci", action="store_true",
                        help="CI mode: emit machine-readable metrics, suppress "
                             "the interactive progress bar.")
    parser.add_argument("--baseline", metavar="PATH", default="",
                        help="Prior manifest (.csv or .txt) to compute deltas "
                             "against. Does not affect exit code on its own.")
    parser.add_argument("--verify", metavar="PATH", default="",
                        help="Like --baseline, but exit non-zero if any file was "
                             "added, modified, or deleted relative to the manifest.")
    parser.add_argument("--fail-on-modified", action="store_true",
                        help="Exit non-zero if any baseline file was modified or "
                             "deleted (additions allowed).")
    parser.add_argument("--exclude", metavar="GLOB", action="append", default=[],
                        help="Glob of paths to skip (repeatable), e.g. '*.log'.")
    parser.add_argument("--include", metavar="GLOB", action="append", default=[],
                        help="If given, only paths matching one of these globs "
                             "are scanned (repeatable).")
    parser.add_argument("--algorithm", default="sha256",
                        choices=["sha256", "sha1", "sha512", "md5"],
                        help="Cryptographic hash algorithm (default: sha256). "
                             "CRC32 is always included.")
    parser.add_argument("--version", action="version",
                        version=f"%(prog)s {__version__}")
    return parser.parse_args(argv)


def detect_gateway():
    """Best-effort default-gateway lookup across Linux and Windows."""
    try:
        if sys.platform.startswith("win"):
            out = subprocess.check_output("route print 0.0.0.0", shell=True,
                                          stderr=subprocess.DEVNULL).decode("utf-8", "ignore")
            for line in out.splitlines():
                cols = line.split()
                if len(cols) >= 5 and cols[0] == "0.0.0.0":
                    return cols[2]
        else:
            out = subprocess.check_output(["ip", "route"],
                                          stderr=subprocess.DEVNULL).decode("utf-8", "ignore")
            for line in out.splitlines():
                if line.startswith("default"):
                    parts = line.split()
                    if "via" in parts:
                        return parts[parts.index("via") + 1]
    except Exception:
        pass
    return "unknown-gateway"


def compute_output_paths(out_dir):
    """Return (txt, csv, summary) paths, versioned per build when in Jenkins."""
    txt = os.path.join(out_dir, "checksums.txt")
    csv_path = os.path.join(out_dir, "checksums.csv")
    summary = os.path.join(out_dir, "summary.txt")

    build_number = os.environ.get("BUILD_NUMBER")
    if build_number:
        branch = os.environ.get("BRANCH_NAME") or os.environ.get("GIT_BRANCH") or "local"
        safe_branch = "".join(c if c.isalnum() or c in "_-" else "_" for c in branch)
        suffix = f"-{safe_branch}-b{build_number}"
        txt = os.path.join(out_dir, f"checksums{suffix}.txt")
        csv_path = os.path.join(out_dir, f"checksums{suffix}.csv")
        summary = os.path.join(out_dir, f"summary{suffix}.txt")
    return txt, csv_path, summary


def _unwrap(cell):
    """Strip the Excel-safe ="VALUE" wrapper produced in the CSV output."""
    cell = cell.strip()
    if cell.startswith('="') and cell.endswith('"'):
        cell = cell[2:-1]
    # A leading '/' guard is added to values that begin with a spreadsheet
    # control character; drop it so the stored path round-trips cleanly.
    if cell.startswith("/") and len(cell) > 1 and cell[1] in "0=+-":
        cell = cell[1:]
    return cell


def parse_baseline(baseline_file):
    """Parse a prior manifest into {clean_path: {'crc':..., 'sha':...}}.

    Handles both the Excel-safe CSV format and the whitespace-aligned text
    format. Text lines are parsed from the right so paths containing spaces
    survive intact.
    """
    manifests = {}
    if not baseline_file or not os.path.isfile(baseline_file):
        return manifests

    is_csv = baseline_file.lower().endswith(".csv")
    try:
        with open(baseline_file, "r", encoding="utf-8", errors="ignore") as bf:
            for line in bf:
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or stripped.startswith("="):
                    continue
                if ("FILE PATH" in stripped or "Cross-Platform" in stripped
                        or "Generated:" in stripped or "Gateway:" in stripped):
                    continue

                if is_csv:
                    row = next(csv.reader([stripped]))
                    if len(row) < 3:
                        continue
                    path = _unwrap(row[0])
                    crc = _unwrap(row[1])
                    sha = _unwrap(row[2])
                else:
                    # Drop a trailing "[STATUS]" tag if present.
                    body = stripped
                    if body.endswith("]") and "[" in body:
                        body = body[:body.rfind("[")].rstrip()
                    try:
                        left, sha = body.rsplit(None, 1)
                        path, crc = left.rstrip().rsplit(None, 1)
                        path = path.strip()
                    except ValueError:
                        continue
                if path:
                    manifests[path] = {"crc": crc, "sha": sha}
    except Exception as e:
        print(f"Pipeline Warning: Error parsing baseline manifest: {e}",
              file=sys.stderr)
    return manifests


def should_scan(rel_path, includes, excludes):
    """Apply --include / --exclude glob filters to a forward-slash rel path."""
    if excludes and any(fnmatch.fnmatch(rel_path, pat) for pat in excludes):
        return False
    if includes and not any(fnmatch.fnmatch(rel_path, pat) for pat in includes):
        return False
    return True


def main(argv=None):
    args = parse_args(argv)
    start_time = time.time()
    last_refresh_time = 0.0

    is_ci_mode = args.ci or bool(
        os.environ.get("JENKINS_URL") or os.environ.get("GITHUB_ACTIONS")
        or os.environ.get("CI"))

    root = args.root
    out_dir = args.out_dir
    output_file, csv_output_file, summary_output_file = compute_output_paths(out_dir)

    # --verify is --baseline with a drift gate.
    baseline_file = args.verify or args.baseline
    verify_mode = bool(args.verify)

    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    default_gateway = detect_gateway()

    if not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    # Remove stale artifacts so a run always overwrites cleanly.
    for stale in (output_file, csv_output_file, summary_output_file):
        if os.path.isfile(stale):
            os.remove(stale)

    hasher_probe = hashlib.new(args.algorithm)
    hash_hex_len = hasher_probe.digest_size * 2
    hash_label = "SHA256 CHECKSUM" if args.algorithm == "sha256" \
        else f"{args.algorithm.upper()} CHECKSUM"

    out_basenames = {os.path.basename(output_file), os.path.basename(csv_output_file),
                     os.path.basename(summary_output_file),
                     os.path.basename(baseline_file) if baseline_file else ""}

    if not is_ci_mode:
        sys.stdout.write("\x1b[?25l")
    print(f"Scanning directory tree... Target Manifest Repository Folder: ./{out_dir}/")

    # ------------------------------------------------------------------ Scan
    root_files = []
    folder_map = {}
    unique_folders = set()
    max_path_len = len("FILE PATH")

    norm_out = out_dir.replace("\\", "/").rstrip("/")
    for dir_root, dirs, files in os.walk(root):
        if ".git" in dirs:
            dirs.remove(".git")

        rel_dir = os.path.relpath(dir_root, root).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = "."
        elif rel_dir == norm_out or rel_dir.startswith(norm_out + "/"):
            dirs[:] = []
            continue
        if rel_dir != "." :
            unique_folders.add(rel_dir)

        for name in files:
            file_path = os.path.join(dir_root, name)
            clean_path = os.path.relpath(file_path, root).replace("\\", "/")

            if name in out_basenames:
                continue
            if ((name.startswith("checksums") and name.endswith((".txt", ".csv")))
                    or (name.startswith("summary") and name.endswith(".txt"))):
                continue
            if not should_scan(clean_path, args.include, args.exclude):
                continue

            if len(clean_path) > max_path_len:
                max_path_len = len(clean_path)
            if rel_dir == ".":
                root_files.append(clean_path)
            else:
                folder_map.setdefault(rel_dir, []).append(clean_path)

    root_files.sort(key=str.lower)
    sorted_folders = sorted(folder_map.keys(), key=str.lower)
    for folder in sorted_folders:
        folder_map[folder].sort(key=str.lower)

    final_file_list = root_files + [p for f in sorted_folders for p in folder_map[f]]
    total_files = len(final_file_list)
    total_folders = len(unique_folders)

    col_width = max_path_len + 4
    total_line_len = col_width + 10 + hash_hex_len + 2
    separator_line = "=" * total_line_len
    standard_80_line = "=" * 80
    header_columns = f'{"FILE PATH":<{col_width}} {"CRC32":<10} {hash_label}\n'

    has_baseline_context = bool(baseline_file and os.path.isfile(baseline_file))
    if has_baseline_context:
        csv_headers = ["FILE PATH", "CRC32", hash_label, "DELTA STATUS"]
    else:
        csv_headers = ["FILE PATH", "CRC32", hash_label]

    # ------------------------------------------------------- Empty tree short-circuit
    if total_files == 0:
        with open(output_file, "w", newline="", encoding="utf-8") as f:
            f.write(separator_line + "\n")
            f.write(header_columns)
            f.write(separator_line + "\n")
            f.write(f'{"  [No target files detected in this directory tree]":<{col_width}}\n')
            f.write(separator_line + "\n")
        with open(csv_output_file, "w", newline="", encoding="utf-8") as cf:
            csv.writer(cf).writerow(csv_headers)
        with open(summary_output_file, "w", newline="", encoding="utf-8") as sf:
            sf.write(standard_80_line + "\n")
            sf.write("Streamed Cross-Platform Checksum Summary\n")
            sf.write(f"Generated:               {timestamp}\n")
            sf.write(f"Gateway:                 {default_gateway}\n")
            sf.write(standard_80_line + "\n")
            sf.write("Execution Summary Manifest\n")
            sf.write("Total Folders Traversed: 0\n")
            sf.write("Total Files Processed:   0\n")
            sf.write(standard_80_line + "\n")
        if not is_ci_mode:
            sys.stdout.write("\x1b[?25h")
        return EXIT_OK

    structured_report = {"root": []}
    for folder in sorted_folders:
        structured_report[folder] = []
    csv_data_rows = []

    baseline_manifests = parse_baseline(baseline_file) if has_baseline_context else {}

    # ------------------------------------------------------------- Core loop
    has_pipeline_failures = False
    processed_paths_set = set()
    metrics = {"added": 0, "modified": 0, "deleted": 0, "unchanged": 0}

    for idx, clean_path in enumerate(final_file_list, 1):
        processed_paths_set.add(clean_path)
        current_time = time.time()

        if not is_ci_mode:
            if (current_time - last_refresh_time >= 0.5) or idx == total_files:
                disp = clean_path if len(clean_path) <= 25 else "..." + clean_path[-22:]
                elapsed = int(current_time - start_time) or 1
                left = int(((elapsed * total_files) / idx) - elapsed)
                left_str = f"{left}s" if left < 60 else f"{left // 60}m {left % 60}s"
                elapsed_str = f"{elapsed}s" if elapsed < 60 else f"{elapsed // 60}m {elapsed % 60}s"
                sys.stdout.write(
                    f"\r\x1b[2KProgress: [{idx}/{total_files}] | Time: {elapsed_str} "
                    f"| Left: {left_str} | Target: {disp}")
                sys.stdout.flush()
                last_refresh_time = current_time
        elif idx % max(1, total_files // 10) == 0 or idx == total_files:
            print(f"Pipeline Progress: Processing files... [{idx}/{total_files}] "
                  f"({int((idx / total_files) * 100)}%)")

        try:
            hasher = hashlib.new(args.algorithm)
            crc = 0
            with open(os.path.join(root, clean_path), "rb") as fh:
                while True:
                    chunk = fh.read(65536)
                    if not chunk:
                        break
                    hasher.update(chunk)
                    crc = zlib.crc32(chunk, crc)
            sha_str = hasher.hexdigest()
            crc_str = f"{crc & 0xffffffff:08x}"

            status_tag = ""
            csv_status = None
            if has_baseline_context:
                if clean_path in baseline_manifests:
                    if baseline_manifests[clean_path]["sha"] == sha_str:
                        status_tag, csv_status = " [UNCHANGED]", "UNCHANGED"
                        metrics["unchanged"] += 1
                    else:
                        status_tag, csv_status = " [MODIFIED]", "MODIFIED"
                        metrics["modified"] += 1
                else:
                    status_tag, csv_status = " [ADDED]", "ADDED"
                    metrics["added"] += 1

            line_item = f"{clean_path:<{col_width}} {crc_str:<10} {sha_str}{status_tag}"

            # Excel-safe wrapping. Guard control-char leads without corrupting the value.
            safe_path = f'="{clean_path}"'
            if clean_path[:1] in ("0", "=", "+", "-"):
                safe_path = f'="\'{clean_path}"'
            row = [safe_path, f'="{crc_str}"', f'="{sha_str}"']
            if has_baseline_context:
                row.append(f'="{csv_status}"')
            csv_data_rows.append(row)

        except Exception as e:
            line_item = f'{clean_path:<{col_width}} {"[FAILED]":<10} [ERROR: FILE ACCESS LOCK]'
            row = [f'="{clean_path}"', '="FAILED"', '="ERROR: FILE ACCESS LOCK"']
            if has_baseline_context:
                row.append('="ACCESS_DENIED"')
            csv_data_rows.append(row)
            has_pipeline_failures = True
            print(f"Pipeline Alert: Could not hash target path -> {clean_path}. "
                  f"Reason: {e}", file=sys.stderr)

        parent_dir = os.path.dirname(clean_path).replace("\\", "/")
        if parent_dir in ("", "."):
            structured_report["root"].append(line_item)
        elif parent_dir in structured_report:
            structured_report[parent_dir].append(line_item)
        else:
            structured_report["root"].append(line_item)

    deleted_items = []
    if has_baseline_context:
        for old_path, meta in baseline_manifests.items():
            if old_path not in processed_paths_set:
                metrics["deleted"] += 1
                deleted_items.append(
                    f'{old_path:<{col_width}} {meta["crc"]:<10} {meta["sha"]} [DELETED]')
                csv_data_rows.append(
                    [f'="{old_path}"', f'="{meta["crc"]}"', f'="{meta["sha"]}"', '="DELETED"'])

    # ------------------------------------------------------------ Write text report
    with open(output_file, "w", newline="", encoding="utf-8") as f:
        if structured_report["root"]:
            f.write("# DIRECTORY: Root Workspace Cluster [.]\n")
            f.write(f'# Context Summary: Contains {len(structured_report["root"])} files direct\n')
            f.write(separator_line + "\n")
            f.write(header_columns)
            f.write(separator_line + "\n")
            f.write("\n".join(structured_report["root"]) + "\n")

        for folder in sorted_folders:
            if structured_report[folder]:
                sub_count = sum(1 for sf in sorted_folders if sf.startswith(folder + "/"))
                f.write(f"\n\n# DIRECTORY: {folder}\n")
                f.write(f"# Context Summary: Contains {len(structured_report[folder])} "
                        f"target files | {sub_count} nested sub-folders\n")
                f.write(separator_line + "\n")
                f.write(header_columns)
                f.write(separator_line + "\n")
                f.write("\n".join(structured_report[folder]) + "\n")

        if deleted_items:
            f.write("\n\n# REMOVED/DELETED FILE MANIFEST ENTRIES\n")
            f.write(f"# Context Summary: Contains {len(deleted_items)} missing "
                    f"elements mapped out of workspace\n")
            f.write(separator_line + "\n")
            f.write(header_columns)
            f.write(separator_line + "\n")
            f.write("\n".join(deleted_items) + "\n")

    # ------------------------------------------------------------- Write CSV
    with open(csv_output_file, "w", newline="", encoding="utf-8") as cf:
        writer = csv.writer(cf)
        writer.writerow(csv_headers)
        writer.writerows(csv_data_rows)

    # ---------------------------------------------------------- Write summary
    elapsed_total = int(time.time() - start_time) or 1
    duration_str = f"{elapsed_total}s" if elapsed_total < 60 \
        else f"{elapsed_total // 60}m {elapsed_total % 60}s"
    with open(summary_output_file, "w", newline="", encoding="utf-8") as sf:
        sf.write(standard_80_line + "\n")
        sf.write("Streamed Cross-Platform Checksum Summary\n")
        sf.write(f"Generated:               {timestamp}\n")
        sf.write(f"Gateway:                 {default_gateway}\n")
        if has_baseline_context:
            sf.write(f"Baseline Mapped Source:  {os.path.basename(baseline_file)}\n")
        sf.write(standard_80_line + "\n")
        sf.write("Execution Summary Manifest\n")
        sf.write(f"Total Execution Time:    {duration_str}\n")
        sf.write(f"Total Folders Traversed: {total_folders}\n")
        sf.write(f"Total Files Processed:   {total_files}\n")
        if has_baseline_context:
            sf.write(f'Delta Metrics Summary:   [Added: {metrics["added"]} | '
                     f'Modified: {metrics["modified"]} | Deleted: {metrics["deleted"]} '
                     f'| Unchanged: {metrics["unchanged"]}]\n')
        sf.write(standard_80_line + "\n")

    if not is_ci_mode:
        elapsed = int(time.time() - start_time) or 1
        elapsed_str = f"{elapsed}s" if elapsed < 60 else f"{elapsed // 60}m {elapsed % 60}s"
        sys.stdout.write(
            f"\r\x1b[2KProgress: [{total_files}/{total_files}] | Total Time: "
            f"{elapsed_str} | Left: 0s | Target: Execution finalized\n")
        sys.stdout.flush()
        sys.stdout.write("\x1b[?25h")

    # ---------------------------------------------------- CI machine-readable metrics
    if is_ci_mode:
        print(f"OUTPUT_METRICS_TARGET_FILE={output_file}")
        print(f"OUTPUT_METRICS_CSV_FILE={csv_output_file}")
        print(f"OUTPUT_METRICS_SUMMARY_FILE={summary_output_file}")
        print(f"OUTPUT_METRICS_HAS_BASELINE={'true' if has_baseline_context else 'false'}")
        print(f"OUTPUT_METRICS_DELTA_ADDED={metrics['added']}")
        print(f"OUTPUT_METRICS_DELTA_MODIFIED={metrics['modified']}")
        print(f"OUTPUT_METRICS_DELTA_DELETED={metrics['deleted']}")
        print(f"OUTPUT_METRICS_HAS_LOCK_ERRORS={'true' if has_pipeline_failures else 'false'}")

    # -------------------------------------------------------------- Exit code
    if has_pipeline_failures:
        return EXIT_LOCK_ERRORS
    if verify_mode and (metrics["added"] or metrics["modified"] or metrics["deleted"]):
        print("Verification failed: manifest drift detected "
              f"(added={metrics['added']} modified={metrics['modified']} "
              f"deleted={metrics['deleted']}).", file=sys.stderr)
        return EXIT_VERIFY_DRIFT
    if args.fail_on_modified and (metrics["modified"] or metrics["deleted"]):
        print("Integrity gate failed: baseline files were modified or deleted "
              f"(modified={metrics['modified']} deleted={metrics['deleted']}).",
              file=sys.stderr)
        return EXIT_FAIL_ON_MODIFIED
    return EXIT_OK


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.stdout.write("\x1b[?25h")
        sys.exit(1)
# * UNCLASSIFIED                 UNCLASSIFIED                 UNCLASSIFIED *
