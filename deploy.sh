#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh SIEM Quick-Start Deployment Script
# ============================================================================
# This script deploys a production-ready Wazuh SIEM platform on
# Akamai Cloud Computing (Linode Kubernetes Engine).
#
# What this script does:
#   1. Validates prerequisites and configuration
#   2. Initializes the wazuh-kubernetes base manifests (git submodule)
#   3. Generates TLS certificates
#   4. Installs infrastructure prerequisites (nginx, cert-manager, ExternalDNS)
#   5. Generates secure random passwords
#   6. Deploys Wazuh using Kustomize
#   7. Waits for deployment readiness
#   8. Initializes Wazuh Indexer security configuration
#   9. Displays access information
#
# Deployment profiles (DEPLOY_PROFILE / --profile):
#   akamai            Turnkey deployment on Akamai Cloud (LKE). Installs
#                     nginx-ingress, cert-manager and ExternalDNS, verifies the
#                     domain on Linode DNS, and provisions Linode NodeBalancers.
#   existing-cluster  Deploy onto an existing Kubernetes cluster using your own
#                     ingress controller, storage class, TLS and DNS
#                     (bring-your-own infrastructure). Skips the Akamai/Linode
#                     specific provisioning steps.
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --dry-run           Validate configuration without deploying
#   --profile NAME      Deployment profile: akamai (default) or existing-cluster
#   --existing-cluster  Shorthand for --profile existing-cluster
#   --skip-prereqs      Skip prerequisite installation
#   --skip-certs        Skip certificate generation
#   --force             Force deployment even if validation fails
#   --help              Show this help message
#
# Requirements:
#   - kubectl configured for the target cluster
#   - git (this repository is a normal git checkout so the wazuh-kubernetes
#     submodule can be initialised; or run with --recurse-submodules on clone)
#   - helm 3.x (only for the "akamai" profile, to install prerequisites)
#   - docker (for password hash generation)
#   - jq (for JSON parsing)
#   - config.env file (see config.env.example)
#
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration and Global Variables
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default options
DRY_RUN=false
SKIP_PREREQS=false
SKIP_CERTS=false
FORCE=false
# Deployment profile may be overridden on the CLI; CLI wins over config.env.
PROFILE_CLI=""

# Logging
LOG_FILE="$SCRIPT_DIR/deploy.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "\n${CYAN}==>${NC} ${MAGENTA}$1${NC}\n"; }

# ============================================================================
# Help Function
# ============================================================================
show_help() {
    cat << EOF
Akamai Cloud Wazuh Quick-Start Deployment Script

Usage: $0 [OPTIONS]

Options:
  --dry-run           Validate configuration without deploying
  --profile NAME      Deployment profile: akamai (default) or existing-cluster
  --existing-cluster  Shorthand for --profile existing-cluster
  --skip-prereqs      Skip prerequisite installation (nginx, cert-manager, ExternalDNS)
  --skip-certs        Skip certificate generation
  --force             Force deployment even if validation warnings occur
  --help              Show this help message

Requirements:
  - kubectl configured for the target cluster
  - git (to initialise the wazuh-kubernetes submodule)
  - helm 3.x (akamai profile only, for installing prerequisites)
  - docker installed (for password hash generation)
  - jq installed (for JSON parsing)
  - config.env file with required variables

Configuration (config.env):
  DOMAIN                - Your root domain (akamai profile: DNS must be on Linode)
  LINODE_API_TOKEN      - Linode API token (akamai profile / MANAGE_DNS=true)
  LETSENCRYPT_EMAIL     - Email for Let's Encrypt certificates (when MANAGE_TLS=true)
  DEPLOY_PROFILE        - akamai (default) or existing-cluster
  STORAGE_PROVISIONER   - CSI provisioner for the wazuh-storage class
  INGRESS_CLASS         - Ingress class for the dashboard (default: nginx)
  CLUSTER_ISSUER        - cert-manager ClusterIssuer (default: letsencrypt-prod)

Examples:
  # Turnkey deployment on Akamai Cloud (LKE)
  ./deploy.sh

  # Validate configuration without deploying
  ./deploy.sh --dry-run

  # Deploy onto an existing cluster with your own ingress/storage/TLS/DNS
  ./deploy.sh --existing-cluster

  # Deploy without installing prerequisites (already installed)
  ./deploy.sh --skip-prereqs

For more information: https://github.com/johnybradshaw/akamai-wazuh
EOF
    exit 0
}

# ============================================================================
# Parse Command Line Arguments
# ============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --profile)
            PROFILE_CLI="${2:-}"
            if [[ -z "$PROFILE_CLI" ]]; then
                log_error "--profile requires an argument (akamai or existing-cluster)"
                exit 1
            fi
            shift 2
            ;;
        --existing-cluster)
            PROFILE_CLI="existing-cluster"
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        --skip-certs)
            SKIP_CERTS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Banner
# ============================================================================
cat << "EOF"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   Akamai Cloud Wazuh SIEM Quick-Start                          ║
║   Production-Ready Security Platform Deployment                 ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
echo ""
log_info "Deployment started at: $(date)"
log_info "Log file: $LOG_FILE"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY-RUN mode - no changes will be made"
    echo ""
fi

# ============================================================================
# Step 1: Load and Validate Configuration
# ============================================================================
log_step "Step 1: Loading and Validating Configuration"

# Check for config.env
if [[ ! -f "config.env" ]]; then
    log_error "Configuration file 'config.env' not found"
    log_info "Please copy config.env.example to config.env and customize it:"
    echo "  cp config.env.example config.env"
    echo "  nano config.env"
    exit 1
fi

# Load configuration
log_info "Loading configuration from config.env..."
# shellcheck source=/dev/null
source config.env

# ----------------------------------------------------------------------------
# Resolve deployment profile (CLI flag wins over config.env, default: akamai)
# ----------------------------------------------------------------------------
DEPLOY_PROFILE="${PROFILE_CLI:-${DEPLOY_PROFILE:-akamai}}"
case "$DEPLOY_PROFILE" in
    akamai|existing-cluster) ;;
    *)
        log_error "Invalid DEPLOY_PROFILE: '$DEPLOY_PROFILE' (expected: akamai or existing-cluster)"
        exit 1
        ;;
esac

# ----------------------------------------------------------------------------
# Defaults for optional variables (defaults are tuned for the akamai/LKE profile)
# ----------------------------------------------------------------------------
WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
# wazuh-kubernetes submodule ref (used only as a fallback clone target when the
# repository was not checked out with submodules, e.g. a source tarball).
WAZUH_VERSION="${WAZUH_VERSION:-4.14.6}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-600}"

# Bring-your-own-infrastructure knobs (substituted into the Kustomize overlay).
STORAGE_PROVISIONER="${STORAGE_PROVISIONER:-linodebs.csi.linode.com}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"
CLUSTER_ISSUER="${CLUSTER_ISSUER:-letsencrypt-prod}"

# Whether deploy.sh manages DNS (Linode) and TLS (cert-manager). For the
# existing-cluster profile these default to "false" (bring your own).
if [[ "$DEPLOY_PROFILE" == "existing-cluster" ]]; then
    MANAGE_DNS="${MANAGE_DNS:-false}"
    MANAGE_TLS="${MANAGE_TLS:-false}"
    # On an existing cluster we never install nginx/cert-manager/ExternalDNS.
    SKIP_PREREQS=true
else
    MANAGE_DNS="${MANAGE_DNS:-true}"
    MANAGE_TLS="${MANAGE_TLS:-true}"
fi

# ----------------------------------------------------------------------------
# Validate required variables (depends on the active profile)
# ----------------------------------------------------------------------------
REQUIRED_VARS=("DOMAIN")
# LINODE_API_TOKEN is needed for the Linode DNS check and ExternalDNS.
[[ "$MANAGE_DNS" == "true" ]] && REQUIRED_VARS+=("LINODE_API_TOKEN")
# LETSENCRYPT_EMAIL is only needed when we install cert-manager and create the
# Let's Encrypt ClusterIssuer (akamai profile). On an existing cluster you bring
# your own issuer/TLS, so it is not required.
[[ "$DEPLOY_PROFILE" == "akamai" ]] && REQUIRED_VARS+=("LETSENCRYPT_EMAIL")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    log_error "Missing required configuration variables for profile '$DEPLOY_PROFILE':"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    log_info "Please edit config.env and set all required variables"
    exit 1
fi

log_success "Configuration loaded successfully"
log_info "Profile: $DEPLOY_PROFILE (manage DNS: $MANAGE_DNS, manage TLS: $MANAGE_TLS)"
log_info "Domain: $DOMAIN"
log_info "Namespace: $WAZUH_NAMESPACE"
log_info "Storage provisioner: $STORAGE_PROVISIONER | Ingress class: $INGRESS_CLASS"

# Export for subprocesses
export DOMAIN LINODE_API_TOKEN LETSENCRYPT_EMAIL WAZUH_NAMESPACE
export DEPLOY_PROFILE STORAGE_PROVISIONER INGRESS_CLASS CLUSTER_ISSUER MANAGE_DNS MANAGE_TLS

# ============================================================================
# Step 2: Check Prerequisites
# ============================================================================
log_step "Step 2: Checking Prerequisites"

PREREQ_FAILED=false

# Check kubectl
log_info "Checking kubectl..."
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    PREREQ_FAILED=true
else
    KUBECTL_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion')
    log_success "kubectl installed: $KUBECTL_VERSION"

    # Check kubectl cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "kubectl cannot access Kubernetes cluster"
        log_info "Please configure kubectl to access your LKE cluster"
        PREREQ_FAILED=true
    else
        CLUSTER_VERSION=$(kubectl version -o json | jq -r '.serverVersion.gitVersion')
        log_success "Connected to Kubernetes cluster: $CLUSTER_VERSION"

        # Check node count and resources
        NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
        log_info "Cluster has $NODE_COUNT node(s)"

        if [[ $NODE_COUNT -lt 3 ]]; then
            log_warning "Cluster has fewer than 3 nodes (recommended minimum for HA)"
            if [[ "$FORCE" != "true" ]]; then
                log_error "Use --force to deploy anyway"
                PREREQ_FAILED=true
            fi
        fi
    fi
fi

# Check helm (only required when we install prerequisites)
if [[ "$SKIP_PREREQS" == "false" ]]; then
    log_info "Checking helm..."
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed"
        PREREQ_FAILED=true
    else
        HELM_VERSION=$(helm version --short)
        log_success "helm installed: $HELM_VERSION"
    fi
else
    log_info "Skipping helm check (prerequisite installation disabled for this profile)"
fi

# Check docker
log_info "Checking docker..."
if ! command -v docker &> /dev/null; then
    log_error "docker is not installed (required for password hash generation)"
    PREREQ_FAILED=true
else
    if ! docker ps &> /dev/null; then
        log_error "docker daemon is not running"
        PREREQ_FAILED=true
    else
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}')
        log_success "docker installed and running: $DOCKER_VERSION"
    fi
fi

# Check jq
log_info "Checking jq..."
if ! command -v jq &> /dev/null; then
    log_error "jq is not installed (required for JSON parsing)"
    PREREQ_FAILED=true
else
    JQ_VERSION=$(jq --version)
    log_success "jq installed: $JQ_VERSION"
fi

# Check git
log_info "Checking git..."
if ! command -v git &> /dev/null; then
    log_error "git is not installed (required to clone Wazuh repository)"
    PREREQ_FAILED=true
else
    GIT_VERSION=$(git --version)
    log_success "git installed: $GIT_VERSION"
fi

# Check dig (for DNS verification)
log_info "Checking dig..."
if ! command -v dig &> /dev/null; then
    log_warning "dig is not installed (DNS verification will be skipped)"
else
    log_success "dig installed"
fi

if [[ "$PREREQ_FAILED" == "true" ]]; then
    log_error "Prerequisites check failed"
    log_info "Please install missing tools and try again"
    exit 1
fi

log_success "All prerequisites satisfied"

# ============================================================================
# Step 3: Verify DNS Domain
# ============================================================================
log_step "Step 3: Verifying DNS Domain"

if [[ "$MANAGE_DNS" != "true" ]]; then
    log_info "Profile '$DEPLOY_PROFILE': skipping Linode DNS verification (bring your own DNS)"
    log_info "Ensure DNS records for the following point at your ingress / load balancers:"
    echo "  - wazuh.$DOMAIN              (dashboard)"
    echo "  - wazuh-manager.$DOMAIN      (agent events)"
    echo "  - wazuh-registration.$DOMAIN (agent registration)"
else
    log_info "Checking if domain '$DOMAIN' exists in Linode DNS..."

    # Make API call and capture the full response
    API_RESPONSE=$(curl -s -H "Authorization: Bearer $LINODE_API_TOKEN" \
        "https://api.linode.com/v4/domains")

    # Check if the response contains an error
    if echo "$API_RESPONSE" | jq -e '.errors' &> /dev/null; then
        ERROR_MSG=$(echo "$API_RESPONSE" | jq -r '.errors[0].reason // "Unknown API error"')
        log_error "Linode API error: $ERROR_MSG"
        log_info "Please verify your LINODE_API_TOKEN in config.env"
        log_info "Token should have 'Domains' Read permission"
        log_info "Create a token at: https://cloud.linode.com/profile/tokens"
        exit 1
    fi

    # Check if the response has the expected data structure
    if ! echo "$API_RESPONSE" | jq -e '.data' &> /dev/null; then
        log_error "Unexpected API response format"
        log_info "Response: $API_RESPONSE"
        log_info "Please verify your LINODE_API_TOKEN is valid"
        exit 1
    fi

    # Check if the domain exists
    DOMAIN_CHECK=$(echo "$API_RESPONSE" | jq -r ".data[]? | select(.domain==\"$DOMAIN\") | .domain")

    if [[ "$DOMAIN_CHECK" == "$DOMAIN" ]]; then
        log_success "Domain '$DOMAIN' found in Linode DNS"
    else
        log_error "Domain '$DOMAIN' not found in Linode DNS"
        log_info "Available domains:"
        echo "$API_RESPONSE" | jq -r '.data[]?.domain' | sed 's/^/  - /'
        echo ""
        log_info "Please ensure your domain is hosted on Linode/Akamai DNS"
        log_info "Visit: https://cloud.linode.com/domains"
        exit 1
    fi
fi

# ============================================================================
# Exit if Dry Run
# ============================================================================
if [[ "$DRY_RUN" == "true" ]]; then
    log_success "Dry-run validation completed successfully!"
    echo ""
    log_info "Configuration is valid and ready for deployment"
    log_info "Run without --dry-run to deploy:"
    echo "  ./deploy.sh"
    exit 0
fi

# ============================================================================
# Step 4: Prepare Wazuh Kubernetes Base Manifests (git submodule)
# ============================================================================
log_step "Step 4: Preparing Wazuh Kubernetes Base Manifests"

WAZUH_K8S_DIR="$SCRIPT_DIR/kubernetes/wazuh-kubernetes"

if [[ -f "$WAZUH_K8S_DIR/wazuh/kustomization.yml" ]]; then
    log_success "wazuh-kubernetes base manifests already present (git submodule)"
elif [[ -f "$SCRIPT_DIR/.gitmodules" ]] && git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    log_info "Initialising the wazuh-kubernetes git submodule..."
    if git -C "$SCRIPT_DIR" submodule update --init --recursive kubernetes/wazuh-kubernetes; then
        log_success "Submodule initialised"
    else
        log_error "Failed to initialise the wazuh-kubernetes submodule"
        log_info "Run manually: git submodule update --init --recursive"
        exit 1
    fi
else
    # Fallback for non-git checkouts (e.g. a source tarball): clone the pinned ref.
    log_warning "Repository was not checked out with submodules; cloning wazuh-kubernetes (${WAZUH_VERSION})..."
    git clone https://github.com/wazuh/wazuh-kubernetes.git \
        -b "$WAZUH_VERSION" \
        --depth=1 \
        "$WAZUH_K8S_DIR"
    log_success "Repository cloned successfully"
fi

# Sanity-check that the base manifests are usable before continuing.
if [[ ! -f "$WAZUH_K8S_DIR/wazuh/kustomization.yml" ]]; then
    log_error "wazuh-kubernetes base manifests not found at $WAZUH_K8S_DIR/wazuh"
    log_info "Expected the git submodule to be populated. See README (Existing cluster / git submodule)."
    exit 1
fi

# ============================================================================
# Step 5: Generate TLS Certificates
# ============================================================================
if [[ "$SKIP_CERTS" == "false" ]]; then
    log_step "Step 5: Generating TLS Certificates"

    # Generate indexer certificates with SANs
    log_info "Generating Wazuh Indexer certificates with SANs..."
    cd "$WAZUH_K8S_DIR/wazuh/certs/indexer_cluster"
    if [[ ! -f "root-ca.pem" ]]; then
        # Use improved certificate generation script with SANs
        if [[ -f "$SCRIPT_DIR/scripts/generate-indexer-certs-with-sans.sh" ]]; then
            log_info "Using improved certificate generation (with Subject Alternative Names)"
            if bash "$SCRIPT_DIR/scripts/generate-indexer-certs-with-sans.sh"; then
                # Verify certificates were created
                if [[ -f "root-ca.pem" && -f "node.pem" && -f "node-key.pem" ]]; then
                    log_success "Indexer certificates generated with SANs"
                else
                    log_error "Certificate generation completed but files are missing"
                    exit 1
                fi
            else
                log_error "Certificate generation failed"
                exit 1
            fi
        else
            log_warning "Improved script not found, using default generation"
            bash generate_certs.sh
            log_success "Indexer certificates generated (WARNING: may not have proper SANs)"
        fi
    else
        log_warning "Indexer certificates already exist, skipping"
    fi

    # Generate dashboard certificates
    log_info "Generating Wazuh Dashboard certificates..."
    cd "$WAZUH_K8S_DIR/wazuh/certs/dashboard_http"
    if [[ ! -f "root-ca.pem" ]]; then
        bash generate_certs.sh
        log_success "Dashboard certificates generated"
    else
        log_warning "Dashboard certificates already exist, skipping"
    fi

    cd "$SCRIPT_DIR"
else
    log_step "Step 5: Skipping Certificate Generation (--skip-certs)"
fi

# ============================================================================
# Step 6: Install Infrastructure Prerequisites
# ============================================================================
if [[ "$SKIP_PREREQS" == "false" ]]; then
    log_step "Step 6: Installing Infrastructure Prerequisites"
    log_info "Installing nginx-ingress, cert-manager, and ExternalDNS..."

    bash "$SCRIPT_DIR/kubernetes/scripts/install-prerequisites.sh"

    log_success "Infrastructure prerequisites installed"
else
    log_step "Step 6: Skipping Prerequisites Installation (--skip-prereqs)"
fi

# ============================================================================
# Step 7: Generate Credentials
# ============================================================================
log_step "Step 7: Generating Secure Credentials"

# Directory for overlay patches and configs
OVERLAY_DIR="$SCRIPT_DIR/kubernetes/production-overlay"
# Directory for kustomize execution (one level up to include base resources)
KUSTOMIZE_DIR="$SCRIPT_DIR/kubernetes"

bash "$SCRIPT_DIR/kubernetes/scripts/generate-credentials.sh" "$OVERLAY_DIR"

log_success "Credentials generated and saved to $OVERLAY_DIR/.credentials"

# ============================================================================
# Step 8: Prepare Kustomize Overlay
# ============================================================================
log_step "Step 8: Preparing Kustomize Overlay"

log_info "Substituting placeholders in manifests..."
log_info "  DOMAIN=$DOMAIN"
log_info "  STORAGE_PROVISIONER=$STORAGE_PROVISIONER"
log_info "  INGRESS_CLASS=$INGRESS_CLASS"
log_info "  CLUSTER_ISSUER=$CLUSTER_ISSUER"

# NOTE: this rewrites the overlay files in place (they ship with ${...}
# placeholders). Pipe '|' is used as the sed delimiter so values containing
# slashes/dots are handled safely.
for file in "$OVERLAY_DIR"/*.yaml; do
    if [[ -f "$file" ]]; then
        sed -i.bak \
            -e "s|\${DOMAIN}|$DOMAIN|g" \
            -e "s|\${STORAGE_PROVISIONER}|$STORAGE_PROVISIONER|g" \
            -e "s|\${INGRESS_CLASS}|$INGRESS_CLASS|g" \
            -e "s|\${CLUSTER_ISSUER}|$CLUSTER_ISSUER|g" \
            "$file"
        rm -f "${file}.bak"
    fi
done

log_success "Kustomize overlay prepared"

# ============================================================================
# Step 9: Create Namespace
# ============================================================================
log_step "Step 9: Creating Kubernetes Namespace"

if kubectl get namespace "$WAZUH_NAMESPACE" &> /dev/null; then
    log_warning "Namespace '$WAZUH_NAMESPACE' already exists"
else
    kubectl create namespace "$WAZUH_NAMESPACE"
    log_success "Namespace '$WAZUH_NAMESPACE' created"
fi

# ============================================================================
# Step 10: Deploy Wazuh
# ============================================================================
log_step "Step 10: Deploying Wazuh"

log_info "Applying Kustomize configuration..."
kubectl apply -k "$KUSTOMIZE_DIR"

log_success "Wazuh deployment submitted"

# ============================================================================
# Step 11: Wait for Deployment Readiness
# ============================================================================
log_step "Step 11: Waiting for Deployment Readiness"

log_info "This may take 5-10 minutes..."
log_info "Timeout: ${DEPLOYMENT_TIMEOUT}s"
echo ""

# Wait for pods to be running
log_info "Waiting for pods to start..."
ELAPSED=0
while [[ $ELAPSED -lt $DEPLOYMENT_TIMEOUT ]]; do
    TOTAL_PODS=$(kubectl get pods -n "$WAZUH_NAMESPACE" --no-headers 2>/dev/null | wc -l)
    RUNNING_PODS=$(kubectl get pods -n "$WAZUH_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || true)

    if [[ $TOTAL_PODS -gt 0 ]] && [[ $RUNNING_PODS -eq $TOTAL_PODS ]]; then
        echo "" # Clear the progress line
        log_success "All pods are running ($RUNNING_PODS/$TOTAL_PODS)"
        break
    fi

    printf "\r  Pods: %d/%d running... %ds elapsed" "$RUNNING_PODS" "$TOTAL_PODS" "$ELAPSED"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo "" # Clear the progress line

if [[ $ELAPSED -ge $DEPLOYMENT_TIMEOUT ]]; then
    log_error "Timeout waiting for pods to start"
    log_info "Check pod status: kubectl get pods -n $WAZUH_NAMESPACE"
    exit 1
fi

# Initialize Wazuh Indexer Security
log_info "Initializing Wazuh Indexer security configuration..."

# Wait for indexer pods to be ready (not just running)
log_info "Waiting for indexer pods to be ready..."
ELAPSED=0
while [[ $ELAPSED -lt 300 ]]; do
    INDEXER_READY=$(kubectl get pods -n "$WAZUH_NAMESPACE" -l app=wazuh-indexer \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)
    INDEXER_TOTAL=$(kubectl get pods -n "$WAZUH_NAMESPACE" -l app=wazuh-indexer --no-headers 2>/dev/null | wc -l)

    if [[ $INDEXER_READY -eq $INDEXER_TOTAL ]] && [[ $INDEXER_TOTAL -gt 0 ]]; then
        echo "" # Clear the progress line
        log_success "All indexer pods are ready ($INDEXER_READY/$INDEXER_TOTAL)"
        break
    fi

    printf "\r  Indexer pods: %d/%d ready... %ds elapsed" "$INDEXER_READY" "$INDEXER_TOTAL" "$ELAPSED"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo "" # Clear the progress line

if [[ $ELAPSED -ge 300 ]]; then
    log_warning "Timeout waiting for indexer pods to become ready"
    log_info "Checking pod status..."
    kubectl get pods -n "$WAZUH_NAMESPACE" -l app=wazuh-indexer
    log_warning "Continuing anyway - you may need to run: ./scripts/init-security.sh manually later"
fi

# Only run securityadmin if at least one indexer pod is ready
INDEXER_READY=$(kubectl get pods -n "$WAZUH_NAMESPACE" -l app=wazuh-indexer \
    -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)

if [[ $INDEXER_READY -gt 0 ]]; then
    # Run securityadmin to initialize the security plugin
    log_info "Running securityadmin to initialize security plugin..."

SECURITYADMIN_CMD='
cd /usr/share/wazuh-indexer/plugins/opensearch-security/tools && \
JAVA_HOME=/usr/share/wazuh-indexer/jdk bash securityadmin.sh \
  -cd /usr/share/wazuh-indexer/config/opensearch-security \
  -icl \
  -nhnv \
  -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
  -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
  -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
  -h localhost
'

    if kubectl exec -n "$WAZUH_NAMESPACE" wazuh-indexer-0 -- bash -c "$SECURITYADMIN_CMD" > /dev/null 2>&1; then
        log_success "Security configuration initialized successfully"
    else
        log_warning "Security initialization may have failed, but continuing..."
        log_info "You can manually initialize later with: ./scripts/init-security.sh"
    fi
else
    log_warning "No indexer pods are ready, skipping security initialization"
    log_info "Run manually after pods are ready: ./scripts/init-security.sh"
fi

# Wait for LoadBalancers to get external IPs
log_info "Waiting for LoadBalancers to get external IPs..."
ELAPSED=0
while [[ $ELAPSED -lt 300 ]]; do
    LB_COUNT=$(kubectl get svc -n "$WAZUH_NAMESPACE" -o json | jq '[.items[] | select(.spec.type=="LoadBalancer")] | length')
    LB_READY=$(kubectl get svc -n "$WAZUH_NAMESPACE" -o json | jq '[.items[] | select(.spec.type=="LoadBalancer") | select(.status.loadBalancer.ingress != null)] | length')

    if [[ $LB_READY -eq $LB_COUNT ]]; then
        log_success "All LoadBalancers have external IPs ($LB_READY/$LB_COUNT)"
        break
    fi

    echo -ne "  LoadBalancers: $LB_READY/$LB_COUNT ready... ${ELAPSED}s elapsed\r"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo ""

# Get LoadBalancer IPs
MANAGER_LB_IP=$(kubectl get svc -n "$WAZUH_NAMESPACE" wazuh-manager-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
WORKERS_LB_IP=$(kubectl get svc -n "$WAZUH_NAMESPACE" wazuh-workers-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [[ -n "$MANAGER_LB_IP" ]]; then
    log_info "Manager LoadBalancer IP: $MANAGER_LB_IP"
fi

if [[ -n "$WORKERS_LB_IP" ]]; then
    log_info "Workers LoadBalancer IP: $WORKERS_LB_IP"
fi

# Wait for DNS propagation (only when we manage DNS)
if [[ "$MANAGE_DNS" == "true" ]] && command -v dig &> /dev/null; then
    log_info "Waiting for DNS propagation (this may take 2-5 minutes)..."
    ELAPSED=0
    while [[ $ELAPSED -lt 300 ]]; do
        if dig +short "wazuh.$DOMAIN" | grep -q '^[0-9]'; then
            DASHBOARD_IP=$(dig +short "wazuh.$DOMAIN" | head -1)
            log_success "DNS record for wazuh.$DOMAIN: $DASHBOARD_IP"
            break
        fi
        echo -ne "  Waiting for DNS... ${ELAPSED}s elapsed\r"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    echo ""
fi

# Wait for the TLS certificate (only when cert-manager is managing TLS).
# We removed the explicit cert-manager Certificate resource for portability, so
# cert-manager's ingress-shim creates the cert and stores it in the
# "wazuh-dashboard-tls" secret. Waiting on that secret works regardless of how
# the certificate is provisioned.
if [[ "$MANAGE_TLS" == "true" ]]; then
    log_info "Waiting for TLS certificate (secret 'wazuh-dashboard-tls') to be issued..."
    ELAPSED=0
    while [[ $ELAPSED -lt 300 ]]; do
        if kubectl get secret -n "$WAZUH_NAMESPACE" wazuh-dashboard-tls &>/dev/null; then
            log_success "TLS certificate issued (secret 'wazuh-dashboard-tls' present)"
            break
        fi
        echo -ne "  Waiting for cert-manager to issue the certificate... ${ELAPSED}s elapsed\r"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    echo ""
    if [[ $ELAPSED -ge 300 ]]; then
        log_warning "TLS certificate not issued yet"
        log_info "Check: kubectl describe certificate,certificaterequest,order,challenge -n $WAZUH_NAMESPACE"
    fi
else
    log_info "Profile '$DEPLOY_PROFILE': skipping TLS wait"
    log_info "Provide your own TLS secret named 'wazuh-dashboard-tls' in namespace '$WAZUH_NAMESPACE'"
fi

# ============================================================================
# Step 12: Verify Deployment
# ============================================================================
log_step "Step 12: Verifying Deployment"

bash "$SCRIPT_DIR/kubernetes/scripts/verify-deployment.sh" "$WAZUH_NAMESPACE" || true

# ============================================================================
# Success! Display Access Information
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║   🎉 Wazuh Deployment Completed Successfully! 🎉                ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Wazuh Dashboard"
echo "  URL:      https://wazuh.$DOMAIN"
echo "  Username: admin"
echo "  Password: SecretPassword"
echo ""
log_warning "The deployment uses the upstream Wazuh DEFAULT credentials (admin / SecretPassword)."
log_warning "You MUST change the admin password immediately after first login."
echo ""
log_success "Agent Endpoints"
echo "  Events:       wazuh-manager.$DOMAIN:1514"
echo "  Registration: wazuh-registration.$DOMAIN:1515"
echo ""

# generate-credentials.sh writes strong random secrets here for your records and
# rotation. They are NOT yet wired into the running deployment (see README).
if [[ -f "$OVERLAY_DIR/.credentials" ]]; then
    log_success "Generated credentials (for your records / rotation)"
    echo "  Location: $OVERLAY_DIR/.credentials"
    echo "  View:     cat $OVERLAY_DIR/.credentials"
    echo ""
fi

log_info "Next Steps"
echo "  1. Log into the dashboard and change the admin password"
echo "  2. Deploy agents: ./agent-deployment/deploy-agent.sh <vm-hostname>"
echo "  3. View agents: kubectl exec -n $WAZUH_NAMESPACE wazuh-manager-master-0 -- /var/ossec/bin/agent_control -l"
echo ""

log_info "Useful Commands"
echo "  • Check pods:        kubectl get pods -n $WAZUH_NAMESPACE"
echo "  • Check services:    kubectl get svc -n $WAZUH_NAMESPACE"
echo "  • View logs:         kubectl logs -n $WAZUH_NAMESPACE <pod-name>"
echo "  • Verify deployment: ./kubernetes/scripts/verify-deployment.sh"
echo ""

log_info "Documentation"
echo "  • README:   cat README.md"
echo "  • Wazuh:    https://documentation.wazuh.com/"
echo "  • Support:  https://github.com/johnybradshaw/akamai-wazuh/issues"
echo ""

log_success "Deployment log saved to: $LOG_FILE"
log_success "Deployment completed at: $(date)"
echo ""
