#!/bin/bash
# ============================================================================
# Initialize Wazuh Indexer Security
# ============================================================================
# This script initializes the OpenSearch security plugin in the Wazuh indexer.
# Run this if you see "Not yet initialized (you may need to run securityadmin)"
#
# Usage:
#   ./scripts/init-security.sh [OPTIONS]
#
# Options:
#   --namespace NAME    Kubernetes namespace (default: wazuh)
#   --pod NAME          Specific pod to run on (default: wazuh-indexer-0)
#   --help              Show this help message
#
# What this script does:
#   1. Waits for indexer pods to be ready
#   2. Runs securityadmin.sh to initialize security configuration
#   3. Verifies the security index was created
#
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="wazuh"
POD_NAME="wazuh-indexer-0"

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --pod)
            POD_NAME="$2"
            shift 2
            ;;
        --help)
            sed -n '2,20p' "$0" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "\n${GREEN}Wazuh Indexer Security Initialization${NC}\n"

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

# Check namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_error "Namespace '$NAMESPACE' not found"
    exit 1
fi

# Step 1: Wait for indexer pods to be ready
log_info "Waiting for indexer pods to be ready..."

TIMEOUT=300  # 5 minutes
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=wazuh-indexer \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)

    TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=wazuh-indexer --no-headers 2>/dev/null | wc -l)

    if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
        log_success "All $TOTAL_PODS indexer pods are ready"
        break
    fi

    if [ $((ELAPSED % 10)) -eq 0 ]; then
        log_info "Waiting... ($READY_PODS/$TOTAL_PODS pods ready)"
    fi

    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_warning "Timeout waiting for pods to be ready, proceeding anyway..."
fi

# Step 2: Check if security index already exists
log_info "Checking if security index exists..."

SECURITY_INDEX_EXISTS=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c \
    "curl -s -k -u admin:SecretPassword https://localhost:9200/_cat/indices/.opendistro_security 2>/dev/null || echo 'not_found'" || echo "error")

if [[ "$SECURITY_INDEX_EXISTS" != *"not_found"* ]] && [[ "$SECURITY_INDEX_EXISTS" != *"error"* ]]; then
    log_warning "Security index already exists. If you're having issues, you may need to reinitialize."
    read -p "Do you want to reinitialize the security configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping initialization"
        exit 0
    fi
fi

# Step 3: Run securityadmin to initialize security
log_info "Running securityadmin to initialize security configuration..."

SECURITYADMIN_CMD="
cd /usr/share/wazuh-indexer/plugins/opensearch-security/tools && \
JAVA_HOME=/usr/share/wazuh-indexer/jdk bash securityadmin.sh \
  -cd /usr/share/wazuh-indexer/config/opensearch-security \
  -icl \
  -nhnv \
  -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
  -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
  -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
  -h localhost
"

log_info "Executing securityadmin on pod: $POD_NAME"

if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "$SECURITYADMIN_CMD"; then
    log_success "Security configuration initialized successfully"
else
    log_error "Failed to initialize security configuration"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check pod logs: kubectl logs -n $NAMESPACE $POD_NAME"
    echo "2. Verify certificates exist and are valid"
    echo "3. Ensure all indexer pods are running"
    echo "4. Check opensearch.yml configuration"
    exit 1
fi

# Step 4: Verify security index was created
log_info "Verifying security index creation..."
sleep 5

VERIFY_CMD="curl -s -k -u admin:SecretPassword https://localhost:9200/_cat/indices/.opendistro_security"

if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "$VERIFY_CMD" 2>/dev/null | grep -q ".opendistro_security"; then
    log_success "Security index created successfully"
else
    log_warning "Could not verify security index creation"
fi

# Step 5: Test cluster health
log_info "Checking cluster health..."

HEALTH_CMD="curl -s -k -u admin:SecretPassword https://localhost:9200/_cluster/health?pretty"

if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- bash -c "$HEALTH_CMD" 2>/dev/null; then
    log_success "Cluster is accessible"
else
    log_warning "Could not check cluster health"
fi

echo -e "\n${GREEN}Security initialization completed!${NC}\n"
echo "Next steps:"
echo "  1. Verify indexer pods are running: ${BLUE}kubectl get pods -n $NAMESPACE${NC}"
echo "  2. Check indexer logs: ${BLUE}kubectl logs -n $NAMESPACE $POD_NAME${NC}"
echo "  3. Test dashboard access: https://wazuh.yourdomain.com"
echo ""
log_info "Default credentials: admin / SecretPassword (change after first login)"
