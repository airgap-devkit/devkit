# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x (rc) | Yes — active development |
| 0.2.x | No — superseded |
| 0.1.x | No — superseded |

Only the latest release branch receives security fixes.

---

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report security issues by emailing:

**nimzshafie@gmail.com**

Include in your report:
- A clear description of the vulnerability and its potential impact
- Steps to reproduce, or a proof-of-concept (no destructive payloads)
- Affected version(s) and platform(s)
- Your name/handle if you would like credit

### What to expect

| Timeline | Action |
|----------|--------|
| Within 3 business days | Acknowledgement of your report |
| Within 14 days | Initial assessment and severity determination |
| Within 60 days | Fix released (or an agreed-upon timeline if longer) |
| After fix ships | Public disclosure coordinated with reporter |

We appreciate responsible disclosure and will credit reporters in the release notes unless you prefer to remain anonymous.

---

## Scope

In scope:
- Authentication bypass in the DevKit Manager token system
- Path traversal or arbitrary file read/write through the install API
- Remote code execution via crafted `devkit.json` or `manifest.json`
- TLS misconfiguration exposing credentials

Out of scope:
- Vulnerabilities requiring physical access to the machine
- Issues in vendored tools themselves (report to upstream projects)
- Denial-of-service with no privilege escalation impact
- Social engineering

---

## Security Design Notes

- The DevKit Manager binds to `127.0.0.1` by default; it is not intended to be exposed to a network without explicit operator configuration.
- Session tokens are generated with `crypto/rand` and stored in `.devkit-token` (mode 0600 on Linux).
- TLS is optional. Pass `--tls` to `launch.sh` to enable HTTPS with an auto-generated self-signed certificate (`devkit-tls.crt` / `devkit-tls.key`). For production deployments, supply your own CA-signed certificates instead.
