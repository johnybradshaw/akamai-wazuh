#!/bin/bash
# ============================================================================
# Update Kustomization with New Registry
# ============================================================================
# This script updates the kustomization.yml file to use images from your
# internal registry instead of Docker Hub.
#
# Usage:
#   ./scripts/update-registry.sh <registry> [version]
#
# Examples:
#   ./scripts/update-registry.sh harbor.company.com/wazuh
#   ./scripts/update-registry.sh registry.company.com/security/wazuh 4.14.1
#
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# ============================================================================
# Parse Arguments
# ============================================================================
if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 <registry> [version]"
    echo ""
    echo "Examples:"
    echo "  $0 harbor.company.com/wazuh"
    echo "  $0 registry.company.com/security/wazuh 4.14.1"
    echo ""
    exit 1
fi

REGISTRY="$1"
VERSION="${2:-4.14.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZATION_FILE="$SCRIPT_DIR/../kubernetes/kustomization.yml"

# Remove trailing slash
REGISTRY="${REGISTRY%/}"

echo ""
log_info "Target Registry:  $REGISTRY"
log_info "Wazuh Version:    $VERSION"
log_info "Kustomization:    $KUSTOMIZATION_FILE"
echo ""

# ============================================================================
# Backup Original
# ============================================================================
if [[ -f "$KUSTOMIZATION_FILE" ]]; then
    BACKUP_FILE="${KUSTOMIZATION_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$KUSTOMIZATION_FILE" "$BACKUP_FILE"
    log_success "Backup created: $BACKUP_FILE"
fi

# ============================================================================
# Update Image References
# ============================================================================
log_info "Updating image references..."

# Use sed to update the images section
sed -i.tmp "
/^images:/,/^[^ ]/ {
    /name: wazuh\/wazuh-indexer/,/newTag:/ {
        s|newName:.*|newName: ${REGISTRY}/wazuh-indexer|
        s|newTag:.*|newTag: ${VERSION}|
    }
    /name: wazuh\/wazuh-manager/,/newTag:/ {
        s|newName:.*|newName: ${REGISTRY}/wazuh-manager|
        s|newTag:.*|newTag: ${VERSION}|
    }
    /name: wazuh\/wazuh-dashboard/,/newTag:/ {
        s|newName:.*|newName: ${REGISTRY}/wazuh-dashboard|
        s|newTag:.*|newTag: ${VERSION}|
    }
}
" "$KUSTOMIZATION_FILE"

# Remove temp file
rm -f "${KUSTOMIZATION_FILE}.tmp"

log_success "Kustomization updated"

# ============================================================================
# Show Changes
# ============================================================================
echo ""
log_info "Updated image configuration:"
echo ""
grep -A 10 "^images:" "$KUSTOMIZATION_FILE"
echo ""

# ============================================================================
# Next Steps
# ============================================================================
log_success "Configuration updated successfully!"
echo ""
log_info "Next Steps:"
echo "  1. Review the changes above"
echo "  2. Deploy the updated configuration:"
echo "     kubectl apply -k kubernetes/"
echo ""
log_info "Rollback if needed:"
echo "     mv $BACKUP_FILE $KUSTOMIZATION_FILE"
echo ""
