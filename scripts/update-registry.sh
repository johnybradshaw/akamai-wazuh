#!/bin/bash
# ============================================================================
# Update Kustomization with New Registry
# ============================================================================
# This script updates the kustomization.yml file to use images from your
# internal registry instead of Docker Hub.
#
# Supports Harbor proxy projects and other registries.
#
# Usage:
#   ./scripts/update-registry.sh <registry-path> [version] [--proxy]
#
# Examples:
#   # Direct registry (manually mirrored)
#   ./scripts/update-registry.sh harbor.company.com/wazuh
#
#   # Harbor proxy project (automatic pull-through cache)
#   ./scripts/update-registry.sh harbor.company.com/dockerhub-proxy/wazuh --proxy
#
#   # With custom version
#   ./scripts/update-registry.sh harbor.company.com/wazuh 4.14.1
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

# ============================================================================
# Parse Arguments
# ============================================================================
if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 <registry-path> [version] [--proxy]"
    echo ""
    echo "Examples:"
    echo "  # Direct registry (manually mirrored images)"
    echo "  $0 harbor.company.com/wazuh"
    echo ""
    echo "  # Harbor proxy project (recommended - auto pull-through)"
    echo "  $0 harbor.company.com/dockerhub-proxy/wazuh --proxy"
    echo ""
    echo "  # With custom version"
    echo "  $0 harbor.company.com/wazuh 4.14.1"
    echo ""
    exit 1
fi

REGISTRY="$1"
VERSION="4.14.1"
IS_PROXY="false"

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --proxy)
            IS_PROXY="true"
            shift
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUSTOMIZATION_FILE="$SCRIPT_DIR/../kubernetes/kustomization.yml"

# Remove trailing slash
REGISTRY="${REGISTRY%/}"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Update Registry Configuration                           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Target Registry:  $REGISTRY"
log_info "Wazuh Version:    $VERSION"
log_info "Proxy Mode:       $IS_PROXY"
log_info "Kustomization:    $KUSTOMIZATION_FILE"
echo ""

if [[ "$IS_PROXY" == "true" ]]; then
    log_info "Using Harbor Proxy Project - no manual mirroring needed!"
fi

# ============================================================================
# Backup Original
# ============================================================================
if [[ -f "$KUSTOMIZATION_FILE" ]]; then
    BACKUP_FILE="${KUSTOMIZATION_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$KUSTOMIZATION_FILE" "$BACKUP_FILE"
    log_success "Backup created: $(basename $BACKUP_FILE)"
else
    log_error "Kustomization file not found: $KUSTOMIZATION_FILE"
    exit 1
fi

# ============================================================================
# Update Image References
# ============================================================================
log_info "Updating image references..."

# Use Python for more reliable YAML manipulation
python3 << PYEOF
import sys
import re

KUSTOMIZATION_FILE = '$KUSTOMIZATION_FILE'
REGISTRY = '$REGISTRY'
VERSION = '$VERSION'

# Read the file
with open(KUSTOMIZATION_FILE, 'r') as f:
    content = f.read()

# Function to update or add newName field
def update_image(content, image_name, new_registry, version):
    # Pattern to match the image block with or without existing newName
    # Group 1: "  - name: wazuh/image-name\n"
    # Group 2: optional existing "    newName: ...\n"
    # Group 3: "    newTag: "
    # Group 4: version number
    pattern = r'(  - name: wazuh/' + re.escape(image_name) + r'\n)(?:    newName: [^\n]+\n)?(    newTag: )([^\n]+)'

    # Replacement: add/replace newName and update version
    replacement = r'\g<1>    newName: ' + new_registry + '/' + image_name + r'\n\g<2>' + version

    # Apply replacement
    new_content = re.sub(pattern, replacement, content)

    return new_content

# Update each image
content = update_image(content, 'wazuh-indexer', REGISTRY, VERSION)
content = update_image(content, 'wazuh-manager', REGISTRY, VERSION)
content = update_image(content, 'wazuh-dashboard', REGISTRY, VERSION)

# Write back
with open(KUSTOMIZATION_FILE, 'w') as f:
    f.write(content)

print("Images updated successfully")
PYEOF

if [[ $? -eq 0 ]]; then
    log_success "Kustomization updated"
else
    log_error "Failed to update kustomization"
    log_info "Restoring backup..."
    mv "$BACKUP_FILE" "$KUSTOMIZATION_FILE"
    exit 1
fi

# ============================================================================
# Show Changes
# ============================================================================
echo ""
log_info "Updated image configuration:"
echo ""
# Extract images section - show from "images:" to the next non-indented section
sed -n '/^images:/,/^[a-z][^:]*:/p' "$KUSTOMIZATION_FILE" | sed '$d'
echo ""

# ============================================================================
# Verify Changes
# ============================================================================
log_info "Verifying changes..."
if grep -q "newName: ${REGISTRY}" "$KUSTOMIZATION_FILE"; then
    log_success "Registry path correctly set to: $REGISTRY"
else
    log_error "Registry path was not updated correctly"
    log_info "Restoring backup..."
    mv "$BACKUP_FILE" "$KUSTOMIZATION_FILE"
    exit 1
fi

# ============================================================================
# Next Steps
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Configuration Updated Successfully                       ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

if [[ "$IS_PROXY" == "true" ]]; then
    log_success "Using Harbor proxy - images will be pulled automatically"
    echo ""
    log_info "Next Steps:"
    echo "  1. Deploy the updated configuration:"
    echo -e "     ${CYAN}kubectl apply -k kubernetes/${NC}"
    echo ""
    echo "  2. Harbor will automatically pull and cache images on first use"
    echo ""
else
    log_warning "Using direct registry - ensure images are already mirrored"
    echo ""
    log_info "Next Steps:"
    echo "  1. Verify images exist in your registry:"
    echo -e "     ${CYAN}docker pull ${REGISTRY}/wazuh-indexer:${VERSION}${NC}"
    echo -e "     ${CYAN}docker pull ${REGISTRY}/wazuh-manager:${VERSION}${NC}"
    echo -e "     ${CYAN}docker pull ${REGISTRY}/wazuh-dashboard:${VERSION}${NC}"
    echo ""
    echo "  2. Deploy the updated configuration:"
    echo -e "     ${CYAN}kubectl apply -k kubernetes/${NC}"
    echo ""
fi

echo "  3. Verify deployment:"
echo -e "     ${CYAN}kubectl get pods -n wazuh${NC}"
echo -e "     ${CYAN}kubectl get events -n wazuh | grep -i policy${NC}"
echo ""
log_info "Backup saved: $BACKUP_FILE"
echo -e "${BLUE}ℹ${NC} Rollback: ${CYAN}mv $BACKUP_FILE $KUSTOMIZATION_FILE${NC}"
echo ""
