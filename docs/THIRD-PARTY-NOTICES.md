# Third-Party Notices

This project vendors a small number of third-party assets so it runs fully
offline in air-gapped environments. This file records their origin and license.
Machine-readable provenance (including SHA-256 checksums) lives in
[`sbom.spdx.json`](../sbom.spdx.json).

---

## OS / distribution logos

**Source:** [Simple Icons](https://github.com/simple-icons/simple-icons)
**License:** [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain dedication)
**SBOM package:** `SPDXRef-asset-os-logos`
**Location:** [`server/web/static/img/`](../server/web/static/img/)

The devkit UI displays a logo for the detected platform. The Go server reads
`/etc/os-release` (`ID`, falling back to `ID_LIKE`) at runtime and maps it to one
of the SVGs below; unknown distributions fall back to the generic `linux.png`.

| File | Platform | Simple Icons slug | `/etc/os-release` ID(s) |
|------|----------|-------------------|--------------------------|
| `rhel.svg` | Red Hat Enterprise Linux | `redhat` | `rhel`, `redhat` |
| `rocky.svg` | Rocky Linux | `rockylinux` | `rocky` |
| `almalinux.svg` | AlmaLinux | `almalinux` | `almalinux` |
| `centos.svg` | CentOS | `centos` | `centos` |
| `fedora.svg` | Fedora | `fedora` | `fedora` |
| `ubuntu.svg` | Ubuntu | `ubuntu` | `ubuntu` |
| `debian.svg` | Debian | `debian` | `debian` |
| `mint.svg` | Linux Mint | `linuxmint` | `linuxmint` |
| `opensuse.svg` | openSUSE | `opensuse` | `opensuse-leap`, `opensuse-tumbleweed`, … |
| `suse.svg` | SUSE Linux Enterprise | `suse` | `sles`, `sled`, `suse` |
| `arch.svg` | Arch Linux | `archlinux` | `arch` |
| `alpine.svg` | Alpine Linux | `alpinelinux` | `alpine` |
| `macos.svg` | macOS | `apple` | *(GOOS `darwin`)* |

`windows.png` (Windows) and `linux.png` (generic Tux fallback) predate this set
and are retained as-is.

> **Trademark note:** The CC0-1.0 dedication applies to the Simple Icons SVG
> artwork. The underlying names and marks (Red Hat®, Ubuntu®, etc.) remain
> trademarks of their respective owners and are used here only to identify the
> corresponding platform.

**Updating:** when refreshing or adding a logo, re-run the SHA-256 in
`sbom.spdx.json` for `SPDXRef-asset-os-logos` (the entry lists one checksum per
vendored SVG) and update the mapping in `server/internal/api/handlers.go`
(`distroIcon`) plus the table above.

---

## Other vendored web assets

| Asset | Source | License | SBOM package |
|-------|--------|---------|--------------|
| `server/web/static/tus.min.js` | [tus-js-client](https://github.com/tus/tus-js-client) | MIT | `SPDXRef-dep-tus-js-client` |

Vendored software dependencies (toolchains, libraries, pip wheels) are enumerated
with versions and checksums in [`sbom.spdx.json`](../sbom.spdx.json) and
summarized in [`docs/TOOLS.md`](TOOLS.md).
