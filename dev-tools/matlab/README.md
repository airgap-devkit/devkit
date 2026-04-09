# MATLAB -- Installation Verification

**Author: Nima Shafie**

Verification scripts for MATLAB and required toolboxes.
Does NOT install MATLAB -- it must already be present on the system.

---

## Prerequisites

MATLAB must be installed via the MathWorks installer with a valid license:
- Base MATLAB (any recent release, R2023a or later recommended)
- Database Toolbox (separately licensed)
- MATLAB Compiler (separately licensed)

Both toolboxes require MathWorks licenses. They are NOT freely downloadable --
they must be activated through your organization's MathWorks license agreement.
Contact your MathWorks license administrator if you do not have access.

---

## Verify Installation

```bash
# Check that MATLAB + both toolboxes are present
bash dev-tools/matlab/setup.sh

# Check-only mode (no receipt written)
bash dev-tools/matlab/setup.sh --check-only

# If matlab is not on PATH, specify location:
# Windows:
bash dev-tools/matlab/setup.sh --matlab-path "/c/Program Files/MATLAB/R2025a/bin/matlab.exe"
# Linux:
bash dev-tools/matlab/setup.sh --matlab-path /usr/local/MATLAB/R2025a/bin/matlab
```

---

## What Gets Checked

| Check | Pass Condition |
|-------|---------------|
| MATLAB executable | Found on PATH or at specified path |
| MATLAB version | Any version R2023a or later |
| Database Toolbox | Licensed and installed (`ver('database')` non-empty) |
| MATLAB Compiler | Licensed and installed (`ver('compiler')` non-empty) |

---

## Adding Toolboxes to an Existing MATLAB Install

If MATLAB is present but a toolbox is missing:

1. Open the MathWorks installer (`setup.exe` on Windows, `./install` on Linux)
2. Select **Add Products to an Existing Installation**
3. Sign in with your MathWorks account
4. Select the missing toolbox and complete the installation
5. Re-run `bash dev-tools/matlab/setup.sh` to verify

---

## Platform Support

| Platform | Supported |
|----------|-----------|
| Windows 11 | Yes |
| RHEL 8 / Linux | Yes (MATLAB for Linux is officially supported on RHEL 8) |

---

## Database Toolbox Usage

The Database Toolbox provides SQL query capabilities from MATLAB:

```matlab
% Connect to SQLite
conn = sqlite('mydb.db');
data = fetch(conn, 'SELECT * FROM measurements');
close(conn);

% Connect to PostgreSQL (requires JDBC driver)
conn = database('mydb', 'user', 'pass', ...
    'Vendor', 'PostgreSQL', ...
    'Server', 'localhost', ...
    'PortNumber', 5432);
```

## MATLAB Compiler Usage

The MATLAB Compiler allows packaging MATLAB applications for deployment
on machines without MATLAB:

```matlab
% From MATLAB command window:
mcc -m myapp.m -o myapp_standalone

% Or from the command line:
% Windows:
mcc -m myapp.m -o myapp_standalone.exe
% Linux:
mcc -m myapp.m -o myapp_standalone
```

Standalone applications require the free MATLAB Runtime (MCR) on the
target machine, which can be distributed without a MATLAB license.