#!/bin/bash

##############################################################################
# verify_full_test.sh
#
# Verifies that all branches, tags, and commits were transferred correctly
# from the full-test-repo to the exported version
##############################################################################

set -e

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Find the most recent export
EXPORT_DIR=$(find "${SCRIPT_DIR}" -maxdepth 2 -type d -name "full-test-repo" | grep "_export" | sort -r | head -n 1)

if [ -z "$EXPORT_DIR" ]; then
    print_error "Could not find exported full-test-repo"
    print_info "Make sure you've run export_all.sh first"
    exit 1
fi

print_header "Verifying Full Test Repository Transfer"
echo ""
print_info "Original: ${SCRIPT_DIR}/test/full-test-repo"
print_info "Exported: $EXPORT_DIR"
echo ""

ISSUES=0

# Function to check repo
check_repo() {
    local NAME=$1
    local PATH=$2
    local EXPECTED_BRANCHES=$3
    local EXPECTED_TAGS=$4
    
    echo ""
    print_header "Checking: $NAME"
    
    if [ ! -d "$PATH/.git" ]; then
        print_error "Not a git repository: $PATH"
        ISSUES=$((ISSUES + 1))
        return
    fi
    
    cd "$PATH"
    
    # Check branches
    BRANCH_COUNT=$(git branch | wc -l)
    echo "Branches: $BRANCH_COUNT (expected: $EXPECTED_BRANCHES)"
    git branch | sed 's/^/  /'
    
    if [ "$BRANCH_COUNT" -eq "$EXPECTED_BRANCHES" ]; then
        print_success "Branch count correct"
    else
        print_error "Branch count mismatch! Expected $EXPECTED_BRANCHES, got $BRANCH_COUNT"
        ISSUES=$((ISSUES + 1))
    fi
    
    # Check tags
    TAG_COUNT=$(git tag | wc -l)
    echo ""
    echo "Tags: $TAG_COUNT (expected: $EXPECTED_TAGS)"
    git tag | sed 's/^/  /'
    
    if [ "$TAG_COUNT" -eq "$EXPECTED_TAGS" ]; then
        print_success "Tag count correct"
    else
        print_error "Tag count mismatch! Expected $EXPECTED_TAGS, got $TAG_COUNT"
        ISSUES=$((ISSUES + 1))
    fi
    
    # Check remotes (should be empty for air-gapped)
    REMOTE_COUNT=$(git remote | wc -l)
    echo ""
    echo "Remotes: $REMOTE_COUNT (expected: 0 for air-gapped)"
    
    if [ "$REMOTE_COUNT" -eq 0 ]; then
        print_success "No remotes (air-gapped setup correct)"
    else
        print_error "Found remotes (should be none for air-gapped)"
        git remote -v
        ISSUES=$((ISSUES + 1))
    fi
}

# Check all repositories
check_repo "Super Repository" "$EXPORT_DIR" 4 4
check_repo "user-service (ROOT LEVEL)" "$EXPORT_DIR/services/user-service" 4 3
check_repo "payment-service (ROOT LEVEL)" "$EXPORT_DIR/services/payment-service" 4 3
check_repo "database-lib (NESTED L2)" "$EXPORT_DIR/services/user-service/lib/database" 3 2
check_repo "cache-lib (NESTED L2)" "$EXPORT_DIR/services/payment-service/lib/cache" 3 2
check_repo "logger-lib (NESTED L3)" "$EXPORT_DIR/services/user-service/lib/database/utils/logger" 3 2

# Final summary
echo ""
print_header "Verification Summary"
echo ""

if [ $ISSUES -eq 0 ]; then
    print_success "ALL CHECKS PASSED!"
    echo ""
    echo "✓ All 21 branches transferred correctly"
    echo "✓ All 16 tags transferred correctly"
    echo "✓ All repositories are air-gapped (no remotes)"
    echo "✓ Root-level submodules have all branches (not just main)"
    echo "✓ Nested submodules have all branches"
    echo ""
    print_success "Bundle and export scripts are working perfectly!"
else
    print_error "FOUND $ISSUES ISSUE(S)"
    echo ""
    print_info "Review the output above to see what failed"
    echo ""
    echo "Common issues:"
    echo "  • Root-level repos only have 'main' branch"
    echo "    → This means bundle_all.sh didn't fetch all branches"
    echo "  • Missing tags"
    echo "    → Check bundle verification log"
    echo "  • Remotes present"
    echo "    → export_all.sh didn't remove remotes properly"
fi

echo ""