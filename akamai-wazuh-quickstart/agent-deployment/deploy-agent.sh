#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh Quick-Start - Agent Deployment Script
# ============================================================================
# This script deploys a Wazuh agent to a remote Ubuntu VM.
#
# What this script does:
#   1. Fetches configuration from Kubernetes cluster
#   2. Retrieves agent registration password
#   3. Connects to remote VM via SSH
#   4. Installs Wazuh agent
#   5. Configures agent with manager endpoints
#   6. Starts and verifies agent
#
# Usage:
#   ./deploy-agent.sh <vm-hostname> [agent-name] [agent-group]
#
# Arguments:
#   vm-hostname   - SSH hostname or IP of the VM
#   agent-name    - Optional: Custom agent name (default: hostname)
#   agent-group   - Optional: Agent group (default: default)
#
# Examples:
#   ./deploy-agent.sh web-server-01
#   ./deploy-agent.sh 192.168.1.10 web-01 web-servers
#   ./deploy-agent.sh user@hostname db-server database-servers
#
# Requirements:
#   - SSH access to target VM (password or key-based)
#   - kubectl configured for Wazuh cluster
#   - Target VM running Ubuntu 18.04+ or Debian 9+
#   - Root/sudo access on target VM
#
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# ============================================================================
# Parse Arguments
# ============================================================================
if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 <vm-hostname> [agent-name] [agent-group]"
    echo ""
    echo "Examples:"
    echo "  $0 web-server-01"
    echo "  $0 192.168.1.10 web-01 web-servers"
    echo "  $0 user@hostname db-server database-servers"
    exit 1
fi

VM_HOST="$1"
AGENT_NAME="${2:-$(echo "$VM_HOST" | sed 's/.*@//' | sed 's/:.*//')}"
AGENT_GROUP="${3:-default}"

# Configuration
WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Wazuh Agent Deployment                                   ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Target VM:     $VM_HOST"
log_info "Agent Name:    $AGENT_NAME"
log_info "Agent Group:   $AGENT_GROUP"
log_info "Namespace:     $WAZUH_NAMESPACE"
echo ""

# ============================================================================
# Step 1: Fetch Configuration from Kubernetes
# ============================================================================
log_info "Fetching configuration from Kubernetes cluster..."

# Check kubectl access
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    log_info "Please configure kubectl to access your Wazuh cluster"
    exit 1
fi

# Get domain from ingress
DOMAIN=$(kubectl get ingress -n "$WAZUH_NAMESPACE" wazuh-dashboard-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null | sed 's/^wazuh\.//' || echo "")

if [[ -z "$DOMAIN" ]]; then
    log_error "Could not determine domain from ingress"
    log_info "Please ensure Wazuh is deployed and ingress is configured"
    exit 1
fi

log_success "Domain: $DOMAIN"

# Set manager endpoints
WAZUH_MANAGER="wazuh-manager.$DOMAIN"
WAZUH_REGISTRATION_SERVER="wazuh-registration.$DOMAIN"

log_info "Manager:       $WAZUH_MANAGER:1514"
log_info "Registration:  $WAZUH_REGISTRATION_SERVER:1515"

# ============================================================================
# Step 2: Retrieve Agent Password
# ============================================================================
log_info "Retrieving agent registration password..."

# Try to get from Kubernetes secret
AGENT_PASSWORD=$(kubectl get secret -n "$WAZUH_NAMESPACE" wazuh-authd-pass -o jsonpath='{.data.authd\.pass}' 2>/dev/null | base64 -d || echo "")

if [[ -z "$AGENT_PASSWORD" ]]; then
    # Try to get from credentials file
    CREDENTIALS_FILE="$SCRIPT_DIR/../kubernetes/overlays/production/.credentials"
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        AGENT_PASSWORD=$(grep "WAZUH_AGENT_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2 | tr -d '"')
    fi
fi

if [[ -z "$AGENT_PASSWORD" ]]; then
    log_error "Could not retrieve agent registration password"
    log_info "Please check Kubernetes secrets or credentials file"
    exit 1
fi

log_success "Agent password retrieved"

# ============================================================================
# Step 3: Check SSH Connectivity
# ============================================================================
log_info "Testing SSH connectivity to $VM_HOST..."

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$VM_HOST" "echo 2>&1" &>/dev/null; then
    log_warning "Cannot connect via SSH with keys"
    log_info "You may be prompted for password"
fi

# Test basic connectivity
if ! ssh -o ConnectTimeout=10 "$VM_HOST" "echo connected" &>/dev/null; then
    log_error "Cannot connect to $VM_HOST via SSH"
    log_info "Please check:"
    echo "  • SSH is running on the target VM"
    echo "  • Firewall allows SSH connections"
    echo "  • SSH keys are configured (or password is available)"
    exit 1
fi

log_success "SSH connectivity confirmed"

# ============================================================================
# Step 4: Deploy Agent to VM
# ============================================================================
log_info "Deploying Wazuh agent to $VM_HOST..."

# Create deployment script
DEPLOY_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Parameters passed from parent script
WAZUH_MANAGER="__WAZUH_MANAGER__"
WAZUH_REGISTRATION_SERVER="__WAZUH_REGISTRATION_SERVER__"
AGENT_PASSWORD="__AGENT_PASSWORD__"
AGENT_NAME="__AGENT_NAME__"
AGENT_GROUP="__AGENT_GROUP__"

log_info "Starting Wazuh agent installation on $(hostname)..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    log_error "Cannot detect OS version"
    exit 1
fi

log_info "Detected OS: $OS $VERSION"

# Remove existing Wazuh agent if present
if systemctl is-active --quiet wazuh-agent 2>/dev/null; then
    log_warning "Existing Wazuh agent detected, removing..."
    systemctl stop wazuh-agent || true
    systemctl disable wazuh-agent || true
fi

if dpkg -l | grep -q wazuh-agent; then
    apt-get remove --purge -y wazuh-agent || true
    rm -rf /var/ossec
fi

# Install dependencies
log_info "Installing dependencies..."
apt-get update -qq
apt-get install -y curl apt-transport-https lsb-release gnupg

# Add Wazuh repository
log_info "Adding Wazuh repository..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg

echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | \
    tee /etc/apt/sources.list.d/wazuh.list

# Install Wazuh agent
log_info "Installing Wazuh agent..."
apt-get update -qq

# Install with environment variables
WAZUH_MANAGER="$WAZUH_MANAGER" \
WAZUH_REGISTRATION_SERVER="$WAZUH_REGISTRATION_SERVER" \
WAZUH_REGISTRATION_PASSWORD="$AGENT_PASSWORD" \
WAZUH_AGENT_NAME="$AGENT_NAME" \
WAZUH_AGENT_GROUP="$AGENT_GROUP" \
apt-get install -y wazuh-agent

# Verify installation
if [[ ! -f /var/ossec/bin/wazuh-control ]]; then
    log_error "Wazuh agent installation failed"
    exit 1
fi

log_success "Wazuh agent installed"

# Configure ossec.conf if needed
log_info "Verifying agent configuration..."

# Ensure manager address is set
if ! grep -q "<address>$WAZUH_MANAGER</address>" /var/ossec/etc/ossec.conf; then
    log_warning "Updating manager address in ossec.conf..."
    sed -i "s|<address>.*</address>|<address>$WAZUH_MANAGER</address>|g" /var/ossec/etc/ossec.conf
fi

# Start and enable agent
log_info "Starting Wazuh agent..."
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

# Wait for agent to start
sleep 5

# Verify agent is running
if systemctl is-active --quiet wazuh-agent; then
    log_success "Wazuh agent is running"
else
    log_error "Wazuh agent failed to start"
    systemctl status wazuh-agent
    exit 1
fi

# Check agent status
log_info "Agent status:"
/var/ossec/bin/wazuh-control status

# Display agent info
if [[ -f /var/ossec/etc/client.keys ]]; then
    log_success "Agent registered successfully"
    log_info "Agent ID: $(grep -v '^$' /var/ossec/etc/client.keys | cut -d' ' -f1)"
else
    log_warning "Agent not registered yet (may take a few moments)"
fi

log_success "Wazuh agent deployment completed!"
EOFSCRIPT
)

# Substitute variables in script
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//__WAZUH_MANAGER__/$WAZUH_MANAGER}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//__WAZUH_REGISTRATION_SERVER__/$WAZUH_REGISTRATION_SERVER}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//__AGENT_PASSWORD__/$AGENT_PASSWORD}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//__AGENT_NAME__/$AGENT_NAME}"
DEPLOY_SCRIPT="${DEPLOY_SCRIPT//__AGENT_GROUP__/$AGENT_GROUP}"

# Execute deployment script on remote VM
log_info "Executing deployment on remote VM..."
echo "$DEPLOY_SCRIPT" | ssh "$VM_HOST" "sudo bash -s"

if [[ $? -eq 0 ]]; then
    log_success "Agent deployed successfully to $VM_HOST"
else
    log_error "Agent deployment failed"
    exit 1
fi

# ============================================================================
# Step 5: Verify Agent Registration
# ============================================================================
log_info "Verifying agent registration..."
sleep 5

# Get list of agents from manager
MASTER_POD=$(kubectl get pods -n "$WAZUH_NAMESPACE" -l app=wazuh-manager,node-type=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$MASTER_POD" ]]; then
    log_info "Checking agent list on manager..."
    kubectl exec -n "$WAZUH_NAMESPACE" "$MASTER_POD" -- /var/ossec/bin/agent_control -l | grep -i "$AGENT_NAME" || true
fi

# ============================================================================
# Success
# ============================================================================
echo ""
log_success "Agent deployment completed!"
echo ""
log_info "Agent Information:"
echo "  • Name:        $AGENT_NAME"
echo "  • Group:       $AGENT_GROUP"
echo "  • Manager:     $WAZUH_MANAGER:1514"
echo "  • VM:          $VM_HOST"
echo ""
log_info "Verify agent status:"
echo "  • On VM:       ssh $VM_HOST 'sudo systemctl status wazuh-agent'"
echo "  • On manager:  kubectl exec -n $WAZUH_NAMESPACE $MASTER_POD -- /var/ossec/bin/agent_control -l"
echo ""
log_info "View agent logs:"
echo "  • On VM:       ssh $VM_HOST 'sudo tail -f /var/ossec/logs/ossec.log'"
echo ""
