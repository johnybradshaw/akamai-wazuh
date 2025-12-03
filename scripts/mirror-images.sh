#!/bin/bash
# ============================================================================
# Mirror Wazuh Images to Internal Registry
# ============================================================================
# This script pulls Wazuh images from Docker Hub and pushes them to your
# organization's approved container registry.
#
# Usage:
#   ./scripts/mirror-images.sh <target-registry>
#
# Example:
#   ./scripts/mirror-images.sh harbor.company.com/wazuh
#   ./scripts/mirror-images.sh registry.company.com/security/wazuh
#
# Requirements:
#   - docker installed and authenticated to target registry
#   - Network access to Docker Hub
#   - Push permissions to target registry
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# ============================================================================
# Parse Arguments
# ============================================================================
if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 <target-registry>"
    echo ""
    echo "Examples:"
    echo "  $0 harbor.company.com/wazuh"
    echo "  $0 registry.company.com/security/wazuh"
    echo ""
    exit 1
fi

TARGET_REGISTRY="$1"
WAZUH_VERSION="4.14.1"
SOURCE_REGISTRY="docker.io/wazuh"

# Remove trailing slash if present
TARGET_REGISTRY="${TARGET_REGISTRY%/}"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Mirror Wazuh Images to Internal Registry                ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Source Registry:  $SOURCE_REGISTRY"
log_info "Target Registry:  $TARGET_REGISTRY"
log_info "Wazuh Version:    $WAZUH_VERSION"
echo ""

# Images to mirror
IMAGES=(
    "wazuh-indexer"
    "wazuh-manager"
    "wazuh-dashboard"
)

# ============================================================================
# Check Prerequisites
# ============================================================================
log_info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    log_error "docker is not installed"
    exit 1
fi
log_success "docker found"

if ! docker ps &> /dev/null; then
    log_error "docker daemon is not running"
    exit 1
fi
log_success "docker daemon running"

# ============================================================================
# Mirror Images
# ============================================================================
FAILED_IMAGES=()
SUCCESS_COUNT=0

for image in "${IMAGES[@]}"; do
    echo ""
    log_info "Processing: $image:$WAZUH_VERSION"

    SOURCE_IMAGE="${SOURCE_REGISTRY}/${image}:${WAZUH_VERSION}"
    TARGET_IMAGE="${TARGET_REGISTRY}/${image}:${WAZUH_VERSION}"

    # Pull from Docker Hub
    log_info "  Pulling from Docker Hub..."
    if docker pull "$SOURCE_IMAGE"; then
        log_success "  Pull successful"
    else
        log_error "  Failed to pull $SOURCE_IMAGE"
        FAILED_IMAGES+=("$image")
        continue
    fi

    # Tag for target registry
    log_info "  Tagging for target registry..."
    if docker tag "$SOURCE_IMAGE" "$TARGET_IMAGE"; then
        log_success "  Tag successful"
    else
        log_error "  Failed to tag"
        FAILED_IMAGES+=("$image")
        continue
    fi

    # Push to target registry
    log_info "  Pushing to $TARGET_REGISTRY..."
    if docker push "$TARGET_IMAGE"; then
        log_success "  Push successful: $TARGET_IMAGE"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "  Failed to push $TARGET_IMAGE"
        log_warning "  Make sure you're authenticated to $TARGET_REGISTRY"
        FAILED_IMAGES+=("$image")
        continue
    fi
done

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Mirror Summary                                           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Total images:     ${#IMAGES[@]}"
log_success "Successful:       $SUCCESS_COUNT"

if [[ ${#FAILED_IMAGES[@]} -gt 0 ]]; then
    log_error "Failed:           ${#FAILED_IMAGES[@]}"
    echo ""
    log_warning "Failed images:"
    for img in "${FAILED_IMAGES[@]}"; do
        echo "  • $img"
    done
    echo ""
fi

# ============================================================================
# Next Steps
# ============================================================================
if [[ $SUCCESS_COUNT -eq ${#IMAGES[@]} ]]; then
    echo ""
    log_success "All images mirrored successfully!"
    echo ""
    log_info "Next Steps:"
    echo ""
    echo "1. Update kubernetes/kustomization.yml with new image locations:"
    echo ""
    echo "   images:"
    for image in "${IMAGES[@]}"; do
        echo "     - name: wazuh/${image}"
        echo "       newName: ${TARGET_REGISTRY}/${image}"
        echo "       newTag: ${WAZUH_VERSION}"
    done
    echo ""
    echo "2. Redeploy Wazuh:"
    echo "   kubectl apply -k kubernetes/"
    echo ""
    echo "3. Verify deployment:"
    echo "   kubectl get pods -n wazuh"
    echo ""
else
    log_error "Some images failed to mirror"
    log_info "Please fix the errors above and try again"
    exit 1
fi
