#!/bin/bash

##############################################################################
# export_all.sh
#
# Author: Nima Shafie
# 
# Purpose: Extract and recreate a Git super repository with all its submodules
#          from git bundles on an air-gapped network. Maintains the original
#          folder structure and initializes all submodules.
#
# Usage: ./export_all.sh
#
# Requirements: git
##############################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

##############################################################################
# USER CONFIGURATION - EDIT THESE VARIABLES
##############################################################################

# Path to the import folder (the folder created by bundle_all.sh)
# This should be the YYYYMMDD_HHmm_import folder
# Leave empty to auto-detect (finds the most recent *_import folder by timestamp in name)
# Example: "20260126_2140_import" or leave "" for auto-detect
IMPORT_FOLDER=""

# Default branch to checkout (typically 'main' or 'master')
DEFAULT_BRANCH="main"

##############################################################################
# SCRIPT CONFIGURATION - Generally no need to edit below
##############################################################################

# Store the original working directory (where the script is run from)
SCRIPT_DIR="$(pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}ℹ $1${NC}"
}

##############################################################################
# VALIDATION
##############################################################################

print_header "Git Export Script - Recreate Repository from Bundles"

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install git and try again."
    exit 1
fi

# Auto-detect import folder if not specified
if [ -z "$IMPORT_FOLDER" ]; then
    print_info "Auto-detecting import folder..."
    
    # Find the most recent *_import folder
    IMPORT_FOLDER=$(find . -maxdepth 1 -type d -name "*_import" | sort -r | head -n 1)
    
    if [ -z "$IMPORT_FOLDER" ]; then
        print_error "No *_import folder found in current directory."
        print_info "Please either:"
        echo "  1. Place this script in the same directory as the import folder, or"
        echo "  2. Edit the IMPORT_FOLDER variable in this script"
        exit 1
    fi
    
    # Remove leading ./
    IMPORT_FOLDER="${IMPORT_FOLDER#./}"
    print_success "Found import folder: $IMPORT_FOLDER"
else
    # Validate specified import folder
    if [ ! -d "$IMPORT_FOLDER" ]; then
        print_error "Import folder does not exist: $IMPORT_FOLDER"
        print_info "Please edit the IMPORT_FOLDER variable in this script."
        exit 1
    fi
fi

# Extract timestamp from import folder name
TIMESTAMP=$(basename "$IMPORT_FOLDER" | sed 's/_import$//')
EXPORT_FOLDER="${SCRIPT_DIR}/${TIMESTAMP}_export"

# Make IMPORT_FOLDER absolute if it's relative
if [[ "$IMPORT_FOLDER" != /* ]]; then
    IMPORT_FOLDER="${SCRIPT_DIR}/${IMPORT_FOLDER}"
fi

print_info "Export folder will be: $(basename $EXPORT_FOLDER)"

# Check if export folder already exists
if [ -d "$EXPORT_FOLDER" ]; then
    print_warning "Export folder already exists: $EXPORT_FOLDER"
    read -p "Do you want to remove it and continue? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        print_info "Export cancelled."
        exit 0
    fi
    print_info "Removing existing export folder..."
    rm -rf "$EXPORT_FOLDER"
fi

# Create export folder
mkdir -p "$EXPORT_FOLDER"

# Create log file
LOG_FILE="${EXPORT_FOLDER}/export_log.txt"
{
    echo "================================================================="
    echo "Git Export Log"
    echo "================================================================="
    echo "Generated: $(date)"
    echo "Import Folder: $IMPORT_FOLDER"
    echo "Export Folder: $EXPORT_FOLDER"
    echo "Default Branch: $DEFAULT_BRANCH"
    echo "================================================================="
    echo ""
} > "$LOG_FILE"

log_message() {
    echo "$1" | tee -a "$LOG_FILE"
}

##############################################################################
# FIND SUPER REPOSITORY BUNDLE
##############################################################################

print_header "Step 1: Locating Super Repository Bundle"

# The super repository bundle should be in the root of the import folder
# We need to identify which one is the super repo by checking metadata
# or by finding the largest bundle (super repos are usually larger)
# Better approach: check which bundles are NOT in the .gitmodules reference

cd "$IMPORT_FOLDER"

# Get all bundles in the root directory
ROOT_BUNDLES=$(find . -maxdepth 1 -name "*.bundle" -type f)

if [ -z "$ROOT_BUNDLES" ]; then
    print_error "No bundles found in $IMPORT_FOLDER"
    exit 1
fi

# If there's only one bundle in root, that's the super repository
BUNDLE_COUNT=$(echo "$ROOT_BUNDLES" | wc -l)

if [ "$BUNDLE_COUNT" -eq 1 ]; then
    SUPER_BUNDLE="$ROOT_BUNDLES"
else
    # Multiple bundles in root - we need to identify the super repo
    # Check metadata.txt if available
    if [ -f "metadata.txt" ]; then
        SUPER_REPO_NAME=$(grep "Super Repository:" metadata.txt | awk '{print $3}')
        if [ -n "$SUPER_REPO_NAME" ]; then
            SUPER_BUNDLE="./${SUPER_REPO_NAME}.bundle"
            if [ ! -f "$SUPER_BUNDLE" ]; then
                print_warning "Super repository name from metadata not found: $SUPER_BUNDLE"
                # Fall back to largest bundle
                SUPER_BUNDLE=$(ls -S *.bundle 2>/dev/null | head -n 1)
                SUPER_BUNDLE="./$SUPER_BUNDLE"
            fi
        else
            # No metadata, use largest bundle as super repository
            print_warning "Could not determine super repository from metadata, using largest bundle"
            SUPER_BUNDLE=$(ls -S *.bundle 2>/dev/null | head -n 1)
            SUPER_BUNDLE="./$SUPER_BUNDLE"
        fi
    else
        # No metadata.txt, use largest bundle
        print_warning "No metadata.txt found, using largest bundle as super repository"
        SUPER_BUNDLE=$(ls -S *.bundle 2>/dev/null | head -n 1)
        SUPER_BUNDLE="./$SUPER_BUNDLE"
    fi
fi

cd "$SCRIPT_DIR"

SUPER_BUNDLE="${IMPORT_FOLDER}/${SUPER_BUNDLE#./}"

if [ ! -f "$SUPER_BUNDLE" ]; then
    print_error "Could not locate super repository bundle"
    exit 1
fi

SUPER_REPO_NAME=$(basename "$SUPER_BUNDLE" .bundle)
print_success "Found super repository bundle: $SUPER_BUNDLE"
print_info "Repository name: $SUPER_REPO_NAME"

##############################################################################
# CLONE SUPER REPOSITORY
##############################################################################

print_header "Step 2: Cloning Super Repository"

SUPER_REPO_PATH="${EXPORT_FOLDER}/${SUPER_REPO_NAME}"

print_info "Cloning to: $SUPER_REPO_PATH"

# Clone from bundle (suppress verbose output)
git clone --quiet "$SUPER_BUNDLE" "$SUPER_REPO_PATH" 2>&1 | grep -v "^Receiving\|^Resolving" || true

cd "$SUPER_REPO_PATH"

# Determine and checkout the default branch
print_info "Determining default branch..."

# Check if we already have a local branch (bundle may have set HEAD)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "HEAD" ]; then
    # Already on a branch
    print_success "Checked out branch: $CURRENT_BRANCH"
else
    # No local branch yet, create one from remote refs
    AVAILABLE_BRANCHES=$(git branch -r | grep -v '\->' | sed 's|^[[:space:]]*origin/||' | sed 's|^[[:space:]]*||')
    
    # Check branches in order of preference
    if echo "$AVAILABLE_BRANCHES" | grep -q "^main$"; then
        git checkout -b main origin/main
        print_success "Checked out branch: main"
    elif echo "$AVAILABLE_BRANCHES" | grep -q "^master$"; then
        git checkout -b master origin/master
        print_success "Checked out branch: master"
    elif echo "$AVAILABLE_BRANCHES" | grep -q "^develop$"; then
        git checkout -b develop origin/develop
        print_success "Checked out branch: develop"
    else
        # Use the first available branch
        FIRST_BRANCH=$(echo "$AVAILABLE_BRANCHES" | head -n 1)
        if [ -n "$FIRST_BRANCH" ]; then
            git checkout -b "$FIRST_BRANCH" "origin/$FIRST_BRANCH"
            print_warning "No main/master branch found, checked out: $FIRST_BRANCH"
        else
            print_error "No branches found in bundle"
            exit 1
        fi
    fi
fi

# Create local tracking branches for all remote branches
print_info "Creating local branches from bundle refs..."
for remote in $(git branch -r | grep -v '\->' | grep 'origin/' | sed 's|^[[:space:]]*||'); do
    branch_name=$(echo "$remote" | sed 's|origin/||' | sed 's|^[[:space:]]*||')
    if [ -n "$branch_name" ] && ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
        git branch "$branch_name" "$remote" 2>/dev/null
    fi
done &> /dev/null

# Remove the remote - all branches are now local
git remote remove origin 2>/dev/null || true
print_success "Local branches created for all remote refs"

# Get statistics (after removing remote so we only count local branches)
BRANCH_COUNT=$(git branch | wc -l)
TAG_COUNT=$(git tag | wc -l)
COMMIT_COUNT=$(git rev-list --all --count)

log_message "================================================================="
log_message "SUPER REPOSITORY: $SUPER_REPO_NAME"
log_message "================================================================="
log_message "Cloned to: $SUPER_REPO_PATH"
log_message "Branches: $BRANCH_COUNT"
log_message "Tags: $TAG_COUNT"
log_message "Total Commits: $COMMIT_COUNT"
log_message ""

print_success "Super repository cloned successfully"

cd "$SCRIPT_DIR"

##############################################################################
# DISCOVER SUBMODULE BUNDLES
##############################################################################

print_header "Step 3: Discovering Submodule Bundles"

# Find all bundle files except the super repository bundle  
# Use mindepth 2 to skip root-level bundles (which is the super repo)
SUBMODULE_BUNDLES=$(find "$IMPORT_FOLDER" -mindepth 2 -name "*.bundle" -type f | sort || true)

# Sort by directory depth (shallowest first) to ensure parent directories are created before nested ones
SUBMODULE_BUNDLES=$(echo "$SUBMODULE_BUNDLES" | awk '{ print length, $0 }' | sort -n | cut -d" " -f2-)

if [ -z "$SUBMODULE_BUNDLES" ]; then
    print_warning "No submodule bundles found"
    SUBMODULE_COUNT=0
else
    SUBMODULE_COUNT=$(echo "$SUBMODULE_BUNDLES" | wc -l)
    print_success "Found $SUBMODULE_COUNT submodule bundle(s) at all levels"
fi

##############################################################################
# PROCESS ALL SUBMODULE BUNDLES
##############################################################################

print_header "Step 4: Processing Submodules"

cd "$SUPER_REPO_PATH"

if [ "$SUBMODULE_COUNT" -eq 0 ]; then
    print_info "No submodule bundles to process"
else
    log_message "================================================================="
    log_message "SUBMODULES ($SUBMODULE_COUNT total - including nested)"
    log_message "================================================================="
    
    SUBMODULE_NUM=0
    while IFS= read -r BUNDLE_FULL_PATH; do
        SUBMODULE_NUM=$((SUBMODULE_NUM + 1))
        
        # Get the relative path from import folder
        BUNDLE_REL_PATH="${BUNDLE_FULL_PATH#$IMPORT_FOLDER/}"
        BUNDLE_REL_DIR=$(dirname "$BUNDLE_REL_PATH")
        BUNDLE_NAME=$(basename "$BUNDLE_REL_PATH" .bundle)
        
        # The submodule path is the bundle path without .bundle extension
        if [ "$BUNDLE_REL_DIR" = "." ]; then
            SUBMODULE_PATH="$BUNDLE_NAME"
        else
            SUBMODULE_PATH="${BUNDLE_REL_DIR}/${BUNDLE_NAME}"
        fi
        
        print_info "[$SUBMODULE_NUM/$SUBMODULE_COUNT] Exporting: $SUBMODULE_PATH"
        
        # Create parent directory structure if needed
        SUBMODULE_PARENT=$(dirname "$SUBMODULE_PATH")
        if [ "$SUBMODULE_PARENT" != "." ] && [ ! -d "$SUBMODULE_PARENT" ]; then
            mkdir -p "$SUBMODULE_PARENT"
        fi
        
        # Clone the submodule from bundle
        if git clone --quiet "$BUNDLE_FULL_PATH" "$SUBMODULE_PATH" 2>&1 | grep -v "^Receiving\|^Resolving" || true; then
            :  # Clone successful, continue
        else
            print_error "  ✗ Clone failed"
            log_message ""
            log_message "Submodule #$SUBMODULE_NUM: $SUBMODULE_PATH"
            log_message "Status: ✗ CLONE FAILED"
            log_message ""
            continue
        fi
        
        # Navigate to submodule
        cd "$SUBMODULE_PATH"
        
        # Determine and checkout the default branch (suppress output)
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        
        if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" = "HEAD" ]; then
            # No local branch yet, create one from remote refs
            AVAILABLE_BRANCHES=$(git branch -r | grep -v '\->' | sed 's|^[[:space:]]*origin/||' | sed 's|^[[:space:]]*||')
            
            if echo "$AVAILABLE_BRANCHES" | grep -q "^main$"; then
                git checkout -b main origin/main &>/dev/null
            elif echo "$AVAILABLE_BRANCHES" | grep -q "^master$"; then
                git checkout -b master origin/master &>/dev/null
            else
                FIRST_BRANCH=$(echo "$AVAILABLE_BRANCHES" | head -n 1)
                if [ -n "$FIRST_BRANCH" ]; then
                    git checkout -b "$FIRST_BRANCH" "origin/$FIRST_BRANCH" &>/dev/null
                fi
            fi
        fi
        
        # Create local tracking branches for all remote branches
        for remote in $(git branch -r | grep -v '\->' | grep 'origin/' | sed 's|^[[:space:]]*||'); do
            branch_name=$(echo "$remote" | sed 's|origin/||' | sed 's|^[[:space:]]*||')
            if [ -n "$branch_name" ] && ! git show-ref --verify --quiet "refs/heads/$branch_name"; then
                git branch "$branch_name" "$remote" 2>/dev/null || true
            fi
        done &> /dev/null
        
        # Remove remote origin (air-gapped) - do this AFTER creating local branches
        git remote remove origin 2>/dev/null || true
        
        # Get statistics (after removing remote so we only count local branches)
        SUB_BRANCH_COUNT=$(git branch | wc -l)
        SUB_TAG_COUNT=$(git tag | wc -l)
        SUB_COMMIT_COUNT=$(git rev-list --all --count)
        
        print_success "  ✓ Exported ($SUB_BRANCH_COUNT branches, $SUB_TAG_COUNT tags)"
        
        log_message ""
        log_message "Submodule #$SUBMODULE_NUM: $SUBMODULE_PATH"
        log_message "-----------------------------------------------------------------"
        log_message "Status: ✓ CLONED"
        log_message "Branches: $SUB_BRANCH_COUNT"
        log_message "Tags: $SUB_TAG_COUNT"
        log_message "Total Commits: $SUB_COMMIT_COUNT"
        log_message ""
        
        # Return to super repository root
        cd "$SUPER_REPO_PATH"
    done < <(echo "$SUBMODULE_BUNDLES")
    
    print_success "All submodules processed"
fi

cd "$SCRIPT_DIR"

##############################################################################
# CREATE NETWORK CONNECTIVITY NOTES
##############################################################################

print_header "Step 5: Creating Documentation"

NETWORK_NOTES="${EXPORT_FOLDER}/NETWORK_CONNECTIVITY_NOTES.txt"

{
    echo "================================================================="
    echo "Network Connectivity Notes"
    echo "================================================================="
    echo "Generated: $(date)"
    echo ""
    echo "CURRENT CONFIGURATION (Air-gapped):"
    echo "-----------------------------------------------------------------"
    echo "The repository has been cloned from git bundles without remote"
    echo "URLs configured. This is intentional for air-gapped networks."
    echo ""
    echo "FUTURE NETWORK CONNECTIVITY:"
    echo "-----------------------------------------------------------------"
    echo "If/when network connectivity becomes available between networks,"
    echo "you can configure remote URLs for the repositories:"
    echo ""
    echo "For the super repository:"
    echo "  cd $SUPER_REPO_PATH"
    echo "  git remote add origin <URL>"
    echo ""
    echo "For submodules, you have two options:"
    echo ""
    echo "Option 1: Manually configure each submodule remote"
    echo "  cd $SUPER_REPO_PATH/<submodule-path>"
    echo "  git remote add origin <URL>"
    echo ""
    echo "Option 2: Update .gitmodules and sync"
    echo "  cd $SUPER_REPO_PATH"
    echo "  # Edit .gitmodules to restore original URLs"
    echo "  git submodule sync"
    echo "  git submodule update --init --recursive --remote"
    echo ""
    echo "VERIFYING INTEGRITY:"
    echo "-----------------------------------------------------------------"
    echo "To verify the repository was cloned correctly:"
    echo "  cd $SUPER_REPO_PATH"
    echo "  git log --oneline -10"
    echo "  git submodule status"
    echo ""
    echo "PUSHING TO REMOTE (when connectivity available):"
    echo "-----------------------------------------------------------------"
    echo "  cd $SUPER_REPO_PATH"
    echo "  git remote add origin <URL>"
    echo "  git push -u origin --all"
    echo "  git push -u origin --tags"
    echo ""
    echo "  # Push submodules"
    echo "  git submodule foreach --recursive 'git push -u origin --all'"
    echo "  git submodule foreach --recursive 'git push -u origin --tags'"
    echo ""
    echo "================================================================="
} > "$NETWORK_NOTES"

print_success "Network connectivity notes created: $NETWORK_NOTES"

##############################################################################
# FINAL SUMMARY
##############################################################################

print_header "Export Complete!"

TOTAL_SIZE=$(du -sh "$EXPORT_FOLDER" | awk '{print $1}')

echo ""
print_success "Export folder: $EXPORT_FOLDER"
print_success "Total size: $TOTAL_SIZE"
print_success "Super repository: $SUPER_REPO_NAME"
print_success "Submodules: $SUBMODULE_COUNT initialized"
echo ""
print_info "Repository location:"
echo "  $SUPER_REPO_PATH"
echo ""
print_info "Documentation created:"
echo "  - export_log.txt (detailed export log)"
echo "  - NETWORK_CONNECTIVITY_NOTES.txt (remote configuration guide)"
echo ""
print_warning "Important Notes:"
echo "  1. All repositories are currently air-gapped (no remote URLs)"
echo "  2. Default branch '$DEFAULT_BRANCH' has been checked out where available"
echo "  3. See NETWORK_CONNECTIVITY_NOTES.txt for future remote setup"
echo ""

log_message "================================================================="
log_message "SUMMARY"
log_message "================================================================="
log_message "Total Export Size: $TOTAL_SIZE"
log_message "Super Repository: $SUPER_REPO_NAME"
log_message "Submodules Initialized: $SUBMODULE_COUNT"
log_message "Repository Path: $SUPER_REPO_PATH"
log_message "Script Completed: $(date)"
log_message "================================================================="

print_success "All done! ✓"
echo ""
print_info "You can now work with your repository at:"
echo "  cd $SUPER_REPO_PATH"