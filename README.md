# Git Bundle Scripts for Air-Gapped Networks

This repository contains two bash scripts designed to bundle and export Git repositories with submodules across air-gapped networks.

## Overview

These scripts solve the problem of transferring a Git "super repository" (a repository containing multiple submodules) across network segments that cannot communicate with each other. The workflow involves:

1. **Bundling** - Creating git bundles of the entire repository structure on the source network
2. **Transfer** - Moving the bundles via physical media (CD/DVD/USB)
3. **Export** - Recreating the repository structure on the destination network

## Prerequisites

- Git installed on both source and destination systems
- `sha256sum` utility (typically included in coreutils)
- Bash shell

## Scripts

### 1. bundle_all.sh

**Purpose**: Bundles a Git super repository with all its submodules for transfer to air-gapped networks.

**What it does**:
- Scans and identifies all submodules in your repository
- Creates git bundles with full history (all branches, tags, commits)
- Maintains the exact folder structure of submodules
- Generates verification logs with SHA256 checksums
- Creates metadata files for the export process

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_import/` containing all bundles

### 2. export_all.sh

**Purpose**: Extracts and recreates the Git repository structure from bundles on the destination network.

**What it does**:
- Auto-detects the import folder from `bundle_all.sh`
- Clones the super repository from the bundle
- Recreates all submodules in their original folder structure
- Checks out the default branch (`main` by default)
- Generates documentation for future network connectivity

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_export/` with the complete repository

## Usage Instructions

### Step 1: Configure bundle_all.sh (Source Network)

Edit the `bundle_all.sh` script and configure these variables:

```bash
# Local path to the Git super repository you want to bundle
REPO_PATH="/path/to/your/super-repository"

# SSH remote Git address (for reference/documentation purposes)
REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"
```

### Step 2: Run bundle_all.sh (Source Network)

```bash
chmod +x bundle_all.sh
./bundle_all.sh
```

This will create a folder named like `20260126_2051_import/` containing:
- All git bundles (maintaining folder structure)
- `bundle_verification.txt` - Detailed verification log with SHA256 checksums
- `metadata.txt` - Export metadata and instructions

### Step 3: Verify the Bundle (Source Network)

Review the verification log to ensure all bundles were created successfully:

```bash
cat 20260126_2051_import/bundle_verification.txt
```

Check that all repositories show `✓ VERIFIED` status.

### Step 4: Transfer to Destination Network

Transfer the entire `YYYYMMDD_HHmm_import/` folder to the destination network via:
- CD/DVD burning
- USB drive
- Other approved physical media

### Step 5: Configure export_all.sh (Destination Network)

Edit the `export_all.sh` script if needed:

```bash
# Path to the import folder (leave empty for auto-detection)
IMPORT_FOLDER=""

# Default branch to checkout
DEFAULT_BRANCH="main"
```

**Note**: Auto-detection will find the most recent `*_import` folder automatically.

### Step 6: Run export_all.sh (Destination Network)

```bash
chmod +x export_all.sh
./export_all.sh
```

This will create a folder named like `20260126_2051_export/` containing:
- The complete repository structure
- All submodules initialized and checked out
- `export_log.txt` - Detailed export log
- `NETWORK_CONNECTIVITY_NOTES.txt` - Guide for future remote setup

### Step 7: Verify the Export (Destination Network)

Navigate to the exported repository and verify:

```bash
cd 20260126_2051_export/your-repo-name/
git log --oneline -10
git submodule status
```

## Folder Structure Example

### After bundle_all.sh:
```
20260126_2051_import/
├── super-repo.bundle
├── submodule-a.bundle
├── folder_b/
│   └── submodule-b.bundle
├── folder_c/
│   └── folder_d/
│       └── submodule-c.bundle
├── bundle_verification.txt
└── metadata.txt
```

### After export_all.sh:
```
20260126_2051_export/
├── super-repo/
│   ├── .git/
│   ├── .gitmodules
│   ├── submodule-a/
│   │   └── .git/
│   ├── folder_b/
│   │   └── submodule-b/
│   │       └── .git/
│   └── folder_c/
│       └── folder_d/
│           └── submodule-c/
│               └── .git/
├── export_log.txt
└── NETWORK_CONNECTIVITY_NOTES.txt
```

## Air-Gapped Network Considerations

### Current Setup
- Repositories are cloned WITHOUT remote URLs configured
- This is intentional for security in air-gapped environments
- All git history, branches, and tags are preserved

### Future Network Connectivity
If networks eventually become connected, see `NETWORK_CONNECTIVITY_NOTES.txt` for instructions on:
- Adding remote URLs
- Configuring submodule remotes
- Pushing changes back to the source
- Syncing with remote repositories

## Verification and Safety

### bundle_all.sh Verification
The script automatically:
- Verifies each bundle using `git bundle verify`
- Calculates SHA256 checksums for integrity checking
- Records file sizes for each bundle
- Logs branch, tag, and commit counts

### export_all.sh Verification
The script:
- Validates bundle integrity before cloning
- Ensures folder structure matches the original
- Initializes all submodules correctly
- Logs all operations for audit purposes

## Troubleshooting

### Bundle verification fails
- Ensure the source repository is fully initialized
- Run `git submodule update --init --recursive` in the source repository
- Check that all submodules are accessible

### Submodule not found during export
- Verify the bundle exists in the correct folder in the import directory
- Check that the folder structure matches between import and the original repository
- Review `bundle_verification.txt` for any missing bundles

### Branch not found
- Edit `DEFAULT_BRANCH` in `export_all.sh` to match your repository's main branch
- Common alternatives: `master`, `develop`

### Permission denied
- Ensure scripts are executable: `chmod +x *.sh`
- Check file permissions on the import/export folders

## Advanced Usage

### Custom timestamp folders
The scripts use `YYYYMMDD_HHmm` format. If you need to work with multiple exports on the same day, the timestamp will differentiate them.

### Selective bundling
To bundle only specific submodules, you can modify `bundle_all.sh` to skip certain paths. Add exclusion logic in the submodule processing section.

### Network transition
When transitioning from air-gapped to networked:
1. Update `.gitmodules` with correct URLs
2. Run `git submodule sync`
3. Add remote origins: `git remote add origin <URL>`
4. Configure submodule remotes as documented

## Security Notes

- Always verify SHA256 checksums match between source and destination
- Review `bundle_verification.txt` before transferring
- Keep audit logs of all transfers between networks
- Follow your organization's air-gap transfer procedures

## Support

For issues or questions:
1. Check the verification logs (`bundle_verification.txt`, `export_log.txt`)
2. Review `NETWORK_CONNECTIVITY_NOTES.txt` for remote setup
3. Ensure Git version compatibility between networks

## License

These scripts are provided as-is for use in managing Git repositories across air-gapped networks.

---

**Last Updated**: January 26, 2026
