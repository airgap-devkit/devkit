#!/bin/bash

##############################################################################
# create_full_test_repo.sh
#
# Creates a comprehensive test repository with:
# - Multiple branches and tags at ALL levels
# - Root-level submodules
# - Nested submodules at various depths
# - Rich commit history everywhere
##############################################################################

set -e

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEST_DIR="${SCRIPT_DIR}/test"

echo "============================================================"
echo "Creating Comprehensive Test Repository"
echo "============================================================"
echo ""
echo "This will create:"
echo "  • Super repository with 4 branches, 4 tags"
echo "  • 2 root-level submodules (each with 4 branches, 3 tags)"
echo "  • 2 nested submodules at level 2 (each with 3 branches, 2 tags)"
echo "  • 1 deeply nested submodule at level 3 (3 branches, 2 tags)"
echo ""
echo "Test location: ${TEST_DIR}"
echo ""
read -p "Press Enter to continue..."

# Clean up if exists
rm -rf "${TEST_DIR}" 2>/dev/null || true
mkdir -p "${TEST_DIR}"
cd "${TEST_DIR}"

##############################################################################
# 1. CREATE BASE REPOSITORIES WITH BRANCHES & TAGS
##############################################################################

echo ""
echo "============================================================"
echo "Step 1: Creating Base Repositories"
echo "============================================================"

# ----- BASE 1: user-service (will be root-level submodule) -----
echo ""
echo "[1/5] Creating user-service (root-level submodule)..."
mkdir full-test-base-user-service
cd full-test-base-user-service
git init
git config --local protocol.file.allow always

cat > user.py << 'EOF'
class User:
    version = "1.0.0"
    def login(self): return "logged in"
EOF
git add . && git commit -m "Initial user service v1.0"
git tag v1.0.0

git checkout -b develop
cat > user.py << 'EOF'
class User:
    version = "1.5.0"
    def login(self): return "logged in"
    def logout(self): return "logged out"
EOF
git add . && git commit -m "Add logout feature"
git tag v1.5.0

git checkout -b feature/oauth
cat > oauth.py << 'EOF'
def oauth_login(): return "oauth"
EOF
git add . && git commit -m "Add OAuth support"

git checkout develop
git checkout -b release/2.0
cat > user.py << 'EOF'
class User:
    version = "2.0.0"
    def login(self): return "logged in v2"
    def logout(self): return "logged out"
EOF
git add . && git commit -m "Release v2.0"
git tag v2.0.0

git checkout main
USER_SERVICE_PATH=$(pwd)
echo "✓ user-service: 4 branches (main, develop, feature/oauth, release/2.0), 3 tags"

# ----- BASE 2: payment-service (will be root-level submodule) -----
cd "${TEST_DIR}"
echo ""
echo "[2/5] Creating payment-service (root-level submodule)..."
mkdir full-test-base-payment-service
cd full-test-base-payment-service
git init
git config --local protocol.file.allow always

cat > payment.py << 'EOF'
class Payment:
    version = "1.0.0"
    def process(self): return "processed"
EOF
git add . && git commit -m "Initial payment service v1.0"
git tag v1.0.0

git checkout -b develop
cat > payment.py << 'EOF'
class Payment:
    version = "1.2.0"
    def process(self): return "processed"
    def refund(self): return "refunded"
EOF
git add . && git commit -m "Add refund feature"
git tag v1.2.0

git checkout -b feature/stripe
cat > stripe.py << 'EOF'
def stripe_payment(): return "stripe"
EOF
git add . && git commit -m "Add Stripe integration"

git checkout -b hotfix/1.0.1 main
cat > payment.py << 'EOF'
class Payment:
    version = "1.0.1"
    def process(self): return "processed (fixed)"
EOF
git add . && git commit -m "Hotfix v1.0.1"
git tag v1.0.1

git checkout main
PAYMENT_SERVICE_PATH=$(pwd)
echo "✓ payment-service: 4 branches (main, develop, feature/stripe, hotfix/1.0.1), 3 tags"

# ----- BASE 3: database-lib (will be nested in user-service) -----
cd "${TEST_DIR}"
echo ""
echo "[3/5] Creating database-lib (nested level 2)..."
mkdir full-test-base-database-lib
cd full-test-base-database-lib
git init
git config --local protocol.file.allow always

cat > db.py << 'EOF'
class Database:
    version = "1.0"
    def connect(self): return "connected"
EOF
git add . && git commit -m "Initial database library"
git tag v1.0

git checkout -b develop
cat > db.py << 'EOF'
class Database:
    version = "2.0"
    def connect(self): return "connected"
    def disconnect(self): return "disconnected"
EOF
git add . && git commit -m "Add disconnect"
git tag v2.0

git checkout -b feature/pool
cat > pool.py << 'EOF'
class ConnectionPool: pass
EOF
git add . && git commit -m "Add connection pool"

git checkout main
DATABASE_LIB_PATH=$(pwd)
echo "✓ database-lib: 3 branches (main, develop, feature/pool), 2 tags"

# ----- BASE 4: cache-lib (will be nested in payment-service) -----
cd "${TEST_DIR}"
echo ""
echo "[4/5] Creating cache-lib (nested level 2)..."
mkdir full-test-base-cache-lib
cd full-test-base-cache-lib
git init
git config --local protocol.file.allow always

cat > cache.py << 'EOF'
class Cache:
    version = "1.0"
    def set(self, k, v): pass
    def get(self, k): pass
EOF
git add . && git commit -m "Initial cache library"
git tag v1.0

git checkout -b develop
cat > cache.py << 'EOF'
class Cache:
    version = "1.5"
    def set(self, k, v): pass
    def get(self, k): pass
    def delete(self, k): pass
EOF
git add . && git commit -m "Add delete method"
git tag v1.5

git checkout -b feature/redis
cat > redis.py << 'EOF'
def redis_cache(): return "redis"
EOF
git add . && git commit -m "Add Redis backend"

git checkout main
CACHE_LIB_PATH=$(pwd)
echo "✓ cache-lib: 3 branches (main, develop, feature/redis), 2 tags"

# ----- BASE 5: logger-lib (will be deeply nested in database-lib) -----
cd "${TEST_DIR}"
echo ""
echo "[5/5] Creating logger-lib (nested level 3)..."
mkdir full-test-base-logger-lib
cd full-test-base-logger-lib
git init
git config --local protocol.file.allow always

cat > logger.py << 'EOF'
class Logger:
    def log(self, msg): print(msg)
EOF
git add . && git commit -m "Initial logger"
git tag v1.0

git checkout -b develop
cat > logger.py << 'EOF'
class Logger:
    def log(self, msg): print(msg)
    def error(self, msg): print("ERROR:", msg)
EOF
git add . && git commit -m "Add error logging"
git tag v2.0

git checkout -b feature/json
cat > logger.py << 'EOF'
import json
class Logger:
    def log(self, msg): print(json.dumps(msg))
    def error(self, msg): print("ERROR:", msg)
EOF
git add . && git commit -m "Add JSON logging"

git checkout main
LOGGER_LIB_PATH=$(pwd)
echo "✓ logger-lib: 3 branches (main, develop, feature/json), 2 tags"

##############################################################################
# 2. CREATE NESTED SUBMODULE STRUCTURE
##############################################################################

echo ""
echo "============================================================"
echo "Step 2: Creating Nested Submodule Structure"
echo "============================================================"

# Add logger-lib to database-lib (level 3 nesting)
cd "$DATABASE_LIB_PATH"
git checkout main
mkdir -p utils
git -c protocol.file.allow=always submodule add "file://$LOGGER_LIB_PATH" utils/logger
git commit -m "Add logger as nested submodule"

# Merge into other branches
git checkout develop
git merge main -m "Merge logger submodule"
git checkout feature/pool
git merge develop -m "Merge logger submodule"
git checkout main

echo "✓ database-lib now contains logger-lib (level 3 nesting)"

# Add database-lib to user-service (level 2 nesting)
cd "$USER_SERVICE_PATH"
git checkout main
mkdir -p lib
git -c protocol.file.allow=always submodule add "file://$DATABASE_LIB_PATH" lib/database
git commit -m "Add database-lib as nested submodule"

# Merge into other branches
git checkout develop
git merge main -m "Merge database submodule"
git checkout feature/oauth
git merge develop -m "Merge database submodule"
git checkout main

echo "✓ user-service now contains database-lib (which contains logger-lib)"

# Add cache-lib to payment-service (level 2 nesting)
cd "$PAYMENT_SERVICE_PATH"
git checkout main
mkdir -p lib
git -c protocol.file.allow=always submodule add "file://$CACHE_LIB_PATH" lib/cache
git commit -m "Add cache-lib as nested submodule"

# Merge into other branches
git checkout develop
git merge main -m "Merge cache submodule"
git checkout feature/stripe
git merge develop -m "Merge cache submodule"
git checkout main

echo "✓ payment-service now contains cache-lib"

##############################################################################
# 3. CREATE SUPER REPOSITORY
##############################################################################

echo ""
echo "============================================================"
echo "Step 3: Creating Super Repository"
echo "============================================================"

cd "${TEST_DIR}"
mkdir full-test-repo
cd full-test-repo
git init
git config --local protocol.file.allow always

cat > README.md << 'EOF'
# Full Test Application
Version: 1.0.0
A comprehensive microservices application for testing git bundles.
EOF
cat > .gitignore << 'EOF'
*.pyc
__pycache__/
.env
EOF
git add . && git commit -m "Initial commit v1.0"
git tag v1.0.0

echo ""
echo "Adding root-level submodules..."

# Add user-service at root level
git -c protocol.file.allow=always submodule add "file://$USER_SERVICE_PATH" services/user-service
git commit -m "Add user-service"

# Add payment-service at root level
git -c protocol.file.allow=always submodule add "file://$PAYMENT_SERVICE_PATH" services/payment-service
git commit -m "Add payment-service"
git tag v1.5.0

echo ""
echo "Creating branches in super repository..."

# Create develop branch
git checkout -b develop
cat > README.md << 'EOF'
# Full Test Application
Version: 2.0.0-dev
A comprehensive microservices application for testing git bundles.
## Development Version
New features in development.
EOF
git add . && git commit -m "Update to v2.0-dev"
git tag v2.0.0-dev

# Create feature branch
git checkout -b feature/api-gateway
cat > gateway.py << 'EOF'
class APIGateway:
    def route(self): return "routed"
EOF
git add . && git commit -m "Add API gateway"

# Create release branch
git checkout develop
git checkout -b release/2.0
cat > README.md << 'EOF'
# Full Test Application
Version: 2.0.0
A comprehensive microservices application for testing git bundles.
## Production Release
Ready for deployment.
EOF
git add . && git commit -m "Release v2.0"
git tag v2.0.0

git checkout main

SUPER_PATH=$(pwd)
echo "✓ Super repository created with 4 branches, 4 tags"

##############################################################################
# 4. SUMMARY
##############################################################################

echo ""
echo "============================================================"
echo "✓ Full Test Repository Created Successfully!"
echo "============================================================"
echo ""
echo "REPOSITORY STRUCTURE:"
echo "------------------------------------------------------------"
echo "full-test-repo/                          ← Super Repository"
echo "├── 4 branches: main, develop, feature/api-gateway, release/2.0"
echo "├── 4 tags: v1.0.0, v1.5.0, v2.0.0-dev, v2.0.0"
echo "│"
echo "└── services/"
echo "    ├── user-service/                    ← ROOT-LEVEL Submodule"
echo "    │   ├── 4 branches: main, develop, feature/oauth, release/2.0"
echo "    │   ├── 3 tags: v1.0.0, v1.5.0, v2.0.0"
echo "    │   │"
echo "    │   └── lib/"
echo "    │       └── database/                ← NESTED Level 2"
echo "    │           ├── 3 branches: main, develop, feature/pool"
echo "    │           ├── 2 tags: v1.0, v2.0"
echo "    │           │"
echo "    │           └── utils/"
echo "    │               └── logger/          ← DEEPLY NESTED Level 3"
echo "    │                   ├── 3 branches: main, develop, feature/json"
echo "    │                   └── 2 tags: v1.0, v2.0"
echo "    │"
echo "    └── payment-service/                 ← ROOT-LEVEL Submodule"
echo "        ├── 4 branches: main, develop, feature/stripe, hotfix/1.0.1"
echo "        ├── 3 tags: v1.0.0, v1.2.0, v1.0.1"
echo "        │"
echo "        └── lib/"
echo "            └── cache/                   ← NESTED Level 2"
echo "                ├── 3 branches: main, develop, feature/redis"
echo "                └── 2 tags: v1.0, v1.5"
echo ""
echo "TOTAL CONTENT:"
echo "------------------------------------------------------------"
echo "• Super Repository:      4 branches, 4 tags"
echo "• user-service:          4 branches, 3 tags (ROOT LEVEL)"
echo "• payment-service:       4 branches, 3 tags (ROOT LEVEL)"
echo "• database-lib:          3 branches, 2 tags (NESTED LEVEL 2)"
echo "• cache-lib:             3 branches, 2 tags (NESTED LEVEL 2)"
echo "• logger-lib:            3 branches, 2 tags (NESTED LEVEL 3)"
echo ""
echo "TOTAL: 21 branches, 16 tags across 6 repositories"
echo ""
echo "Repository Location: $SUPER_PATH"
echo ""
echo "============================================================"
echo "TESTING INSTRUCTIONS"
echo "============================================================"
echo ""
echo "1. CONFIGURE bundle_all.sh:"
echo "   cd ${SCRIPT_DIR}"
echo "   nano bundle_all.sh"
echo "   # Set: REPO_PATH=\"${SUPER_PATH}\""
echo ""
echo "2. RUN BUNDLE:"
echo "   ./bundle_all.sh"
echo ""
echo "3. RUN EXPORT:"
echo "   ./export_all.sh"
echo ""
echo "4. RUN VERIFICATION:"
echo "   ./verify_full_test.sh"
echo ""
echo "5. MANUAL VERIFICATION (if needed):"
echo "   cd YYYYMMDD_HHmm_export/full-test-repo"
echo "   "
echo "   # Check super repo (should show 4 branches)"
echo "   git branch"
echo "   "
echo "   # Check ROOT-LEVEL user-service (should show 4 branches)"
echo "   cd services/user-service && git branch && cd ../.."
echo "   "
echo "   # Check ROOT-LEVEL payment-service (should show 4 branches)"
echo "   cd services/payment-service && git branch && cd ../.."
echo "   "
echo "   # Check NESTED database-lib (should show 3 branches)"
echo "   cd services/user-service/lib/database && git branch && cd ../../../.."
echo "   "
echo "   # Check NESTED cache-lib (should show 3 branches)"
echo "   cd services/payment-service/lib/cache && git branch && cd ../../../.."
echo "   "
echo "   # Check DEEPLY NESTED logger-lib (should show 3 branches)"
echo "   cd services/user-service/lib/database/utils/logger && git branch"
echo ""
echo "6. EXPECTED RESULTS:"
echo "   ✓ Super repo: 4 branches"
echo "   ✓ user-service: 4 branches (NOT just main!)"
echo "   ✓ payment-service: 4 branches (NOT just main!)"
echo "   ✓ database-lib: 3 branches"
echo "   ✓ cache-lib: 3 branches"
echo "   ✓ logger-lib: 3 branches"
echo ""
echo "============================================================"
echo ""