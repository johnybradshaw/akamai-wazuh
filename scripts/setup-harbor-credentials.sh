#!/bin/bash
# ============================================================================
# Setup Harbor Image Pull Secret
# ============================================================================
# This script creates a Kubernetes secret with Harbor credentials and
# configures the wazuh namespace to use it for pulling images.
#
# Usage:
#   ./scripts/setup-harbor-credentials.sh
#
# The script will prompt for:
#   - Harbor registry URL
#   - Harbor username
#   - Harbor password/token
#
# Or set environment variables:
#   HARBOR_URL=harbor.company.com
#   HARBOR_USERNAME=admin
#   HARBOR_PASSWORD=yourpassword
#   ./scripts/setup-harbor-credentials.sh
#
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Setup Harbor Image Pull Secret                          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# Configuration
# ============================================================================
NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
SECRET_NAME="harbor-credentials"

# Get Harbor credentials
if [[ -z "${HARBOR_URL:-}" ]]; then
    echo -n "Harbor URL (e.g., harbor.lke540223.akamai-apl.net): "
    read -r HARBOR_URL
fi

if [[ -z "${HARBOR_USERNAME:-}" ]]; then
    echo -n "Harbor Username: "
    read -r HARBOR_USERNAME
fi

if [[ -z "${HARBOR_PASSWORD:-}" ]]; then
    echo -n "Harbor Password: "
    read -rs HARBOR_PASSWORD
    echo ""
fi

if [[ -z "${HARBOR_EMAIL:-}" ]]; then
    HARBOR_EMAIL="${HARBOR_USERNAME}@example.com"
fi

log_info "Harbor URL:      $HARBOR_URL"
log_info "Username:        $HARBOR_USERNAME"
log_info "Namespace:       $NAMESPACE"
log_info "Secret Name:     $SECRET_NAME"
echo ""

# ============================================================================
# Check Prerequisites
# ============================================================================
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# ============================================================================
# Create Namespace if needed
# ============================================================================
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_info "Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
    log_success "Namespace created"
else
    log_info "Namespace $NAMESPACE already exists"
fi

# ============================================================================
# Create Image Pull Secret
# ============================================================================
log_info "Creating image pull secret..."

# Delete existing secret if present
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_warning "Secret already exists, deleting old one..."
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
fi

# Create new secret
kubectl create secret docker-registry "$SECRET_NAME" \
    --docker-server="$HARBOR_URL" \
    --docker-username="$HARBOR_USERNAME" \
    --docker-password="$HARBOR_PASSWORD" \
    --docker-email="$HARBOR_EMAIL" \
    -n "$NAMESPACE"

log_success "Image pull secret created: $SECRET_NAME"

# ============================================================================
# Patch Service Accounts
# ============================================================================
log_info "Configuring service accounts to use the secret..."

# Patch default service account
kubectl patch serviceaccount default -n "$NAMESPACE" \
    -p "{\"imagePullSecrets\": [{\"name\": \"$SECRET_NAME\"}]}" || true

log_success "Default service account configured"

# ============================================================================
# Restart Pods to Pick Up Secret
# ============================================================================
log_info "Restarting Wazuh pods to use new credentials..."

# Check if deployments/statefulsets exist before restarting
if kubectl get statefulset wazuh-indexer -n "$NAMESPACE" &> /dev/null; then
    kubectl rollout restart statefulset wazuh-indexer -n "$NAMESPACE"
fi

if kubectl get statefulset wazuh-manager-master -n "$NAMESPACE" &> /dev/null; then
    kubectl rollout restart statefulset wazuh-manager-master -n "$NAMESPACE"
fi

if kubectl get statefulset wazuh-manager-worker -n "$NAMESPACE" &> /dev/null; then
    kubectl rollout restart statefulset wazuh-manager-worker -n "$NAMESPACE"
fi

if kubectl get deployment wazuh-dashboard -n "$NAMESPACE" &> /dev/null; then
    kubectl rollout restart deployment wazuh-dashboard -n "$NAMESPACE"
fi

log_success "Pods restarted"

# ============================================================================
# Verify
# ============================================================================
echo ""
log_info "Waiting for pods to restart (30 seconds)..."
sleep 30

echo ""
log_info "Checking pod status..."
kubectl get pods -n "$NAMESPACE"

echo ""
log_info "Checking for image pull errors..."
IMAGE_PULL_ERRORS=$(kubectl get events -n "$NAMESPACE" --field-selector reason=Failed | grep -i "imagepull\|backoff" || true)

if [[ -z "$IMAGE_PULL_ERRORS" ]]; then
    log_success "No image pull errors found!"
else
    log_warning "Some image pull errors still present:"
    echo "$IMAGE_PULL_ERRORS"
fi

# ============================================================================
# Success
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Image Pull Secret Setup Complete                        ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Harbor credentials configured"
echo ""
log_info "Verify deployment:"
echo "  ${CYAN}kubectl get pods -n $NAMESPACE${NC}"
echo "  ${CYAN}kubectl describe pod <pod-name> -n $NAMESPACE${NC}"
echo ""
log_info "Check if images are pulling:"
echo "  ${CYAN}kubectl get events -n $NAMESPACE | grep -i pull${NC}"
echo ""
log_info "To update credentials later, run this script again"
echo ""
