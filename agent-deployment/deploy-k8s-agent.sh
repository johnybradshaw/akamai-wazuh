#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh Quick-Start - Kubernetes Agent Deployment Script
# ============================================================================
# This script deploys Wazuh agents as a DaemonSet to Kubernetes clusters
# to monitor cluster nodes and workloads.
#
# What this script does:
#   1. Fetches Wazuh manager configuration from the cluster
#   2. Creates namespace for agents
#   3. Creates necessary secrets and ConfigMaps
#   4. Deploys agents as a DaemonSet on all nodes
#   5. Verifies agent registration
#
# Usage:
#   ./deploy-k8s-agent.sh [OPTIONS]
#
# Options:
#   --namespace NAME       Namespace for agent DaemonSet (default: wazuh-agents)
#   --manager-ns NAME      Namespace where Wazuh manager is deployed (default: wazuh)
#   --agent-group NAME     Agent group name (default: kubernetes)
#   --privileged           Run agents with privileged access (default: false)
#   --help                 Show this help message
#
# Examples:
#   # Deploy with defaults
#   ./deploy-k8s-agent.sh
#
#   # Deploy to custom namespace
#   ./deploy-k8s-agent.sh --namespace monitoring-agents
#
#   # Deploy with privileged access for deeper monitoring
#   ./deploy-k8s-agent.sh --privileged
#
# Requirements:
#   - kubectl configured for target cluster
#   - Wazuh manager already deployed and accessible
#
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration and Global Variables
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default options
AGENT_NAMESPACE="wazuh-agents"
MANAGER_NAMESPACE="wazuh"
AGENT_GROUP="kubernetes"
PRIVILEGED="false"

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
Kubernetes Wazuh Agent Deployment Script

Usage: $0 [OPTIONS]

Options:
  --namespace NAME       Namespace for agent DaemonSet (default: wazuh-agents)
  --manager-ns NAME      Namespace where Wazuh manager is deployed (default: wazuh)
  --agent-group NAME     Agent group name (default: kubernetes)
  --privileged           Run agents with privileged access for deeper monitoring
  --help                 Show this help message

Examples:
  # Deploy with defaults
  $0

  # Deploy to custom namespace
  $0 --namespace monitoring-agents

  # Deploy with privileged access
  $0 --privileged

Requirements:
  - kubectl configured for target cluster
  - Wazuh manager already deployed
EOF
    exit 0
}

# ============================================================================
# Parse Command Line Arguments
# ============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            AGENT_NAMESPACE="$2"
            shift 2
            ;;
        --manager-ns)
            MANAGER_NAMESPACE="$2"
            shift 2
            ;;
        --agent-group)
            AGENT_GROUP="$2"
            shift 2
            ;;
        --privileged)
            PRIVILEGED="true"
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
║   Wazuh Kubernetes Agent Deployment                            ║
║   DaemonSet-based Monitoring                                    ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
echo ""
log_info "Deployment started at: $(date)"
log_info "Agent Namespace:   $AGENT_NAMESPACE"
log_info "Manager Namespace: $MANAGER_NAMESPACE"
log_info "Agent Group:       $AGENT_GROUP"
log_info "Privileged Mode:   $PRIVILEGED"
echo ""

# ============================================================================
# Step 1: Validate Prerequisites
# ============================================================================
log_step "Step 1: Validating Prerequisites"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    exit 1
fi
log_success "kubectl found"

# Check cluster access
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    log_info "Please configure kubectl to access your cluster"
    exit 1
fi
CLUSTER_VERSION=$(kubectl version -o json | jq -r '.serverVersion.gitVersion')
log_success "Connected to cluster: $CLUSTER_VERSION"

# Check if manager namespace exists
if ! kubectl get namespace "$MANAGER_NAMESPACE" &> /dev/null; then
    log_error "Wazuh manager namespace '$MANAGER_NAMESPACE' not found"
    log_info "Please deploy Wazuh manager first or specify correct namespace with --manager-ns"
    exit 1
fi
log_success "Manager namespace exists"

# Check if manager is running
MANAGER_POD=$(kubectl get pods -n "$MANAGER_NAMESPACE" -l app=wazuh-manager,node-type=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$MANAGER_POD" ]]; then
    log_error "Wazuh manager pod not found in namespace '$MANAGER_NAMESPACE'"
    log_info "Please ensure Wazuh manager is deployed and running"
    exit 1
fi
log_success "Manager pod found: $MANAGER_POD"

# ============================================================================
# Step 2: Fetch Configuration
# ============================================================================
log_step "Step 2: Fetching Wazuh Configuration"

# Get domain from ingress
DOMAIN=$(kubectl get ingress -n "$MANAGER_NAMESPACE" wazuh-dashboard-ingress -o jsonpath='{.spec.rules[0].host}' 2>/dev/null | sed 's/^wazuh\.//' || echo "")

if [[ -z "$DOMAIN" ]]; then
    log_warning "Could not determine domain from ingress"
    log_info "Will use internal cluster DNS"
    WAZUH_MANAGER="wazuh.$MANAGER_NAMESPACE.svc.cluster.local"
    WAZUH_REGISTRATION_SERVER="wazuh.$MANAGER_NAMESPACE.svc.cluster.local"
else
    log_success "Domain: $DOMAIN"
    WAZUH_MANAGER="wazuh-manager.$DOMAIN"
    WAZUH_REGISTRATION_SERVER="wazuh-registration.$DOMAIN"
fi

log_info "Manager endpoint:       $WAZUH_MANAGER"
log_info "Registration endpoint:  $WAZUH_REGISTRATION_SERVER"

# Get agent password
AGENT_PASSWORD=$(kubectl get secret -n "$MANAGER_NAMESPACE" wazuh-authd-pass -o jsonpath='{.data.authd\.pass}' 2>/dev/null | base64 -d || echo "")

if [[ -z "$AGENT_PASSWORD" ]]; then
    log_error "Could not retrieve agent registration password"
    log_info "Please check if wazuh-authd-pass secret exists in namespace '$MANAGER_NAMESPACE'"
    exit 1
fi
log_success "Agent password retrieved"

# ============================================================================
# Step 3: Create Namespace
# ============================================================================
log_step "Step 3: Creating Agent Namespace"

if kubectl get namespace "$AGENT_NAMESPACE" &> /dev/null; then
    log_warning "Namespace '$AGENT_NAMESPACE' already exists"
else
    kubectl create namespace "$AGENT_NAMESPACE"
    log_success "Namespace '$AGENT_NAMESPACE' created"
fi

# ============================================================================
# Step 4: Create Agent Configuration
# ============================================================================
log_step "Step 4: Creating Agent Configuration"

# Create secret for agent password
log_info "Creating agent password secret..."
kubectl create secret generic wazuh-agent-password \
    --from-literal=password="$AGENT_PASSWORD" \
    --namespace="$AGENT_NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
log_success "Agent password secret created"

# Create ConfigMap for agent configuration
log_info "Creating agent configuration ConfigMap..."
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: wazuh-agent-config
  namespace: $AGENT_NAMESPACE
data:
  WAZUH_MANAGER: "$WAZUH_MANAGER"
  WAZUH_REGISTRATION_SERVER: "$WAZUH_REGISTRATION_SERVER"
  WAZUH_AGENT_GROUP: "$AGENT_GROUP"
YAML
log_success "Agent configuration ConfigMap created"

# ============================================================================
# Step 5: Deploy Agent DaemonSet
# ============================================================================
log_step "Step 5: Deploying Agent DaemonSet"

log_info "Creating DaemonSet manifest..."

# Determine security context
if [[ "$PRIVILEGED" == "true" ]]; then
    SECURITY_CONTEXT='
        securityContext:
          privileged: true
          capabilities:
            add:
              - SYS_ADMIN
              - SYS_PTRACE
              - NET_ADMIN'
    log_warning "Running agents in privileged mode"
else
    SECURITY_CONTEXT='
        securityContext:
          capabilities:
            add:
              - SYS_PTRACE'
fi

# Create DaemonSet
cat <<YAML | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: wazuh-agent
  namespace: $AGENT_NAMESPACE
  labels:
    app: wazuh-agent
    component: security-monitoring
spec:
  selector:
    matchLabels:
      app: wazuh-agent
  template:
    metadata:
      labels:
        app: wazuh-agent
    spec:
      hostNetwork: true
      hostPID: true
      hostIPC: true
      tolerations:
      # Run on all nodes including control plane
      - operator: Exists
      containers:
      - name: wazuh-agent
        image: wazuh/wazuh-agent:4.14.1
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
$SECURITY_CONTEXT
        env:
        - name: WAZUH_MANAGER
          valueFrom:
            configMapKeyRef:
              name: wazuh-agent-config
              key: WAZUH_MANAGER
        - name: WAZUH_REGISTRATION_SERVER
          valueFrom:
            configMapKeyRef:
              name: wazuh-agent-config
              key: WAZUH_REGISTRATION_SERVER
        - name: WAZUH_REGISTRATION_PASSWORD
          valueFrom:
            secretKeyRef:
              name: wazuh-agent-password
              key: password
        - name: WAZUH_AGENT_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: WAZUH_AGENT_GROUP
          valueFrom:
            configMapKeyRef:
              name: wazuh-agent-config
              key: WAZUH_AGENT_GROUP
        volumeMounts:
        - name: rootfs
          mountPath: /host
          readOnly: true
        - name: dockersock
          mountPath: /var/run/docker.sock
          readOnly: true
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: proc
          mountPath: /host/proc
          readOnly: true
      volumes:
      - name: rootfs
        hostPath:
          path: /
      - name: dockersock
        hostPath:
          path: /var/run/docker.sock
      - name: sys
        hostPath:
          path: /sys
      - name: proc
        hostPath:
          path: /proc
YAML

log_success "DaemonSet created"

# ============================================================================
# Step 6: Wait for Agent Pods
# ============================================================================
log_step "Step 6: Waiting for Agent Pods"

log_info "Waiting for pods to start (timeout: 120s)..."
kubectl rollout status daemonset/wazuh-agent -n "$AGENT_NAMESPACE" --timeout=120s

# Get pod status
DESIRED=$(kubectl get daemonset wazuh-agent -n "$AGENT_NAMESPACE" -o jsonpath='{.status.desiredNumberScheduled}')
READY=$(kubectl get daemonset wazuh-agent -n "$AGENT_NAMESPACE" -o jsonpath='{.status.numberReady}')

log_success "Agent pods ready: $READY/$DESIRED"

# Show pod distribution
echo ""
log_info "Agent pods by node:"
kubectl get pods -n "$AGENT_NAMESPACE" -l app=wazuh-agent -o wide | tail -n +2 | awk '{print "  • " $7 ": " $1 " (" $3 ")"}'

# ============================================================================
# Step 7: Verify Agent Registration
# ============================================================================
log_step "Step 7: Verifying Agent Registration"

log_info "Waiting for agents to register (this may take 30-60 seconds)..."
sleep 30

log_info "Checking registered agents on manager..."
echo ""
kubectl exec -n "$MANAGER_NAMESPACE" "$MANAGER_POD" -- \
    /var/ossec/bin/agent_control -l | grep -E "(ID:|Name:|IP:)" || true

# Count agents
AGENT_COUNT=$(kubectl exec -n "$MANAGER_NAMESPACE" "$MANAGER_POD" -- \
    /var/ossec/bin/agent_control -l 2>/dev/null | grep -c "ID:" || echo "0")

log_info "Total registered agents: $AGENT_COUNT"

# ============================================================================
# Success!
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║   🎉 Kubernetes Agent Deployment Completed! 🎉                  ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

log_success "Agent DaemonSet Information"
echo "  Namespace:  $AGENT_NAMESPACE"
echo "  Pods:       $READY/$DESIRED ready"
echo "  Group:      $AGENT_GROUP"
echo ""

log_info "Useful Commands"
echo "  • View agent pods:      kubectl get pods -n $AGENT_NAMESPACE -l app=wazuh-agent -o wide"
echo "  • View agent logs:      kubectl logs -n $AGENT_NAMESPACE -l app=wazuh-agent --tail=50"
echo "  • Check agent status:   kubectl exec -n $MANAGER_NAMESPACE $MANAGER_POD -- /var/ossec/bin/agent_control -l"
echo "  • Restart agents:       kubectl rollout restart daemonset/wazuh-agent -n $AGENT_NAMESPACE"
echo "  • Delete agents:        kubectl delete daemonset wazuh-agent -n $AGENT_NAMESPACE"
echo ""

log_info "Agent Configuration"
echo "  • Manager:              $WAZUH_MANAGER"
echo "  • Registration:         $WAZUH_REGISTRATION_SERVER"
echo "  • Privileged Mode:      $PRIVILEGED"
echo ""

log_success "Deployment completed at: $(date)"
echo ""
