#!/bin/bash

##############################################################################
# export_all.sh
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
# Leave empty to auto-detect the most recent *_import folder
IMPORT_FOLDER=""

# Default branch to checkout (typically 'main' or 'master')
DEFAULT_BRANCH="main"

##############################################################################
# SCRIPT CONFIGURATION - Generally no need to edit below
##############################################################################

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
TIMESTAMP=$(echo "$IMPORT_FOLDER" | sed 's/_import$//')
EXPORT_FOLDER="${TIMESTAMP}_export"

print_info "Export folder will be: $EXPORT_FOLDER"

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
# It's the bundle that's not in any subdirectory
SUPER_BUNDLE=$(find "$IMPORT_FOLDER" -maxdepth 1 -name "*.bundle" -type f | head -n 1)

if [ -z "$SUPER_BUNDLE" ]; then
    print_error "No super repository bundle found in $IMPORT_FOLDER"
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

# Clone from bundle
git clone "$SUPER_BUNDLE" "$SUPER_REPO_PATH"

cd "$SUPER_REPO_PATH"

# Checkout default branch
print_info "Checking out branch: $DEFAULT_BRANCH"
if git show-ref --verify --quiet "refs/heads/$DEFAULT_BRANCH"; then
    git checkout "$DEFAULT_BRANCH"
    print_success "Checked out branch: $DEFAULT_BRANCH"
else
    print_warning "Branch '$DEFAULT_BRANCH' not found, staying on current branch"
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    print_info "Current branch: $CURRENT_BRANCH"
fi

# Get statistics
BRANCH_COUNT=$(git branch -a | wc -l)
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

cd - > /dev/null

##############################################################################
# DISCOVER SUBMODULE BUNDLES
##############################################################################

print_header "Step 3: Discovering Submodule Bundles"

# Find all bundle files except the super repository bundle
SUBMODULE_BUNDLES=$(find "$IMPORT_FOLDER" -name "*.bundle" -type f | grep -v "^${IMPORT_FOLDER}/[^/]*\.bundle$" || true)

if [ -z "$SUBMODULE_BUNDLES" ]; then
    print_warning "No submodule bundles found"
    SUBMODULE_COUNT=0
else
    SUBMODULE_COUNT=$(echo "$SUBMODULE_BUNDLES" | wc -l)
    print_success "Found $SUBMODULE_COUNT submodule bundle(s)"
fi

##############################################################################
# CHECK FOR .gitmodules FILE
##############################################################################

print_header "Step 4: Processing Submodules"

cd "$SUPER_REPO_PATH"

if [ ! -f ".gitmodules" ]; then
    if [ "$SUBMODULE_COUNT" -gt 0 ]; then
        print_warning "Found submodule bundles but no .gitmodules file in super repository"
        print_warning "This may indicate an issue with the source repository"
    else
        print_info "No .gitmodules file found (no submodules configured)"
    fi
    cd - > /dev/null
else
    print_info "Found .gitmodules configuration"
    
    # Get list of configured submodules
    CONFIGURED_SUBMODULES=$(git config --file .gitmodules --get-regexp path | awk '{print $2}' || true)
    
    if [ -z "$CONFIGURED_SUBMODULES" ]; then
        print_warning "No submodules configured in .gitmodules"
        cd - > /dev/null
    else
        CONFIGURED_COUNT=$(echo "$CONFIGURED_SUBMODULES" | wc -l)
        print_success "Found $CONFIGURED_COUNT configured submodule(s)"
        
        log_message "================================================================="
        log_message "SUBMODULES ($CONFIGURED_COUNT total)"
        log_message "================================================================="
        
        SUBMODULE_NUM=0
        echo "$CONFIGURED_SUBMODULES" | while IFS= read -r SUBMODULE_PATH; do
            SUBMODULE_NUM=$((SUBMODULE_NUM + 1))
            
            print_info "[$SUBMODULE_NUM/$CONFIGURED_COUNT] Processing: $SUBMODULE_PATH"
            
            SUBMODULE_NAME=$(basename "$SUBMODULE_PATH")
            SUBMODULE_DIR=$(dirname "$SUBMODULE_PATH")
            
            # Construct bundle path
            if [ "$SUBMODULE_DIR" = "." ]; then
                SUBMODULE_BUNDLE="../../../${IMPORT_FOLDER}/${SUBMODULE_NAME}.bundle"
            else
                SUBMODULE_BUNDLE="../../../${IMPORT_FOLDER}/${SUBMODULE_DIR}/${SUBMODULE_NAME}.bundle"
            fi
            
            # Check if bundle exists
            if [ ! -f "$SUBMODULE_BUNDLE" ]; then
                print_error "Bundle not found for submodule: $SUBMODULE_PATH"
                print_error "Expected: $SUBMODULE_BUNDLE"
                log_message ""
                log_message "Submodule #$SUBMODULE_NUM: $SUBMODULE_PATH"
                log_message "Status: ✗ BUNDLE NOT FOUND"
                log_message ""
                continue
            fi
            
            # Get the submodule URL from .gitmodules
            SUBMODULE_URL=$(git config --file .gitmodules --get "submodule.${SUBMODULE_PATH}.url" || echo "")
            
            # Update .gitmodules to point to the bundle file temporarily
            # Note: For air-gapped networks, we'll use the bundle file path
            # For future network connectivity, you can update these URLs later
            
            print_info "  Initializing submodule from bundle..."
            
            # Create submodule directory if it doesn't exist
            mkdir -p "$SUBMODULE_PATH"
            
            # Clone the submodule from bundle
            git clone "$SUBMODULE_BUNDLE" "$SUBMODULE_PATH"
            
            # Navigate to submodule
            cd "$SUBMODULE_PATH"
            
            # Checkout default branch
            if git show-ref --verify --quiet "refs/heads/$DEFAULT_BRANCH"; then
                git checkout "$DEFAULT_BRANCH" 2>/dev/null || true
                print_success "  Checked out branch: $DEFAULT_BRANCH"
            else
                print_warning "  Branch '$DEFAULT_BRANCH' not found in submodule"
            fi
            
            # Get statistics
            SUB_BRANCH_COUNT=$(git branch -a | wc -l)
            SUB_TAG_COUNT=$(git tag | wc -l)
            SUB_COMMIT_COUNT=$(git rev-list --all --count)
            
            # For future network connectivity: Set the original remote URL
            # This is commented out for air-gapped use, but can be enabled later
            if [ -n "$SUBMODULE_URL" ]; then
                git remote remove origin 2>/dev/null || true
                # Uncomment the next line when network connectivity is available:
                # git remote add origin "$SUBMODULE_URL"
                print_info "  Original URL: $SUBMODULE_URL (not set as remote for air-gapped use)"
            fi
            
            log_message ""
            log_message "Submodule #$SUBMODULE_NUM: $SUBMODULE_PATH"
            log_message "-----------------------------------------------------------------"
            log_message "Status: ✓ CLONED"
            log_message "Branches: $SUB_BRANCH_COUNT"
            log_message "Tags: $SUB_TAG_COUNT"
            log_message "Total Commits: $SUB_COMMIT_COUNT"
            log_message "Original URL: $SUBMODULE_URL"
            log_message ""
            
            print_success "  Submodule initialized: $SUBMODULE_PATH"
            
            # Return to super repository root
            cd - > /dev/null
        done
        
        cd - > /dev/null
        
        # Re-enter super repository for final steps
        cd "$SUPER_REPO_PATH"
        
        # Initialize git submodule tracking
        print_info "Registering submodules with Git..."
        git submodule init 2>/dev/null || true
        
        print_success "All submodules processed"
        
        cd - > /dev/null
    fi
fi

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
print_success "Submodules: $CONFIGURED_COUNT initialized"
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
log_message "Submodules Initialized: $CONFIGURED_COUNT"
log_message "Repository Path: $SUPER_REPO_PATH"
log_message "Script Completed: $(date)"
log_message "================================================================="

print_success "All done! ✓"
echo ""
print_info "You can now work with your repository at:"
echo "  cd $SUPER_REPO_PATH"
