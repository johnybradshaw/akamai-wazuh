#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh Quick-Start - Bulk Agent Deployment Script
# ============================================================================
# This script deploys Wazuh agents to multiple VMs from a CSV file.
#
# CSV Format:
#   hostname,agent_name,agent_group
#
# Example CSV:
#   web-server-01.example.com,web-01,web-servers
#   192.168.1.10,web-02,web-servers
#   user@db-server.example.com,db-01,database-servers
#
# Usage:
#   ./deploy-agents-bulk.sh <vm-list-file> [--parallel N]
#
# Arguments:
#   vm-list-file  - Path to CSV file with VM list
#   --parallel N  - Optional: Deploy to N VMs in parallel (default: 1)
#
# Examples:
#   ./deploy-agents-bulk.sh vm-list.txt
#   ./deploy-agents-bulk.sh vm-list.txt --parallel 5
#
# Requirements:
#   - deploy-agent.sh script in same directory
#   - SSH access to all target VMs
#   - kubectl configured for Wazuh cluster
#
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    log_error "Usage: $0 <vm-list-file> [--parallel N]"
    echo ""
    echo "CSV Format: hostname,agent_name,agent_group"
    echo ""
    echo "Example:"
    echo "  web-server-01.example.com,web-01,web-servers"
    echo "  192.168.1.10,web-02,web-servers"
    echo "  user@db-server,db-01,database-servers"
    echo ""
    exit 1
fi

VM_LIST_FILE="$1"
PARALLEL_JOBS=1

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-agent.sh"
LOG_DIR="$SCRIPT_DIR/logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SUMMARY_LOG="$LOG_DIR/bulk_deployment_${TIMESTAMP}.log"

# Create log directory
mkdir -p "$LOG_DIR"

# ============================================================================
# Banner
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Wazuh Bulk Agent Deployment                              ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
log_info "VM List File:    $VM_LIST_FILE"
log_info "Parallel Jobs:   $PARALLEL_JOBS"
log_info "Summary Log:     $SUMMARY_LOG"
echo ""

# ============================================================================
# Validate Prerequisites
# ============================================================================
log_info "Validating prerequisites..."

# Check if deploy-agent.sh exists
if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    log_error "deploy-agent.sh not found at: $DEPLOY_SCRIPT"
    exit 1
fi

# Make deploy-agent.sh executable
chmod +x "$DEPLOY_SCRIPT"

# Check if VM list file exists
if [[ ! -f "$VM_LIST_FILE" ]]; then
    log_error "VM list file not found: $VM_LIST_FILE"
    exit 1
fi

# Check if file is not empty
if [[ ! -s "$VM_LIST_FILE" ]]; then
    log_error "VM list file is empty: $VM_LIST_FILE"
    exit 1
fi

# Check for kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed"
    exit 1
fi

# Check kubectl cluster access
if ! kubectl cluster-info &> /dev/null; then
    log_error "kubectl cannot access Kubernetes cluster"
    exit 1
fi

log_success "Prerequisites validated"

# ============================================================================
# Parse VM List
# ============================================================================
log_info "Parsing VM list..."

# Array to store VM entries
declare -a VMS
VM_COUNT=0

while IFS=',' read -r hostname agent_name agent_group || [[ -n "$hostname" ]]; do
    # Skip empty lines and comments
    [[ -z "$hostname" || "$hostname" =~ ^#.* ]] && continue

    # Trim whitespace
    hostname=$(echo "$hostname" | xargs)
    agent_name=$(echo "$agent_name" | xargs)
    agent_group=$(echo "$agent_group" | xargs)

    # Set defaults if not provided
    [[ -z "$agent_name" ]] && agent_name="$hostname"
    [[ -z "$agent_group" ]] && agent_group="default"

    VMS+=("$hostname|$agent_name|$agent_group")
    VM_COUNT=$((VM_COUNT + 1))
done < "$VM_LIST_FILE"

if [[ $VM_COUNT -eq 0 ]]; then
    log_error "No valid VM entries found in $VM_LIST_FILE"
    exit 1
fi

log_success "Found $VM_COUNT VM(s) to deploy"
echo ""

# ============================================================================
# Deployment Function
# ============================================================================
deploy_to_vm() {
    local vm_entry="$1"
    local index="$2"

    IFS='|' read -r hostname agent_name agent_group <<< "$vm_entry"

    local vm_log="$LOG_DIR/${agent_name}_${TIMESTAMP}.log"

    echo "[$index/$VM_COUNT] Deploying to: $hostname (agent: $agent_name, group: $agent_group)"

    # Run deployment script
    if "$DEPLOY_SCRIPT" "$hostname" "$agent_name" "$agent_group" > "$vm_log" 2>&1; then
        echo "[$index/$VM_COUNT] ✓ SUCCESS: $hostname" | tee -a "$SUMMARY_LOG"
        return 0
    else
        echo "[$index/$VM_COUNT] ✗ FAILED: $hostname (see $vm_log)" | tee -a "$SUMMARY_LOG"
        return 1
    fi
}

export -f deploy_to_vm
export DEPLOY_SCRIPT LOG_DIR TIMESTAMP SUMMARY_LOG VM_COUNT

# ============================================================================
# Deploy Agents
# ============================================================================
log_info "Starting deployment to $VM_COUNT VM(s)..."
echo ""

# Initialize summary log
echo "Wazuh Bulk Agent Deployment Summary" > "$SUMMARY_LOG"
echo "Started: $(date)" >> "$SUMMARY_LOG"
echo "VM Count: $VM_COUNT" >> "$SUMMARY_LOG"
echo "Parallel Jobs: $PARALLEL_JOBS" >> "$SUMMARY_LOG"
echo "======================================" >> "$SUMMARY_LOG"
echo "" >> "$SUMMARY_LOG"

# Counters
SUCCESSFUL=0
FAILED=0
INDEX=0

# Deploy based on parallel jobs setting
if [[ $PARALLEL_JOBS -eq 1 ]]; then
    # Sequential deployment
    for vm_entry in "${VMS[@]}"; do
        INDEX=$((INDEX + 1))

        if deploy_to_vm "$vm_entry" "$INDEX"; then
            SUCCESSFUL=$((SUCCESSFUL + 1))
        else
            FAILED=$((FAILED + 1))
        fi

        echo ""
    done
else
    # Parallel deployment using background jobs
    log_info "Deploying in parallel (max $PARALLEL_JOBS jobs)..."

    for vm_entry in "${VMS[@]}"; do
        INDEX=$((INDEX + 1))

        # Wait if we've reached max parallel jobs
        while [[ $(jobs -r | wc -l) -ge $PARALLEL_JOBS ]]; do
            sleep 1
        done

        # Deploy in background
        {
            if deploy_to_vm "$vm_entry" "$INDEX"; then
                echo "SUCCESS" > "$LOG_DIR/.result_${INDEX}"
            else
                echo "FAILED" > "$LOG_DIR/.result_${INDEX}"
            fi
        } &
    done

    # Wait for all background jobs to complete
    log_info "Waiting for all deployments to complete..."
    wait

    # Count results
    for i in $(seq 1 $VM_COUNT); do
        if [[ -f "$LOG_DIR/.result_${i}" ]]; then
            result=$(cat "$LOG_DIR/.result_${i}")
            if [[ "$result" == "SUCCESS" ]]; then
                SUCCESSFUL=$((SUCCESSFUL + 1))
            else
                FAILED=$((FAILED + 1))
            fi
            rm -f "$LOG_DIR/.result_${i}"
        fi
    done
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║         Bulk Deployment Summary                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

echo "Completed: $(date)" >> "$SUMMARY_LOG"
echo "Successful: $SUCCESSFUL" >> "$SUMMARY_LOG"
echo "Failed: $FAILED" >> "$SUMMARY_LOG"
echo "" >> "$SUMMARY_LOG"

log_info "Total VMs:    $VM_COUNT"
log_success "Successful:   $SUCCESSFUL"
if [[ $FAILED -gt 0 ]]; then
    log_error "Failed:       $FAILED"
else
    log_info "Failed:       $FAILED"
fi
echo ""

log_info "Summary log:  $SUMMARY_LOG"
log_info "Detail logs:  $LOG_DIR/"
echo ""

# Display failed deployments if any
if [[ $FAILED -gt 0 ]]; then
    log_warning "Failed deployments:"
    grep "✗ FAILED" "$SUMMARY_LOG" | while read -r line; do
        echo "  $line"
    done
    echo ""
fi

# ============================================================================
# Verify Agents on Manager
# ============================================================================
log_info "Verifying agents on manager..."

WAZUH_NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
MASTER_POD=$(kubectl get pods -n "$WAZUH_NAMESPACE" -l app=wazuh-manager,node-type=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$MASTER_POD" ]]; then
    echo ""
    log_info "Registered agents:"
    kubectl exec -n "$WAZUH_NAMESPACE" "$MASTER_POD" -- /var/ossec/bin/agent_control -l || true
else
    log_warning "Could not find manager pod to verify agents"
fi

# ============================================================================
# Exit Status
# ============================================================================
echo ""
if [[ $FAILED -eq 0 ]]; then
    log_success "All agents deployed successfully!"
    exit 0
else
    log_warning "Some deployments failed. Check logs for details."
    exit 1
fi
