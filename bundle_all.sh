#!/bin/bash

##############################################################################
# bundle_all.sh
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
REPO_PATH="/path/to/your/super-repository"

# SSH remote Git address (for reference/documentation purposes)
# Example: git@bitbucket.org:company/super-repo.git
REMOTE_GIT_ADDRESS="git@bitbucket.org:your-org/your-repo.git"

##############################################################################
# SCRIPT CONFIGURATION - Generally no need to edit below
##############################################################################

# Generate timestamp for export folder
TIMESTAMP=$(date +%Y%m%d_%H%M)
EXPORT_FOLDER="${TIMESTAMP}_import"
LOG_FILE="${EXPORT_FOLDER}/bundle_verification.txt"

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

log_message() {
    echo "$1" | tee -a "$LOG_FILE"
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
BUNDLE_PATH="../${EXPORT_FOLDER}/${BUNDLE_NAME}"

print_info "Repository: $REPO_NAME"
print_info "Bundling to: $BUNDLE_PATH"

# Create bundle with all references
git bundle create "$BUNDLE_PATH" --all

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

# Initialize submodules if not already initialized
print_info "Initializing submodules..."
git submodule update --init --recursive

# Get list of submodules with their paths
SUBMODULE_COUNT=$(git config --file .gitmodules --get-regexp path | wc -l || echo "0")

if [ "$SUBMODULE_COUNT" -eq 0 ]; then
    print_warning "No submodules found in this repository"
    log_message "No submodules found."
else
    print_success "Found $SUBMODULE_COUNT submodule(s)"
    log_message "================================================================="
    log_message "SUBMODULES ($SUBMODULE_COUNT total)"
    log_message "================================================================="
    
    # Create a temporary file to store submodule paths
    SUBMODULE_LIST=$(mktemp)
    git config --file .gitmodules --get-regexp path | awk '{print $2}' > "$SUBMODULE_LIST"
    
    SUBMODULE_NUM=0
    while IFS= read -r SUBMODULE_PATH; do
        SUBMODULE_NUM=$((SUBMODULE_NUM + 1))
        
        print_info "[$SUBMODULE_NUM/$SUBMODULE_COUNT] Processing: $SUBMODULE_PATH"
        
        # Get absolute path to submodule
        SUBMODULE_FULL_PATH="$REPO_PATH/$SUBMODULE_PATH"
        
        if [ ! -d "$SUBMODULE_FULL_PATH/.git" ]; then
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
            mkdir -p "../${EXPORT_FOLDER}/${SUBMODULE_DIR}"
        fi
        
        # Bundle filename and path
        SUBMODULE_BUNDLE_NAME="${SUBMODULE_NAME}.bundle"
        if [ "$SUBMODULE_DIR" != "." ]; then
            SUBMODULE_BUNDLE_PATH="../${EXPORT_FOLDER}/${SUBMODULE_DIR}/${SUBMODULE_BUNDLE_NAME}"
        else
            SUBMODULE_BUNDLE_PATH="../${EXPORT_FOLDER}/${SUBMODULE_BUNDLE_NAME}"
        fi
        
        # Navigate to submodule and create bundle
        cd "$SUBMODULE_FULL_PATH"
        
        print_info "  Creating bundle..."
        git bundle create "$SUBMODULE_BUNDLE_PATH" --all
        
        # Verify bundle
        if git bundle verify "$SUBMODULE_BUNDLE_PATH" &> /dev/null; then
            print_success "  Bundle verified"
            SUBMODULE_VERIFIED="✓ VERIFIED"
        else
            print_error "  Bundle verification FAILED"
            SUBMODULE_VERIFIED="✗ FAILED"
        fi
        
        # Calculate SHA256
        SUBMODULE_SHA256=$(sha256sum "$SUBMODULE_BUNDLE_PATH" | awk '{print $1}')
        SUBMODULE_SIZE=$(du -h "$SUBMODULE_BUNDLE_PATH" | awk '{print $1}')
        
        # Get Git statistics
        SUB_BRANCH_COUNT=$(git branch -a | wc -l)
        SUB_TAG_COUNT=$(git tag | wc -l)
        SUB_COMMIT_COUNT=$(git rev-list --all --count)
        
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
        
    done < "$SUBMODULE_LIST"
    
    # Clean up temp file
    rm -f "$SUBMODULE_LIST"
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
cd "../${EXPORT_FOLDER}"
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

cd - > /dev/null

print_success "Metadata file created: $METADATA_FILE"

##############################################################################
# FINAL SUMMARY
##############################################################################

print_header "Bundling Complete!"

TOTAL_SIZE=$(du -sh "../${EXPORT_FOLDER}" | awk '{print $1}')

echo ""
print_success "Export folder: $EXPORT_FOLDER"
print_success "Total size: $TOTAL_SIZE"
print_success "Super repository: 1 bundle created"
print_success "Submodules: $SUBMODULE_COUNT bundle(s) created"
echo ""
print_info "Files created:"
echo "  - bundle_verification.txt (detailed verification log)"
echo "  - metadata.txt (export metadata and instructions)"
echo ""
print_warning "Next Steps:"
echo "  1. Review the verification log: ${EXPORT_FOLDER}/bundle_verification.txt"
echo "  2. Transfer the entire '${EXPORT_FOLDER}' folder to destination network"
echo "  3. Run export_all.sh on the destination network"
echo ""

log_message "================================================================="
log_message "SUMMARY"
log_message "================================================================="
log_message "Total Export Size: $TOTAL_SIZE"
log_message "Super Repository Bundles: 1"
log_message "Submodule Bundles: $SUBMODULE_COUNT"
log_message "Script Completed: $(date)"
log_message "================================================================="

print_success "All done! ✓"
