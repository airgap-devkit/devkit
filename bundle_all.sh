#!/bin/bash

##############################################################################
# bundle_all.sh
#
# Author: Nima Shafie
# 
# Purpose: Bundle a Git super repository with all its submodules for transfer
#          to air-gapped networks. Creates git bundles with full history and
#          generates verification logs.
#
# Usage: ./bundle_all.sh
#
# Requirements: git, sha256sum
##############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

##############################################################################
# SUPPRESS ALL GIT WARNINGS - Save stderr for our own messages
##############################################################################
exec 3>&2  # Save original stderr to file descriptor 3
exec 2>&1  # Redirect stderr to stdout (will be filtered)

##############################################################################
# PERFORMANCE OPTIMIZATION
##############################################################################
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=echo

##############################################################################
# USER CONFIGURATION - EDIT THESE VARIABLES
##############################################################################

# Local path to the Git super repository you want to bundle
#REPO_PATH="$HOME/Desktop/git-bundles/test/full-test-repo"
REPO_PATH="/path/to/your/super-repository"

# SSH remote Git address (for reference/documentation purposes)
# REMOTE_GIT_ADDRESS="file://$HOME/Desktop/git-bundles/test/full-test-repo"
REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"

##############################################################################
# SCRIPT CONFIGURATION - Generally no need to edit below
##############################################################################

# Store the original working directory (where the script is run from)
SCRIPT_DIR="$(pwd)"

# Generate timestamp for export folder
TIMESTAMP=$(date +%Y%m%d_%H%M)
EXPORT_FOLDER="${SCRIPT_DIR}/${TIMESTAMP}_import"
LOG_FILE="${EXPORT_FOLDER}/bundle_verification.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track script start time
SCRIPT_START_TIME=$(date +%s)

##############################################################################
# FUNCTIONS
##############################################################################

print_header() {
    echo -e "${BLUE}============================================================${NC}" >&3
    echo -e "${BLUE}$1${NC}" >&3
    echo -e "${BLUE}============================================================${NC}" >&3
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}" >&3
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" >&3
}

print_error() {
    echo -e "${RED}✗ $1${NC}" >&3
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}" >&3
}

log_message() {
    echo "$1" | tee -a "$LOG_FILE" >&3
}

# Function to checkout default branch with priority order
checkout_default_branch() {
    local REPO_TYPE=$1  # "super" or "submodule"
    local REPO_NAME=$2  # for logging purposes
    
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    # Priority order: main -> develop -> master -> first available
    if git show-ref --verify --quiet refs/heads/main; then
        if [ "$CURRENT_BRANCH" != "main" ]; then
            git checkout main &>/dev/null
            echo "Checked out 'main' branch for $REPO_TYPE: $REPO_NAME" >> "$LOG_FILE"
        fi
    elif git show-ref --verify --quiet refs/heads/develop; then
        if [ "$CURRENT_BRANCH" != "develop" ]; then
            git checkout develop &>/dev/null
            echo "Checked out 'develop' branch for $REPO_TYPE: $REPO_NAME" >> "$LOG_FILE"
        fi
    elif git show-ref --verify --quiet refs/heads/master; then
        if [ "$CURRENT_BRANCH" != "master" ]; then
            git checkout master &>/dev/null
            echo "Checked out 'master' branch for $REPO_TYPE: $REPO_NAME" >> "$LOG_FILE"
        fi
    else
        # Fallback: checkout first available branch
        FIRST_BRANCH=$(git branch | head -n 1 | sed 's/^[* ]*//')
        if [ -n "$FIRST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$FIRST_BRANCH" ]; then
            git checkout "$FIRST_BRANCH" &>/dev/null
            echo "Checked out fallback branch '$FIRST_BRANCH' for $REPO_TYPE: $REPO_NAME" >> "$LOG_FILE"
        fi
    fi
}

##############################################################################
# VALIDATION
##############################################################################

print_header "Git Bundle Script - Super Repository with Submodules"

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git and try again."
    exit 1
fi

# Check if sha256sum is installed
if ! command -v sha256sum &> /dev/null; then
    print_error "sha256sum is not installed. Please install coreutils and try again."
    exit 1
fi

# Validate repository path
if [ ! -d "$REPO_PATH" ]; then
    print_error "Repository path does not exist: $REPO_PATH"
    print_info "Please edit the REPO_PATH variable in this script."
    exit 1
fi

if [ ! -d "$REPO_PATH/.git" ]; then
    print_error "Path is not a Git repository: $REPO_PATH"
    exit 1
fi

# Create export folder
print_info "Creating export folder: $EXPORT_FOLDER"
mkdir -p "$EXPORT_FOLDER"

# Initialize log file
{
    echo "================================================================="
    echo "Git Bundle Verification Log"
    echo "================================================================="
    echo "Generated: $(date)"
    echo "Ran by: $(whoami)"
    echo "Source Repository: $REPO_PATH"
    echo "Remote Address: $REMOTE_GIT_ADDRESS"
    echo "Export Folder: $EXPORT_FOLDER"
    echo "================================================================="
    echo ""
} > "$LOG_FILE"

##############################################################################
# BUNDLE SUPER REPOSITORY
##############################################################################

print_header "Step 1: Bundling Super Repository"

cd "$REPO_PATH"

# Get the repository name from the path
REPO_NAME=$(basename "$REPO_PATH")
BUNDLE_NAME="${REPO_NAME}.bundle"
BUNDLE_PATH="${EXPORT_FOLDER}/${BUNDLE_NAME}"

print_info "Repository: $REPO_NAME"
print_info "Bundling to: $BUNDLE_PATH"

# CRITICAL: Ensure ALL remote branches become local branches before bundling
# git bundle --all only bundles LOCAL refs (branches, tags)

# OPTIMIZATION: Check existing branches before fetching over network
EXISTING_BRANCHES=$(git branch 2>&1 | wc -l)

if [ "$EXISTING_BRANCHES" -gt 1 ]; then
    # Already have multiple branches - skip fetch for speed
    print_info "Using existing $EXISTING_BRANCHES branches (skipping fetch for speed)"
    echo "Skipped fetch - using existing $EXISTING_BRANCHES branches" >> "$LOG_FILE"
elif git config --get remote.origin.url >/dev/null 2>&1; then
    print_info "Fetching branches from remote..."
    # Fetch with performance flags, filter warnings
    git fetch --all --tags --quiet --no-progress 2>&1 | \
        grep -v "detached HEAD\|Note: switching\|HEAD is now" >> "$LOG_FILE" || true
    
    # Create local branches (batch operation, suppress output)
    git for-each-ref --format='%(refname:short)' refs/remotes/origin/ 2>/dev/null | \
    while read -r rb; do
        [ "$rb" = "origin/HEAD" ] && continue
        git branch -f "${rb#origin/}" "$rb" 2>/dev/null || true
    done
fi

# Verify branches exist
LOCAL_BRANCH_COUNT=$(git branch 2>&1 | wc -l)
if [ "$LOCAL_BRANCH_COUNT" -eq 0 ]; then
    print_error "No branches available"
    exit 1
fi

print_info "Creating bundle with $LOCAL_BRANCH_COUNT branches..."

# Create bundle (quiet, suppress progress)
git -c advice.detachedHead=false bundle create "$BUNDLE_PATH" --all --quiet 2>&1 | \
    grep -v "Enumerating\|Counting\|Delta\|Compressing\|Writing\|Total\|detached HEAD" >> "$LOG_FILE" || true

# Checkout default branch (priority: main -> develop -> master -> first available)
checkout_default_branch "super repository" "$REPO_NAME"

# Verify bundle
print_info "Verifying bundle..."
if git bundle verify "$BUNDLE_PATH" &> /dev/null; then
    print_success "Super repository bundle verified successfully"
    BUNDLE_VERIFIED="✓ VERIFIED"
else
    print_error "Super repository bundle verification FAILED"
    BUNDLE_VERIFIED="✗ FAILED"
fi

# Calculate SHA256
BUNDLE_SHA256=$(sha256sum "$BUNDLE_PATH" | awk '{print $1}')
BUNDLE_SIZE=$(du -h "$BUNDLE_PATH" | awk '{print $1}')

# Get Git statistics
BRANCH_COUNT=$(git branch -a | wc -l)
TAG_COUNT=$(git tag | wc -l)
COMMIT_COUNT=$(git rev-list --all --count)

# Log super repository info
{
    echo "================================================================="
    echo "SUPER REPOSITORY: $REPO_NAME"
    echo "================================================================="
    echo "Bundle File: $BUNDLE_NAME"
    echo "Verification: $BUNDLE_VERIFIED"
    echo "SHA256: $BUNDLE_SHA256"
    echo "File Size: $BUNDLE_SIZE"
    echo "Branches: $BRANCH_COUNT"
    echo "Tags: $TAG_COUNT"
    echo "Total Commits: $COMMIT_COUNT"
    echo "Path in Export: ./$BUNDLE_NAME"
    echo ""
} >> "$LOG_FILE"

##############################################################################
# DISCOVER AND BUNDLE SUBMODULES
##############################################################################

print_header "Step 2: Discovering and Bundling Submodules"

# Check if .gitmodules file exists (indicates submodules are configured)
if [ ! -f ".gitmodules" ]; then
    print_warning "No .gitmodules file found - repository has no submodules"
    SUBMODULE_COUNT=0
    log_message "No submodules found in this repository."
else
    # Enable file:// protocol for local submodules (needed for test repos)
    git config --local protocol.file.allow always
    
    # PERFORMANCE: Check if submodules are already initialized
    UNINIT_SUBMODULES=$(git submodule status 2>&1 | grep "^-" | wc -l || echo 0)
    
    if [ "$UNINIT_SUBMODULES" -gt 0 ]; then
        print_info "Initializing $UNINIT_SUBMODULES submodule(s)..."
        # Use parallel jobs, filter out detached HEAD warnings
        git -c protocol.file.allow=always \
            -c advice.detachedHead=false \
            submodule update --init --recursive --jobs 4 \
            2>&1 | grep -v "detached HEAD\|Note: switching to\|Note: checking out\|HEAD is now at" >> "$LOG_FILE" || true
    else
        print_info "Submodules already initialized (skipping)"
        echo "Submodules already initialized" >> "$LOG_FILE"
    fi
    
    # Disable detached HEAD warnings in all submodules
    git submodule foreach --recursive 'git config advice.detachedHead false' >/dev/null 2>&1 || true
    
    # Get list of ALL submodules recursively (not just root level)
    print_info "Discovering all submodules at all levels..."
    
    # Use git submodule foreach to get accurate list with proper URLs
    SUBMODULE_LIST=$(git submodule foreach --recursive --quiet 'echo "$sm_path|$toplevel/$sm_path"' 2>/dev/null || true)
    
    if [ -z "$SUBMODULE_LIST" ]; then
        SUBMODULE_COUNT=0
        print_warning "No submodules found after initialization"
        log_message "No submodules found."
    else
        SUBMODULE_COUNT=$(echo "$SUBMODULE_LIST" | wc -l)
        print_success "Found $SUBMODULE_COUNT submodule(s) at all levels"
        
        log_message "================================================================="
        log_message "SUBMODULES ($SUBMODULE_COUNT total - including nested)"
        log_message "================================================================="
        
        SUBMODULE_NUM=0
        while IFS='|' read -r SUBMODULE_PATH SUBMODULE_FULL_PATH; do
            SUBMODULE_NUM=$((SUBMODULE_NUM + 1))
            
            print_info "[$SUBMODULE_NUM/$SUBMODULE_COUNT] Bundling: $SUBMODULE_PATH"
            
            # Check if submodule is initialized
            if [ ! -e "$SUBMODULE_FULL_PATH/.git" ]; then
                print_warning "Submodule not initialized: $SUBMODULE_PATH (skipping)"
                log_message ""
                log_message "Submodule #$SUBMODULE_NUM: $SUBMODULE_PATH"
                log_message "Status: ✗ NOT INITIALIZED (skipped)"
                log_message ""
                continue
            fi
            
            # Create directory structure in export folder
            SUBMODULE_DIR=$(dirname "$SUBMODULE_PATH")
            SUBMODULE_NAME=$(basename "$SUBMODULE_PATH")
            
            if [ "$SUBMODULE_DIR" != "." ]; then
                mkdir -p "${EXPORT_FOLDER}/${SUBMODULE_DIR}"
            fi
            
            # Bundle filename and path
            SUBMODULE_BUNDLE_NAME="${SUBMODULE_NAME}.bundle"
            if [ "$SUBMODULE_DIR" != "." ]; then
                SUBMODULE_BUNDLE_PATH="${EXPORT_FOLDER}/${SUBMODULE_DIR}/${SUBMODULE_BUNDLE_NAME}"
            else
                SUBMODULE_BUNDLE_PATH="${EXPORT_FOLDER}/${SUBMODULE_BUNDLE_NAME}"
            fi
            
            # Navigate to submodule
            cd "$SUBMODULE_FULL_PATH"
            
            # PERFORMANCE: Check if we already have local branches before fetching
            EXISTING_BRANCHES=$(git branch | wc -l)
            
            if [ "$EXISTING_BRANCHES" -gt 1 ]; then
                # We already have multiple branches - skip fetch (saves time over VPN!)
                echo "Using existing $EXISTING_BRANCHES branches for $SUBMODULE_PATH (skipping fetch)" >> "$LOG_FILE"
            else
                # Only fetch if we have 0 or 1 branch (need to get all branches)
                SUBMODULE_REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
                
                if [ -n "$SUBMODULE_REMOTE_URL" ]; then
                    # Fetch with maximum performance flags
                    git -c protocol.file.allow=always \
                        -c advice.detachedHead=false \
                        fetch --all --tags --quiet --no-progress 2>/dev/null || true
                    
                    # Create local branches from remote (fast batch operation)
                    git for-each-ref --format='%(refname:short)' refs/remotes/origin/ 2>/dev/null | \
                    while read -r remote_branch; do
                        if [ "$remote_branch" = "origin/HEAD" ]; then
                            continue
                        fi
                        local_branch="${remote_branch#origin/}"
                        # Skip worktree check for performance (rare case)
                        git branch -f "$local_branch" "$remote_branch" 2>/dev/null || true
                    done
                fi
            fi
            
            # Final check: ensure we have at least one branch
            FINAL_BRANCH_COUNT=$(git branch | wc -l)
            if [ "$FINAL_BRANCH_COUNT" -eq 0 ]; then
                # Create from HEAD as last resort
                git branch main HEAD 2>/dev/null || git branch master HEAD 2>/dev/null || true
            fi
            
            # Create bundle (all refs, quiet, filter warnings)
            git -c advice.detachedHead=false bundle create "$SUBMODULE_BUNDLE_PATH" --all --quiet 2>&1 | \
                grep -v "Enumerating\|Counting\|Delta\|Compressing\|Writing\|Total\|detached HEAD\|Note: switching" >> "$LOG_FILE" || true
            
            # Checkout default branch (suppress all output)
            checkout_default_branch "submodule" "$SUBMODULE_PATH" >/dev/null 2>&1 || true
            
            # Get Git statistics
            SUB_BRANCH_COUNT=$(git branch | wc -l)
            SUB_TAG_COUNT=$(git tag | wc -l)
            SUB_COMMIT_COUNT=$(git rev-list --all --count 2>/dev/null || echo 0)
            
            # Verify bundle
            if git bundle verify "$SUBMODULE_BUNDLE_PATH" &> /dev/null; then
                print_success "  Bundled ($SUB_BRANCH_COUNT branches, $SUB_TAG_COUNT tags)"
                SUBMODULE_VERIFIED="✓ VERIFIED"
            else
                print_error "  Verification failed"
                SUBMODULE_VERIFIED="✗ FAILED"
            fi
            
            # Calculate SHA256 and size
            SUBMODULE_SHA256=$(sha256sum "$SUBMODULE_BUNDLE_PATH" | awk '{print $1}')
            SUBMODULE_SIZE=$(du -h "$SUBMODULE_BUNDLE_PATH" | awk '{print $1}')
            
            # Get remote URL
            SUBMODULE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "N/A")
            
            # Log submodule info
            {
                echo ""
                echo "Submodule #$SUBMODULE_NUM: $SUBMODULE_PATH"
                echo "-----------------------------------------------------------------"
                echo "Bundle File: $SUBMODULE_BUNDLE_NAME"
                echo "Verification: $SUBMODULE_VERIFIED"
                echo "SHA256: $SUBMODULE_SHA256"
                echo "File Size: $SUBMODULE_SIZE"
                echo "Branches: $SUB_BRANCH_COUNT"
                echo "Tags: $SUB_TAG_COUNT"
                echo "Total Commits: $SUB_COMMIT_COUNT"
                echo "Remote URL: $SUBMODULE_URL"
                echo "Path in Export: ./$SUBMODULE_DIR/$SUBMODULE_BUNDLE_NAME"
                echo ""
            } >> "$LOG_FILE"
            
            # Return to super repository
            cd "$REPO_PATH"
            
        done < <(echo "$SUBMODULE_LIST")
    fi
fi

##############################################################################
# CREATE METADATA FILE
##############################################################################

print_header "Step 3: Creating Metadata File"

METADATA_FILE="${EXPORT_FOLDER}/metadata.txt"

{
    echo "================================================================="
    echo "Git Bundle Metadata"
    echo "================================================================="
    echo "Export Timestamp: $TIMESTAMP"
    echo "Ran by: $(whoami)"
    echo "Source Path: $REPO_PATH"
    echo "Remote Address: $REMOTE_GIT_ADDRESS"
    echo "Super Repository: $REPO_NAME"
    echo "Submodules Count: $SUBMODULE_COUNT"
    echo "================================================================="
    echo ""
    echo "FOLDER STRUCTURE:"
    echo "-----------------------------------------------------------------"
} > "$METADATA_FILE"

# List all bundles with their relative paths
cd "${EXPORT_FOLDER}"
find . -name "*.bundle" -type f | sort >> "$METADATA_FILE"

{
    echo ""
    echo "================================================================="
    echo "IMPORT INSTRUCTIONS:"
    echo "================================================================="
    echo "1. Transfer this entire folder to the destination network"
    echo "2. Run the export_all.sh script in the same directory as this folder"
    echo "3. The script will recreate the repository structure"
    echo ""
    echo "Note: The corresponding export folder will be named:"
    echo "      ${TIMESTAMP}_export"
    echo "================================================================="
} >> "$METADATA_FILE"

cd "${SCRIPT_DIR}"

print_success "Metadata file created: $METADATA_FILE"

##############################################################################
# FINAL SUMMARY
##############################################################################

print_header "Bundling Complete!"

# Calculate elapsed time
SCRIPT_END_TIME=$(date +%s)
ELAPSED_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
MINUTES=$((ELAPSED_TIME / 60))
SECONDS=$((ELAPSED_TIME % 60))

TOTAL_SIZE=$(du -sh "${EXPORT_FOLDER}" | awk '{print $1}')

echo ""
print_success "Export folder: $(basename ${EXPORT_FOLDER})"
print_success "Total size: $TOTAL_SIZE"
print_success "Super repository: 1 bundle created"
print_success "Submodules: $SUBMODULE_COUNT bundle(s) created"
print_success "Time taken: ${MINUTES}m ${SECONDS}s"
echo ""
print_info "Files created:"
echo "  - bundle_verification.txt (detailed verification log)"
echo "  - metadata.txt (export metadata and instructions)"
echo ""
print_warning "Next Steps:"
echo "  1. Review the verification log: $(basename ${EXPORT_FOLDER})/bundle_verification.txt"
echo "  2. Transfer the entire '$(basename ${EXPORT_FOLDER})' folder to destination network"
echo "  3. Run export_all.sh on the destination network"
echo ""

log_message "================================================================="
log_message "SUMMARY"
log_message "================================================================="
log_message "Total Export Size: $TOTAL_SIZE"
log_message "Super Repository Bundles: 1"
log_message "Submodule Bundles: $SUBMODULE_COUNT"
log_message "Time Taken: ${MINUTES}m ${SECONDS}s"
log_message "Script Completed: $(date +%Y%m%d_%H%M)"
log_message "================================================================="

print_success "All done! ✓"