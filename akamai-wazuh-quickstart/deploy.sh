#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh SIEM Quick-Start Deployment Script
# ============================================================================
# This script deploys a production-ready Wazuh SIEM platform on
# Akamai Cloud Computing (Linode Kubernetes Engine).
#
# What this script does:
#   1. Validates prerequisites and configuration
#   2. Clones Wazuh Kubernetes repository
#   3. Generates TLS certificates
#   4. Installs infrastructure prerequisites (nginx, cert-manager, ExternalDNS)
#   5. Generates secure random passwords
#   6. Deploys Wazuh using Kustomize
#   7. Waits for deployment readiness
#   8. Displays access information
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --dry-run           Validate configuration without deploying
#   --skip-prereqs      Skip prerequisite installation
#   --skip-certs        Skip certificate generation
#   --force             Force deployment even if validation fails
#   --help              Show this help message
#
# Requirements:
#   - kubectl configured for LKE cluster (3+ nodes, 4GB RAM each)
#   - helm 3.x
#   - docker (for password hash generation)
#   - jq (for JSON parsing)
#   - config.env file with DOMAIN, LINODE_API_TOKEN, LETSENCRYPT_EMAIL
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
  --skip-prereqs      Skip prerequisite installation (nginx, cert-manager, ExternalDNS)
  --skip-certs        Skip certificate generation
  --force             Force deployment even if validation warnings occur
  --help              Show this help message

Requirements:
  - kubectl configured for an LKE cluster (3+ nodes, 4GB RAM each)
  - helm 3.x installed
  - docker installed (for password hash generation)
  - jq installed (for JSON parsing)
  - config.env file with required variables

Configuration (config.env):
  DOMAIN                - Your root domain (DNS must be on Linode)
  LINODE_API_TOKEN      - Linode API token with Domains Read/Write
  LETSENCRYPT_EMAIL     - Email for Let's Encrypt certificates

Examples:
  # Normal deployment
  ./deploy.sh

  # Validate configuration without deploying
  ./deploy.sh --dry-run

  # Deploy without installing prerequisites (already installed)
  ./deploy.sh --skip-prereqs

For more information: https://github.com/akamai/wazuh-quickstart
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

# Validate required variables
REQUIRED_VARS=("DOMAIN" "LINODE_API_TOKEN" "LETSENCRYPT_EMAIL")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    log_error "Missing required configuration variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    log_info "Please edit config.env and set all required variables"
    exit 1
fi

log_success "Configuration loaded successfully"
log_info "Domain: $DOMAIN"
log_info "Namespace: ${WAZUH_NAMESPACE:-wazuh}"
log_info "Wazuh Version: ${WAZUH_VERSION:-v4.9.2}"

# Set defaults for optional variables
WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
WAZUH_VERSION="${WAZUH_VERSION:-v4.9.2}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-600}"
SKIP_PREREQUISITES="${SKIP_PREREQUISITES:-false}"

# Export for subprocesses
export DOMAIN LINODE_API_TOKEN LETSENCRYPT_EMAIL WAZUH_NAMESPACE

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

# Check helm
log_info "Checking helm..."
if ! command -v helm &> /dev/null; then
    log_error "helm is not installed"
    PREREQ_FAILED=true
else
    HELM_VERSION=$(helm version --short)
    log_success "helm installed: $HELM_VERSION"
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
# Step 3: Verify Linode DNS Domain
# ============================================================================
log_step "Step 3: Verifying Linode DNS Domain"

log_info "Checking if domain '$DOMAIN' exists in Linode DNS..."

DOMAIN_CHECK=$(curl -s -H "Authorization: Bearer $LINODE_API_TOKEN" \
    "https://api.linode.com/v4/domains" | jq -r ".data[] | select(.domain==\"$DOMAIN\") | .domain")

if [[ "$DOMAIN_CHECK" == "$DOMAIN" ]]; then
    log_success "Domain '$DOMAIN' found in Linode DNS"
else
    log_error "Domain '$DOMAIN' not found in Linode DNS"
    log_info "Please ensure your domain is hosted on Linode/Akamai DNS"
    log_info "Visit: https://cloud.linode.com/domains"
    exit 1
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
# Step 4: Clone Wazuh Kubernetes Repository
# ============================================================================
log_step "Step 4: Cloning Wazuh Kubernetes Repository"

WAZUH_K8S_DIR="$SCRIPT_DIR/kubernetes/wazuh-kubernetes"

if [[ -d "$WAZUH_K8S_DIR" ]]; then
    log_warning "Wazuh Kubernetes repository already exists"
    log_info "Pulling latest changes..."
    cd "$WAZUH_K8S_DIR"
    git pull || log_warning "Failed to pull latest changes (using existing)"
    cd "$SCRIPT_DIR"
else
    log_info "Cloning Wazuh Kubernetes repository..."
    git clone https://github.com/wazuh/wazuh-kubernetes.git \
        -b "$WAZUH_VERSION" \
        --depth=1 \
        "$WAZUH_K8S_DIR"
    log_success "Repository cloned successfully"
fi

# ============================================================================
# Step 5: Generate TLS Certificates
# ============================================================================
if [[ "$SKIP_CERTS" == "false" ]]; then
    log_step "Step 5: Generating TLS Certificates"

    # Generate indexer certificates
    log_info "Generating Wazuh Indexer certificates..."
    cd "$WAZUH_K8S_DIR/wazuh/certs/indexer_cluster"
    if [[ ! -f "root-ca.pem" ]]; then
        bash generate_certs.sh
        log_success "Indexer certificates generated"
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

OVERLAY_DIR="$SCRIPT_DIR/kubernetes/overlays/production"
bash "$SCRIPT_DIR/kubernetes/scripts/generate-credentials.sh" "$OVERLAY_DIR"

log_success "Credentials generated and saved to $OVERLAY_DIR/.credentials"

# ============================================================================
# Step 8: Prepare Kustomize Overlay
# ============================================================================
log_step "Step 8: Preparing Kustomize Overlay"

log_info "Substituting domain placeholders in manifests..."

# Substitute ${DOMAIN} in YAML files
for file in "$OVERLAY_DIR"/*.yaml; do
    if [[ -f "$file" ]]; then
        sed -i.bak "s/\${DOMAIN}/$DOMAIN/g" "$file"
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
kubectl apply -k "$OVERLAY_DIR"

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
        log_success "All pods are running ($RUNNING_PODS/$TOTAL_PODS)"
        break
    fi

    echo -ne "  Pods: $RUNNING_PODS/$TOTAL_PODS running... ${ELAPSED}s elapsed\r"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo ""

if [[ $ELAPSED -ge $DEPLOYMENT_TIMEOUT ]]; then
    log_error "Timeout waiting for pods to start"
    log_info "Check pod status: kubectl get pods -n $WAZUH_NAMESPACE"
    exit 1
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

# Wait for DNS propagation
if command -v dig &> /dev/null; then
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

# Wait for TLS certificate
log_info "Waiting for TLS certificate to be issued..."
ELAPSED=0
while [[ $ELAPSED -lt 300 ]]; do
    CERT_READY=$(kubectl get certificate -n "$WAZUH_NAMESPACE" wazuh-dashboard-cert -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [[ "$CERT_READY" == "True" ]]; then
        log_success "TLS certificate issued successfully"
        break
    fi

    echo -ne "  Certificate status: $CERT_READY... ${ELAPSED}s elapsed\r"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo ""

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

# Get admin password
ADMIN_PASSWORD=$(grep "WAZUH_DASHBOARD_PASSWORD=" "$OVERLAY_DIR/.credentials" | cut -d'=' -f2 | tr -d '"')
AGENT_PASSWORD=$(grep "WAZUH_AGENT_PASSWORD=" "$OVERLAY_DIR/.credentials" | cut -d'=' -f2 | tr -d '"')

log_success "Wazuh Dashboard"
echo "  URL:      https://wazuh.$DOMAIN"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""

log_success "Agent Endpoints"
echo "  Events:       wazuh-manager.$DOMAIN:1514"
echo "  Registration: wazuh-registration.$DOMAIN:1515"
echo "  Password:     $AGENT_PASSWORD"
echo ""

log_success "Credentials File"
echo "  Location: $OVERLAY_DIR/.credentials"
echo "  View:     cat $OVERLAY_DIR/.credentials"
echo ""

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
echo "  • Support:  https://github.com/akamai/wazuh-quickstart/issues"
echo ""

log_success "Deployment log saved to: $LOG_FILE"
log_success "Deployment completed at: $(date)"
echo ""
