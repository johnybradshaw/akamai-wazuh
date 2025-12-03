#!/bin/bash
# ============================================================================
# Regenerate Wazuh TLS Certificates
# ============================================================================
# This script regenerates TLS certificates for Wazuh Indexer and Dashboard.
# Use this if you encounter SSL/TLS errors during indexer startup.
#
# Usage:
#   ./scripts/regenerate-certs.sh
#
# What this script does:
#   1. Clones wazuh-kubernetes repository (if missing)
#   2. Generates indexer cluster certificates
#   3. Generates dashboard HTTP certificates
#   4. Verifies all required certificates are present
#
# After running this script, you need to:
#   kubectl rollout restart statefulset/wazuh-indexer -n wazuh
#
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WAZUH_K8S_DIR="$PROJECT_ROOT/kubernetes/wazuh-kubernetes"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

echo -e "\n${GREEN}Wazuh Certificate Regeneration Script${NC}\n"

# Step 1: Check/clone wazuh-kubernetes repository
if [ -d "$WAZUH_K8S_DIR" ]; then
    log_info "wazuh-kubernetes repository already exists at: $WAZUH_K8S_DIR"

    # Check if it's a git repository
    if [ -d "$WAZUH_K8S_DIR/.git" ]; then
        log_info "Updating wazuh-kubernetes repository..."
        cd "$WAZUH_K8S_DIR"
        git pull origin master || log_warning "Could not update repository (continuing with existing version)"
        cd "$PROJECT_ROOT"
    fi
else
    log_info "Cloning wazuh-kubernetes repository..."
    git clone https://github.com/wazuh/wazuh-kubernetes.git "$WAZUH_K8S_DIR"
    log_success "Repository cloned successfully"
fi

# Step 2: Generate indexer cluster certificates
log_info "Generating indexer cluster certificates..."
INDEXER_CERT_DIR="$WAZUH_K8S_DIR/wazuh/certs/indexer_cluster"

if [ ! -d "$INDEXER_CERT_DIR" ]; then
    log_error "Indexer certificate directory not found: $INDEXER_CERT_DIR"
    exit 1
fi

cd "$INDEXER_CERT_DIR"
if [ ! -f "generate_certs.sh" ]; then
    log_error "Certificate generation script not found: $INDEXER_CERT_DIR/generate_certs.sh"
    exit 1
fi

# Remove old certificates if they exist
if [ -f "root-ca.pem" ]; then
    log_warning "Removing existing indexer certificates..."
    rm -f *.pem *.csr
fi

bash generate_certs.sh > /dev/null 2>&1
log_success "Indexer certificates generated"

# Step 3: Generate dashboard HTTP certificates
log_info "Generating dashboard HTTP certificates..."
DASHBOARD_CERT_DIR="$WAZUH_K8S_DIR/wazuh/certs/dashboard_http"

if [ ! -d "$DASHBOARD_CERT_DIR" ]; then
    log_error "Dashboard certificate directory not found: $DASHBOARD_CERT_DIR"
    exit 1
fi

cd "$DASHBOARD_CERT_DIR"
if [ ! -f "generate_certs.sh" ]; then
    log_error "Certificate generation script not found: $DASHBOARD_CERT_DIR/generate_certs.sh"
    exit 1
fi

# Remove old certificates if they exist
if [ -f "cert.pem" ]; then
    log_warning "Removing existing dashboard certificates..."
    rm -f *.pem
fi

bash generate_certs.sh > /dev/null 2>&1
log_success "Dashboard certificates generated"

# Return to project root
cd "$PROJECT_ROOT"

# Step 4: Verify all required certificates exist
log_info "Verifying certificate generation..."

MISSING_CERTS=0

# Check indexer certificates
REQUIRED_INDEXER_CERTS=(
    "root-ca.pem"
    "node.pem"
    "node-key.pem"
    "dashboard.pem"
    "dashboard-key.pem"
    "admin.pem"
    "admin-key.pem"
    "filebeat.pem"
    "filebeat-key.pem"
)

for cert in "${REQUIRED_INDEXER_CERTS[@]}"; do
    if [ ! -f "$INDEXER_CERT_DIR/$cert" ]; then
        log_error "Missing indexer certificate: $cert"
        MISSING_CERTS=$((MISSING_CERTS + 1))
    fi
done

# Check dashboard certificates
REQUIRED_DASHBOARD_CERTS=(
    "cert.pem"
    "key.pem"
)

for cert in "${REQUIRED_DASHBOARD_CERTS[@]}"; do
    if [ ! -f "$DASHBOARD_CERT_DIR/$cert" ]; then
        log_error "Missing dashboard certificate: $cert"
        MISSING_CERTS=$((MISSING_CERTS + 1))
    fi
done

if [ $MISSING_CERTS -gt 0 ]; then
    log_error "Certificate generation failed! $MISSING_CERTS certificates are missing."
    exit 1
fi

log_success "All required certificates are present"

# Step 5: Display next steps
echo -e "\n${GREEN}Certificate generation completed successfully!${NC}\n"
echo "Next steps to apply the new certificates:"
echo ""
echo "  1. If this is a fresh deployment:"
echo "     ${BLUE}kubectl apply -k kubernetes/${NC}"
echo ""
echo "  2. If you have an existing deployment:"
echo "     ${BLUE}kubectl delete secret -n wazuh indexer-certs dashboard-certs${NC}"
echo "     ${BLUE}kubectl apply -k kubernetes/${NC}"
echo "     ${BLUE}kubectl rollout restart statefulset/wazuh-indexer -n wazuh${NC}"
echo "     ${BLUE}kubectl rollout restart deployment/wazuh-dashboard -n wazuh${NC}"
echo ""
echo "  3. Monitor the rollout:"
echo "     ${BLUE}kubectl get pods -n wazuh -w${NC}"
echo ""

log_info "For more information, see: docs/TROUBLESHOOTING-INDEXER-SSL.md"
