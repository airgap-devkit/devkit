#!/usr/bin/env python3
"""Format /tmp/updates.json as a GitHub issue/comment body in Markdown."""
import json
import sys
from datetime import date

data = json.load(open(sys.argv[1]))
today = date.today().isoformat()

lines = [
    f"## Tool Update Report — {today}",
    "",
    "| Tool | Current | Latest | Status |",
    "|------|---------|--------|--------|",
]
for t in sorted(data, key=lambda x: (x["status"] != "update available", x["name"])):
    status = t["status"]
    latest = t.get("latest_version") or "—"
    if status == "manual-check":
        latest = f"[check]({t.get('check_url', '#')})"
    elif status == "no-source":
        latest = "N/A"
    lines.append(
        f"| {t['name']} | `{t['current_version']}` | `{latest}` | {status} |"
    )

lines += [
    "",
    "### How to apply an update",
    "",
    "```bash",
    "bash scripts/internal/apply-tool-update.sh <tool-id> <new-version>",
    "# then:",
    "bash scripts/internal/generate-sbom.sh",
    "bash scripts/internal/release.sh <app-version> --no-build --skip-sign --skip-vt --upload",
    "```",
    "",
    "_Generated automatically by [check-updates.yml](.github/workflows/check-updates.yml)_",
]
print("\n".join(lines))
