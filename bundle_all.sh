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
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

log_message() {
    echo "$1" | tee -a "$LOG_FILE"
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
# If repo only has some branches local but others only as remotes/origin/*, those won't be included!

# If we have a remote, always fetch and create local branches from ALL remote refs
if git config --get remote.origin.url &> /dev/null; then
    print_info "Fetching all branches from remote..."
    # Use 'git fetch --all' (not 'git fetch origin --all')
    git fetch --all --tags >> "$LOG_FILE" 2>&1 || true
    
    # Create local branches from ALL remote branches
    # Check for worktrees to avoid conflicts
    for remote in $(git branch -r | grep 'origin/' | grep -v 'HEAD' | sed 's|^[[:space:]]*origin/||' | sed 's|^[[:space:]]*||'); do
        # Check if branch exists and is used by a worktree
        if git rev-parse --verify "$remote" &>/dev/null; then
            # Branch exists locally - check if it's in a worktree
            if git worktree list | grep -q "$remote"; then
                # Skip branches used by worktrees
                echo "Skipping branch '$remote' (used by worktree)" >> "$LOG_FILE"
                continue
            fi
        fi
        # Create or update local branch to match remote
        git branch -f "$remote" "origin/$remote" >> "$LOG_FILE" 2>&1 || true
    done
fi

# Verify we have local branches
LOCAL_BRANCH_COUNT=$(git branch | wc -l)
if [ "$LOCAL_BRANCH_COUNT" -eq 0 ]; then
    print_error "Repository has no local branches and no remote to fetch from"
    exit 1
fi

print_info "Creating bundle with $LOCAL_BRANCH_COUNT branches..."

# Create bundle with all references
git bundle create "$BUNDLE_PATH" --all >> "$LOG_FILE" 2>&1

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
    
    # Initialize submodules only for bundling purposes
    print_info "Initializing submodules recursively..."
    git -c protocol.file.allow=always submodule update --init --recursive >> "$LOG_FILE" 2>&1
    
    # Get list of ALL submodules recursively (not just root level)
    # This finds submodules at any depth in the tree
    print_info "Discovering all submodules at all levels..."
    
    # Find all .git files/directories under the repository (submodules)
    # Exclude the root .git directory
    SUBMODULE_PATHS=$(find . -name ".git" -type f -o \( -name ".git" -type d -not -path "./.git" \) | sed 's|/\.git$||' | sed 's|^\./||' | sort)
    
    if [ -z "$SUBMODULE_PATHS" ]; then
        SUBMODULE_COUNT=0
        print_warning "No submodules found after initialization"
        log_message "No submodules found."
    else
        SUBMODULE_COUNT=$(echo "$SUBMODULE_PATHS" | wc -l)
        print_success "Found $SUBMODULE_COUNT submodule(s) at all levels"
        
        log_message "================================================================="
        log_message "SUBMODULES ($SUBMODULE_COUNT total - including nested)"
        log_message "================================================================="
        
        SUBMODULE_NUM=0
        while IFS= read -r SUBMODULE_PATH; do
            SUBMODULE_NUM=$((SUBMODULE_NUM + 1))
            
            print_info "[$SUBMODULE_NUM/$SUBMODULE_COUNT] Bundling: $SUBMODULE_PATH"
            
            # Get absolute path to submodule
            SUBMODULE_FULL_PATH="$REPO_PATH/$SUBMODULE_PATH"
            
            # Check if submodule is initialized (.git can be a directory or a file)
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
            
            # Navigate to submodule and create bundle
            cd "$SUBMODULE_FULL_PATH"
            
            # CRITICAL: Fetch all branches and tags from remote before bundling
            # Submodules often only have remote-tracking branches (remotes/origin/*) 
            # and NO local branches. git bundle --all only bundles LOCAL refs.
            # We must convert all remote-tracking branches to local branches first.
            if git config --get remote.origin.url &> /dev/null; then
                # Redirect verbose fetch output to log (use --all without remote name)
                git -c protocol.file.allow=always fetch --all --tags >> "$LOG_FILE" 2>&1 || true
                
                # Create local branches for EVERY remote branch (suppress output)
                for remote in $(git branch -r | grep 'origin/' | grep -v 'HEAD' | sed 's|^[[:space:]]*origin/||' | sed 's|^[[:space:]]*||'); do
                    # Check for worktree conflicts
                    if git rev-parse --verify "$remote" &>/dev/null; then
                        if git worktree list 2>/dev/null | grep -q "$remote"; then
                            echo "Skipping branch '$remote' in $(pwd) (used by worktree)" >> "$LOG_FILE"
                            continue
                        fi
                    fi
                    git branch -f "$remote" "origin/$remote" >> "$LOG_FILE" 2>&1 || true
                done
            fi
            
            # Verify we have local branches before bundling
            LOCAL_BRANCH_COUNT=$(git branch | wc -l)
            if [ "$LOCAL_BRANCH_COUNT" -eq 0 ]; then
                # Last resort: create local branch from HEAD
                CURRENT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "")
                if [ -n "$CURRENT_COMMIT" ]; then
                    git branch main HEAD >> "$LOG_FILE" 2>&1 || git branch master HEAD >> "$LOG_FILE" 2>&1 || true
                fi
            fi
            
            # Create bundle (suppress verbose output)
            git bundle create "$SUBMODULE_BUNDLE_PATH" --all >> "$LOG_FILE" 2>&1
            
            # Checkout default branch (priority: main -> develop -> master -> first available)
            checkout_default_branch "submodule" "$SUBMODULE_PATH"
            
            # Get Git statistics
            SUB_BRANCH_COUNT=$(git branch | wc -l)
            SUB_TAG_COUNT=$(git tag | wc -l)
            SUB_COMMIT_COUNT=$(git rev-list --all --count)
            
            # Verify bundle
            if git bundle verify "$SUBMODULE_BUNDLE_PATH" &> /dev/null; then
                print_success "  ✓ Bundled ($SUB_BRANCH_COUNT branches, $SUB_TAG_COUNT tags)"
                SUBMODULE_VERIFIED="✓ VERIFIED"
            else
                print_error "  ✗ Verification failed"
                SUBMODULE_VERIFIED="✗ FAILED"
            fi
            
            # Calculate SHA256
            SUBMODULE_SHA256=$(sha256sum "$SUBMODULE_BUNDLE_PATH" | awk '{print $1}')
            SUBMODULE_SIZE=$(du -h "$SUBMODULE_BUNDLE_PATH" | awk '{print $1}')
            
            # Get remote URL if available
            SUBMODULE_URL=$(git config --get remote.origin.url || echo "N/A")
            
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
            
        done < <(echo "$SUBMODULE_PATHS")
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
log_message "Script Completed: $(date)"
log_message "================================================================="

print_success "All done! ✓"