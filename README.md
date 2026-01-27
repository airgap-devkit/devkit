# Git Bundle Scripts for Air-Gapped Networks

This repository contains three bash scripts designed to bundle, export, and sync Git repositories with submodules (including nested submodules at any depth) across air-gapped networks.

## Overview

These scripts solve the problem of transferring a Git "super repository" (a repository containing multiple submodules) across network segments that cannot communicate with each other. The workflow involves:

1. **Bundling** - Creating git bundles of the entire repository structure on the source network
2. **Transfer** - Moving the bundles via physical media (CD/DVD/USB)
3. **Export/Sync** - Recreating or updating the repository structure on the destination network

## Key Features

✅ **Handles nested submodules** - Automatically discovers and bundles submodules at ANY depth  
✅ **Works without pre-initialization** - Detects submodules from `.gitmodules` files  
✅ **Three workflows** - Fresh export, update existing, or create new  
✅ **Windows & Linux compatible** - Tested on Windows Git Bash and Linux  
✅ **Smart branch detection** - Automatically checks out main, master, or default branch  
✅ **Comprehensive verification** - SHA256 checksums and detailed logging  
✅ **Preserves complete history** - All branches, tags, and commits included  
✅ **Air-gap ready** - No network dependencies after bundling  
✅ **Safe syncing** - Automatic backups when updating existing repositories

## Prerequisites

- Git installed on both source and destination systems
- `sha256sum` utility (typically included in coreutils)
- Bash shell (Git Bash on Windows, native bash on Linux/Mac)

## Scripts

### 1. bundle_all.sh

**Purpose**: Bundles a Git super repository with all its submodules for transfer to air-gapped networks.

**What it does**:
- Recursively scans and identifies ALL submodules at any depth
- Creates git bundles with full history (all branches, tags, commits)
- Maintains the exact folder structure of submodules
- Generates verification logs with SHA256 checksums
- Creates metadata files for the export process

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_import/` containing all bundles

### 2. export_all.sh

**Purpose**: Extracts and recreates the Git repository structure from bundles on the destination network to a NEW location.

**What it does**:
- Auto-detects the import folder from `bundle_all.sh`
- Clones the super repository from the bundle
- Recreates all submodules in their original folder structure (including nested ones)
- Checks out the default branch (tries main → master → current)
- Generates documentation for future network connectivity

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_export/` with the complete repository

**Use when**: Setting up a repository for the first time on a new network

### 3. sync_from_bundle.sh

**Purpose**: Updates an EXISTING repository with bundles from a newer source, treating the bundle as the source of truth.

**What it does**:
- Creates a backup of the existing repository (in git-bundles folder)
- Force resets the super repository to match the bundle
- Updates all submodules (including nested ones) to match the bundle
- Overwrites any local changes or commits not in the bundle
- Logs all operations

**Output**: Updates the existing repository in place, creates backup in git-bundles folder

**Use when**: Syncing an outdated repository with newer bundles (bundle overwrites local changes)

## Workflow Comparison

| Scenario | Use This Script |
|----------|----------------|
| First time bringing repo to new network | `export_all.sh` |
| Updating existing repo (bundle is truth) | `sync_from_bundle.sh` |
| Want to preserve local commits | Manual Git merge |
| Testing/Creating a fresh copy | `export_all.sh` |

## Usage Instructions

### Workflow 1: First Time Setup (New Network)

#### Step 1: Configure bundle_all.sh (Source Network)

Edit the `bundle_all.sh` script and configure these variables:

```bash
# Local path to the Git super repository you want to bundle
REPO_PATH="$HOME/Desktop/your-super-repository"

# SSH remote Git address (for reference/documentation purposes)
REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"
```

**Windows Git Bash users**: Always use `$HOME` for portability:
```bash
REPO_PATH="$HOME/Desktop/submodule-docker-dev-workflow"
```

#### Step 2: Run bundle_all.sh (Source Network)

```bash
cd ~/Desktop/git-bundles
chmod +x bundle_all.sh
./bundle_all.sh
```

**Important Notes:**
- ✅ **Submodules do NOT need to be initialized beforehand** - The script will automatically detect submodules from `.gitmodules` files and initialize them only for bundling purposes
- ✅ **Works with or without submodules** - If your repository has no submodules, the script will simply bundle the main repository
- ✅ **Handles nested submodules** - Submodules within submodules at any depth are automatically discovered and bundled
- ✅ **Run from any directory** - The script uses the `REPO_PATH` you configured, so you can run it from anywhere

This will create a folder named like `20260126_2051_import/` containing all bundles.

#### Step 3: Verify the Bundle (Source Network)

```bash
cat 20260126_2051_import/bundle_verification.txt
```

Check that all repositories show `✓ VERIFIED` status.

#### Step 4: Transfer to Destination Network

Transfer the entire `YYYYMMDD_HHmm_import/` folder to the destination network via CD/DVD/USB.

#### Step 5: Run export_all.sh (Destination Network)

```bash
cd ~/Desktop/git-bundles
chmod +x export_all.sh
./export_all.sh
```

The script will auto-detect the import folder (or you can configure `IMPORT_FOLDER` variable).

This creates `20260126_2051_export/your-repo-name/` with the complete repository.

#### Step 6: Verify the Export

```bash
cd 20260126_2051_export/your-repo-name/
git log --oneline -10
git submodule status --recursive
```

### Workflow 2: Updating Existing Repository (Sync)

Use this when you have an **outdated repository** on the destination network and want to update it with newer bundles.

⚠️ **WARNING**: This will OVERWRITE all local changes! A backup is created automatically.

#### Step 1-4: Same as Workflow 1

Bundle on source network and transfer to destination.

#### Step 5: Configure sync_from_bundle.sh (Destination Network)

```bash
# Path to your EXISTING repository that needs updating
EXISTING_REPO_PATH="$HOME/Desktop/my-repository"

# Leave empty to auto-detect most recent import folder
IMPORT_FOLDER=""

# Default branch (tries main, then master, then current)
DEFAULT_BRANCH="main"

# Create backup before syncing (HIGHLY recommended)
CREATE_BACKUP=true
```

#### Step 6: Run sync_from_bundle.sh

```bash
cd ~/Desktop/git-bundles
chmod +x sync_from_bundle.sh
./sync_from_bundle.sh
```

**What happens:**
1. Creates backup: `git-bundles/my-repository_backup_YYYYMMDD_HHMMSS/`
2. Force resets your repository to match the bundle
3. Updates all submodules
4. Discards any local changes

#### Step 7: Verify the Sync

```bash
cd ~/Desktop/my-repository
git log --oneline -10
git submodule status --recursive
```

Your repository now matches the source network exactly!

## Folder Structure Examples

### After bundle_all.sh:
```
git-bundles/
└── 20260126_2051_import/
    ├── super-repo.bundle
    ├── submodule-a.bundle
    ├── folder_b/
    │   └── submodule-b.bundle
    ├── folder_c/
    │   └── folder_d/
    │       └── submodule-c.bundle
    │           └── nested/
    │               └── submodule-d.bundle    ← Nested!
    ├── bundle_verification.txt
    └── metadata.txt
```

### After export_all.sh:
```
git-bundles/
└── 20260126_2051_export/
    └── super-repo/
        ├── .git/
        ├── .gitmodules
        ├── submodule-a/
        ├── folder_b/
        │   └── submodule-b/
        └── folder_c/
            └── folder_d/
                └── submodule-c/
                    └── nested/
                        └── submodule-d/
```

### After sync_from_bundle.sh:
```
git-bundles/
├── 20260126_2051_import/              ← Input bundles
├── my-repository_backup_20260126_143052/  ← Backup created
├── bundle_all.sh
├── export_all.sh
└── sync_from_bundle.sh
```

(Plus your existing repository is updated in place at its original location)

## Nested Submodules

These scripts fully support **nested submodules** (submodules within submodules) at any depth:

- The `bundle_all.sh` script recursively discovers ALL `.git` files/directories
- The `export_all.sh` and `sync_from_bundle.sh` scripts process bundles in the correct order (parent before child)
- No manual configuration needed - it just works!

**Example structure:**
```
parent-repo/
└── level1/
    └── submodule-a/           ← First level submodule
        └── nested/
            └── submodule-b/   ← Nested submodule (2nd level)
                └── deep/
                    └── submodule-c/   ← Even deeper! (3rd level)
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
- Logs branch, tag, and commit counts for all repositories

### export_all.sh Verification
The script:
- Validates bundle integrity before cloning
- Ensures folder structure matches the original
- Processes bundles in correct order (parent directories before nested)
- Logs all operations for audit purposes

### sync_from_bundle.sh Safety
The script:
- Creates automatic backup before any changes (in git-bundles folder)
- Force resets to bundle state (bundle is source of truth)
- Logs all operations
- Provides clear warnings about data loss

## Troubleshooting

### Bundle verification fails
- Ensure the source repository is accessible at the configured `REPO_PATH`
- The script will automatically initialize submodules - no manual action needed
- Check that all submodules are accessible (network or file:// paths)

### Submodule not found during export/sync
- Verify the bundle exists in the correct folder in the import directory
- Check `bundle_verification.txt` for any bundles that failed verification
- Ensure the entire import folder was transferred (including subdirectories)

### Branch not found
- The scripts automatically try `main`, then `master`, then the current branch
- No manual configuration needed unless you want a specific branch
- Check the export/sync log to see which branch was checked out

### Permission denied
- Ensure scripts are executable: `chmod +x *.sh`
- Check file permissions on the import/export folders
- On Windows, run Git Bash with appropriate permissions

### Recovering from failed sync
- Backups are stored in `git-bundles/repository-name_backup_YYYYMMDD_HHMMSS/`
- Simply copy the backup back to restore: `cp -r backup/ ~/Desktop/my-repo/`

### Windows-Specific Issues

**Path format**: Always use `$HOME` or forward slashes:
- ✅ Good: `$HOME/Desktop/my-repo`
- ✅ Good: `/c/Users/username/Desktop/my-repo`
- ❌ Bad: `C:\Users\username\Desktop\my-repo`

**Line endings**: Scripts use Unix line endings (LF) - Git Bash handles this automatically

## Advanced Usage

### Testing with Nested Submodules

Use the included `create_nested_test_repo.sh` script to create a test repository with nested submodules:

```bash
cd ~/Desktop
./create_nested_test_repo.sh
```

Use `create_test_scenario.sh` for a complete test setup with old and new repositories to test all three scripts.

### Custom timestamp folders
The scripts use `YYYYMMDD_HHmm` format. Multiple exports on the same day will have different timestamps (down to the minute).

### Import folder auto-detection
When `IMPORT_FOLDER=""` is left empty, scripts find the most recent `*_import` folder by sorting folder names (which are chronologically ordered due to the timestamp format).

## Security Notes

- Always verify SHA256 checksums match between source and destination
- Review `bundle_verification.txt` before transferring
- Keep audit logs of all transfers between networks
- Follow your organization's air-gap transfer procedures
- For local test repositories, the scripts enable `file://` protocol automatically
- When using `sync_from_bundle.sh`, ensure bundles are from a trusted source

## Platform Support

- ✅ **Linux** - Native bash support
- ✅ **macOS** - Native bash support  
- ✅ **Windows** - Git Bash (MINGW64)
- ✅ **WSL** - Windows Subsystem for Linux

## Support

For issues or questions:
1. Check the verification logs (`bundle_verification.txt`, `export_log.txt`)
2. Review `NETWORK_CONNECTIVITY_NOTES.txt` for remote setup
3. Review `SYNC_WORKFLOW.md` for detailed sync instructions
4. Ensure Git version compatibility between networks (Git 2.x recommended)

## Additional Documentation

- `SYNC_WORKFLOW.md` - Detailed guide for syncing/updating existing repositories
- `WINDOWS_QUICK_START.md` - Windows-specific setup guide
- `BETTER_TEST_REPOS.md` - Recommended repositories for testing
- `create_test_scenario.sh` - Complete test setup script

## Quick Reference

```bash
# Bundle a repository (source network)
cd ~/Desktop/git-bundles
./bundle_all.sh

# Export to new location (destination network - first time)
./export_all.sh

# Sync existing repository (destination network - updates)
./sync_from_bundle.sh
```

## License

These scripts are provided as-is for use in managing Git repositories across air-gapped networks.

---

**Last Updated**: January 26, 2026  
**Tested With**: Git 2.x on Windows Git Bash, Linux, and macOS

## Overview

These scripts solve the problem of transferring a Git "super repository" (a repository containing multiple submodules) across network segments that cannot communicate with each other. The workflow involves:

1. **Bundling** - Creating git bundles of the entire repository structure on the source network
2. **Transfer** - Moving the bundles via physical media (CD/DVD/USB)
3. **Export** - Recreating the repository structure on the destination network

## Key Features

✅ **Handles nested submodules** - Automatically discovers and bundles submodules at ANY depth  
✅ **Works without pre-initialization** - Detects submodules from `.gitmodules` files  
✅ **Windows & Linux compatible** - Tested on Windows Git Bash and Linux  
✅ **Smart branch detection** - Automatically checks out main, master, or default branch  
✅ **Comprehensive verification** - SHA256 checksums and detailed logging  
✅ **Preserves complete history** - All branches, tags, and commits included  
✅ **Air-gap ready** - No network dependencies after bundling

## Prerequisites

- Git installed on both source and destination systems
- `sha256sum` utility (typically included in coreutils)
- Bash shell (Git Bash on Windows, native bash on Linux/Mac)

## Scripts

### 1. bundle_all.sh

**Purpose**: Bundles a Git super repository with all its submodules for transfer to air-gapped networks.

**What it does**:
- Recursively scans and identifies ALL submodules at any depth
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
- Recreates all submodules in their original folder structure (including nested ones)
- Checks out the default branch (tries main → master → current)
- Generates documentation for future network connectivity

**Output**: Creates a timestamped folder `YYYYMMDD_HHmm_export/` with the complete repository

## Usage Instructions

### Step 1: Configure bundle_all.sh (Source Network)

Edit the `bundle_all.sh` script and configure these variables:

```bash
# Local path to the Git super repository you want to bundle
REPO_PATH="$HOME/Desktop/your-super-repository"

# SSH remote Git address (for reference/documentation purposes)
REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"
```

**Windows Git Bash users**: Always use `$HOME` for portability:
```bash
REPO_PATH="$HOME/Desktop/submodule-docker-dev-workflow"
```

### Step 2: Run bundle_all.sh (Source Network)

```bash
chmod +x bundle_all.sh
./bundle_all.sh
```

**Important Notes:**
- ✅ **Submodules do NOT need to be initialized beforehand** - The script will automatically detect submodules from `.gitmodules` files and initialize them only for bundling purposes
- ✅ **Works with or without submodules** - If your repository has no submodules, the script will simply bundle the main repository
- ✅ **Handles nested submodules** - Submodules within submodules at any depth are automatically discovered and bundled
- ✅ **Run from any directory** - The script uses the `REPO_PATH` you configured, so you can run it from anywhere

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
- Other approved physical media

### Step 5: Configure export_all.sh (Destination Network)

Edit the `export_all.sh` script if needed:

```bash
# Path to the import folder (leave empty for auto-detection)
IMPORT_FOLDER=""

# Default branch to checkout (automatically tries main, then master, then current)
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
- All submodules initialized and checked out (including nested ones)
- `export_log.txt` - Detailed export log
- `NETWORK_CONNECTIVITY_NOTES.txt` - Guide for future remote setup

### Step 7: Verify the Export (Destination Network)

Navigate to the exported repository and verify:

```bash
cd 20260126_2051_export/your-repo-name/
git log --oneline -10
git submodule status --recursive
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
│           └── nested/
│               └── submodule-d.bundle    ← Nested submodule!
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
│               ├── .git/
│               └── nested/
│                   └── submodule-d/      ← Nested submodule!
│                       └── .git/
├── export_log.txt
└── NETWORK_CONNECTIVITY_NOTES.txt
```

## Nested Submodules

These scripts fully support **nested submodules** (submodules within submodules) at any depth:

- The `bundle_all.sh` script recursively discovers ALL `.git` files/directories
- The `export_all.sh` script processes bundles in the correct order (parent before child)
- No manual configuration needed - it just works!

**Example structure:**
```
parent-repo/
└── level1/
    └── submodule-a/           ← First level submodule
        └── nested/
            └── submodule-b/   ← Nested submodule (2nd level)
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
- Logs branch, tag, and commit counts for all repositories

### export_all.sh Verification
The script:
- Validates bundle integrity before cloning
- Ensures folder structure matches the original
- Processes bundles in correct order (parent directories before nested)
- Logs all operations for audit purposes

## Troubleshooting

### Bundle verification fails
- Ensure the source repository is accessible at the configured `REPO_PATH`
- The script will automatically initialize submodules - no manual action needed
- Check that all submodules are accessible (network or file:// paths)

### Submodule not found during export
- Verify the bundle exists in the correct folder in the import directory
- Check `bundle_verification.txt` for any bundles that failed verification
- Ensure the entire import folder was transferred (including subdirectories)

### Branch not found
- The script automatically tries `main`, then `master`, then the current branch
- No manual configuration needed unless you want a specific branch
- Check the export log to see which branch was checked out

### Permission denied
- Ensure scripts are executable: `chmod +x *.sh`
- Check file permissions on the import/export folders
- On Windows, run Git Bash with appropriate permissions

### Windows-Specific Issues

**Path format**: Always use `$HOME` or forward slashes:
- ✅ Good: `$HOME/Desktop/my-repo`
- ✅ Good: `/c/Users/username/Desktop/my-repo`
- ❌ Bad: `C:\Users\username\Desktop\my-repo`

**Line endings**: Scripts use Unix line endings (LF) - Git Bash handles this automatically

## Advanced Usage

### Testing with Nested Submodules

Use the included `create_nested_test_repo.sh` script to create a test repository with nested submodules:

```bash
cd ~/Desktop
./create_nested_test_repo.sh
```

This creates a `test-parent` repository with nested submodules for testing.

### Custom timestamp folders
The scripts use `YYYYMMDD_HHmm` format. Multiple exports on the same day will have different timestamps (down to the minute).

### Network transition
When transitioning from air-gapped to networked:
1. Update `.gitmodules` with correct URLs
2. Run `git submodule sync --recursive`
3. Add remote origins: `git remote add origin <URL>`
4. Configure submodule remotes: `git submodule foreach --recursive 'git remote add origin <URL>'`

## Security Notes

- Always verify SHA256 checksums match between source and destination
- Review `bundle_verification.txt` before transferring
- Keep audit logs of all transfers between networks
- Follow your organization's air-gap transfer procedures
- For local test repositories, the scripts enable `file://` protocol automatically

## Platform Support

- ✅ **Linux** - Native bash support
- ✅ **Windows** - Git Bash (MINGW64)
- ✅ **WSL** - Windows Subsystem for Linux

## Support

For issues or questions:
1. Check the verification logs (`bundle_verification.txt`, `export_log.txt`)
2. Review `NETWORK_CONNECTIVITY_NOTES.txt` for remote setup
3. Ensure Git version compatibility between networks (Git 2.x recommended)

## License

These scripts are provided as-is for use in managing Git repositories across air-gapped networks.

---

**Last Updated**: January 26, 2026
**Tested With**: Git 2.x on Windows Git Bash, and Linux