# SQLite 3.51.3 -- CLI Tool

**Author: Nima Shafie**

Standalone SQLite CLI binary (`sqlite3` / `sqlite3.exe`) for database inspection
and administration in air-gapped environments.

---

## Note on Python Usage

The `sqlite3` Python module is part of the Python standard library and is
**already available** in the devkit's Python 3.14.4 installation. No install
required for Python applications:

```python
import sqlite3
conn = sqlite3.connect("mydb.db")
```

This module provides only the **standalone CLI binary** for interactive use,
scripting, and database administration outside of Python.

---

## CLI Quick Reference

```bash
# Open or create a database
sqlite3 mydb.db

# Run a single SQL statement and exit
sqlite3 mydb.db "SELECT * FROM users LIMIT 5;"

# Import a CSV
sqlite3 mydb.db ".import data.csv tablename"

# Export to CSV
sqlite3 -csv mydb.db "SELECT * FROM users;" > users.csv

# Show schema
sqlite3 mydb.db ".schema"

# Check version
sqlite3 --version
```

---

## Install

```bash
# Windows or Linux
bash dev-tools/sqlite/setup.sh

# Custom prefix
bash dev-tools/sqlite/setup.sh --prefix /your/path
```

---

## Prebuilt Binaries

Binaries are vendored in `prebuilt-binaries/dev-tools/sqlite/`:

| Platform | File | Size |
|----------|------|------|
| Windows x64 | `sqlite-tools-win-x64-3510300.zip` | ~2MB |
| Linux x64 | `sqlite-tools-linux-x64-3510300.zip` | ~2MB |

SHA256 hashes are in `manifest.json`.

---

## Vendoring

Download from https://sqlite.org/download.html and place in
`prebuilt-binaries/dev-tools/sqlite/`. Update `manifest.json` with SHA256s.