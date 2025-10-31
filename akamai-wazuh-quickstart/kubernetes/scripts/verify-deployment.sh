#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh Quick-Start - Deployment Verification
# ============================================================================
# This script verifies the Wazuh deployment is healthy and accessible:
#   - Kubernetes resources are running
#   - LoadBalancers have external IPs
#   - DNS records are configured correctly
#   - TLS certificates are issued
#   - Dashboard is accessible
#
# Usage: ./verify-deployment.sh [namespace]
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

# Configuration
NAMESPACE="${1:-wazuh}"
DOMAIN="${DOMAIN:-}"
TIMEOUT=300
CHECK_PASSED=0
CHECK_FAILED=0

echo ""
echo "============================================================================"
echo "  Wazuh Deployment Verification"
echo "============================================================================"
echo "  Namespace: $NAMESPACE"
echo "  Timeout:   ${TIMEOUT}s"
echo "============================================================================"
echo ""

# ============================================================================
# 1. Check Namespace Exists
# ============================================================================
log_info "Checking namespace..."
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    log_success "Namespace '$NAMESPACE' exists"
    CHECK_PASSED=$((CHECK_PASSED + 1))
else
    log_error "Namespace '$NAMESPACE' does not exist"
    CHECK_FAILED=$((CHECK_FAILED + 1))
    exit 1
fi

# ============================================================================
# 2. Check Pods Status
# ============================================================================
log_info "Checking pod status..."
echo ""

POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -o json)
TOTAL_PODS=$(echo "$POD_STATUS" | jq '.items | length')

if [[ $TOTAL_PODS -eq 0 ]]; then
    log_error "No pods found in namespace '$NAMESPACE'"
    CHECK_FAILED=$((CHECK_FAILED + 1))
else
    RUNNING_PODS=$(echo "$POD_STATUS" | jq '[.items[] | select(.status.phase=="Running")] | length')
    PENDING_PODS=$(echo "$POD_STATUS" | jq '[.items[] | select(.status.phase=="Pending")] | length')
    FAILED_PODS=$(echo "$POD_STATUS" | jq '[.items[] | select(.status.phase=="Failed")] | length')

    echo "  Total Pods:   $TOTAL_PODS"
    echo "  Running:      $RUNNING_PODS"
    echo "  Pending:      $PENDING_PODS"
    echo "  Failed:       $FAILED_PODS"
    echo ""

    if [[ $RUNNING_PODS -eq $TOTAL_PODS ]]; then
        log_success "All pods are running"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Not all pods are running"
        kubectl get pods -n "$NAMESPACE"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
fi

# ============================================================================
# 3. Check StatefulSets
# ============================================================================
log_info "Checking StatefulSets..."
echo ""

STS_LIST=$(kubectl get statefulsets -n "$NAMESPACE" -o json)
STS_COUNT=$(echo "$STS_LIST" | jq '.items | length')

if [[ $STS_COUNT -eq 0 ]]; then
    log_warning "No StatefulSets found"
else
    echo "$STS_LIST" | jq -r '.items[] | "  \(.metadata.name): \(.status.readyReplicas // 0)/\(.spec.replicas)"'
    echo ""

    READY_STS=$(echo "$STS_LIST" | jq '[.items[] | select(.status.readyReplicas == .spec.replicas)] | length')

    if [[ $READY_STS -eq $STS_COUNT ]]; then
        log_success "All StatefulSets are ready ($READY_STS/$STS_COUNT)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Some StatefulSets are not ready ($READY_STS/$STS_COUNT)"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
fi

# ============================================================================
# 4. Check Deployments
# ============================================================================
log_info "Checking Deployments..."
echo ""

DEPLOY_LIST=$(kubectl get deployments -n "$NAMESPACE" -o json)
DEPLOY_COUNT=$(echo "$DEPLOY_LIST" | jq '.items | length')

if [[ $DEPLOY_COUNT -eq 0 ]]; then
    log_info "No Deployments found (this is normal for Wazuh)"
else
    echo "$DEPLOY_LIST" | jq -r '.items[] | "  \(.metadata.name): \(.status.readyReplicas // 0)/\(.spec.replicas)"'
    echo ""

    READY_DEPLOY=$(echo "$DEPLOY_LIST" | jq '[.items[] | select(.status.readyReplicas == .spec.replicas)] | length')

    if [[ $READY_DEPLOY -eq $DEPLOY_COUNT ]]; then
        log_success "All Deployments are ready ($READY_DEPLOY/$DEPLOY_COUNT)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Some Deployments are not ready ($READY_DEPLOY/$DEPLOY_COUNT)"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
fi

# ============================================================================
# 5. Check Services and LoadBalancers
# ============================================================================
log_info "Checking Services..."
echo ""

SVC_LIST=$(kubectl get services -n "$NAMESPACE" -o json)
LB_SERVICES=$(echo "$SVC_LIST" | jq -r '.items[] | select(.spec.type=="LoadBalancer") | .metadata.name')

if [[ -z "$LB_SERVICES" ]]; then
    log_warning "No LoadBalancer services found"
    CHECK_FAILED=$((CHECK_FAILED + 1))
else
    LB_READY=0
    LB_TOTAL=0

    while IFS= read -r svc; do
        LB_TOTAL=$((LB_TOTAL + 1))
        EXTERNAL_IP=$(kubectl get service "$svc" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [[ -n "$EXTERNAL_IP" ]]; then
            echo "  $svc: $EXTERNAL_IP"
            LB_READY=$((LB_READY + 1))
        else
            echo "  $svc: <pending>"
        fi
    done <<< "$LB_SERVICES"

    echo ""

    if [[ $LB_READY -eq $LB_TOTAL ]]; then
        log_success "All LoadBalancers have external IPs ($LB_READY/$LB_TOTAL)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Some LoadBalancers are pending ($LB_READY/$LB_TOTAL)"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
fi

# ============================================================================
# 6. Check DNS Records (if domain is set)
# ============================================================================
if [[ -n "$DOMAIN" ]]; then
    log_info "Checking DNS records for domain: $DOMAIN"
    echo ""

    DNS_HOSTS=("wazuh.$DOMAIN" "wazuh-manager.$DOMAIN" "wazuh-registration.$DOMAIN")
    DNS_PASSED=0
    DNS_TOTAL=${#DNS_HOSTS[@]}

    for host in "${DNS_HOSTS[@]}"; do
        if dig +short "$host" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' &>/dev/null; then
            IP=$(dig +short "$host" | head -1)
            echo "  $host: $IP"
            DNS_PASSED=$((DNS_PASSED + 1))
        else
            echo "  $host: <not resolved>"
        fi
    done

    echo ""

    if [[ $DNS_PASSED -eq $DNS_TOTAL ]]; then
        log_success "All DNS records are configured ($DNS_PASSED/$DNS_TOTAL)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Some DNS records are not configured ($DNS_PASSED/$DNS_TOTAL)"
        log_info "DNS propagation can take 2-5 minutes"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
else
    log_info "Domain not set, skipping DNS check"
fi

# ============================================================================
# 7. Check TLS Certificates
# ============================================================================
log_info "Checking TLS certificates..."
echo ""

CERT_LIST=$(kubectl get certificates -n "$NAMESPACE" -o json 2>/dev/null || echo '{"items":[]}')
CERT_COUNT=$(echo "$CERT_LIST" | jq '.items | length')

if [[ $CERT_COUNT -eq 0 ]]; then
    log_warning "No certificates found"
    CHECK_FAILED=$((CHECK_FAILED + 1))
else
    READY_CERTS=$(echo "$CERT_LIST" | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

    echo "$CERT_LIST" | jq -r '.items[] | "  \(.metadata.name): \(if .status.conditions[]? | select(.type=="Ready" and .status=="True") then "Ready" else "Not Ready" end)"'
    echo ""

    if [[ $READY_CERTS -eq $CERT_COUNT ]]; then
        log_success "All certificates are ready ($READY_CERTS/$CERT_COUNT)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Some certificates are not ready ($READY_CERTS/$CERT_COUNT)"
        log_info "Certificate issuance can take 2-5 minutes"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
fi

# ============================================================================
# 8. Check Dashboard Accessibility (if domain is set)
# ============================================================================
if [[ -n "$DOMAIN" ]]; then
    log_info "Checking dashboard accessibility..."

    DASHBOARD_URL="https://wazuh.$DOMAIN"
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$DASHBOARD_URL" --connect-timeout 10 || echo "000")

    if [[ "$HTTP_CODE" =~ ^(200|302|401)$ ]]; then
        log_success "Dashboard is accessible (HTTP $HTTP_CODE)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Dashboard not accessible (HTTP $HTTP_CODE)"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
else
    log_info "Domain not set, skipping dashboard check"
fi

# ============================================================================
# 9. Check PersistentVolumeClaims
# ============================================================================
log_info "Checking PersistentVolumeClaims..."
echo ""

PVC_LIST=$(kubectl get pvc -n "$NAMESPACE" -o json)
PVC_COUNT=$(echo "$PVC_LIST" | jq '.items | length')

if [[ $PVC_COUNT -eq 0 ]]; then
    log_warning "No PVCs found"
else
    BOUND_PVCS=$(echo "$PVC_LIST" | jq '[.items[] | select(.status.phase=="Bound")] | length')

    echo "$PVC_LIST" | jq -r '.items[] | "  \(.metadata.name): \(.status.phase) (\(.spec.resources.requests.storage))"'
    echo ""

    if [[ $BOUND_PVCS -eq $PVC_COUNT ]]; then
        log_success "All PVCs are bound ($BOUND_PVCS/$PVC_COUNT)"
        CHECK_PASSED=$((CHECK_PASSED + 1))
    else
        log_warning "Some PVCs are not bound ($BOUND_PVCS/$PVC_COUNT)"
        CHECK_FAILED=$((CHECK_FAILED + 1))
    fi
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "============================================================================"
echo "  Verification Summary"
echo "============================================================================"
echo "  Checks Passed: $CHECK_PASSED"
echo "  Checks Failed: $CHECK_FAILED"
echo "============================================================================"
echo ""

if [[ $CHECK_FAILED -eq 0 ]]; then
    log_success "Deployment verification PASSED! ✓"
    echo ""

    if [[ -n "$DOMAIN" ]]; then
        log_info "Access your Wazuh deployment:"
        echo "  • Dashboard:    https://wazuh.$DOMAIN"
        echo "  • Manager:      wazuh-manager.$DOMAIN:1514"
        echo "  • Registration: wazuh-registration.$DOMAIN:1515"
    fi

    echo ""
    exit 0
else
    log_error "Deployment verification FAILED with $CHECK_FAILED issue(s)"
    echo ""
    log_info "Troubleshooting steps:"
    echo "  1. Check pod logs: kubectl logs -n $NAMESPACE <pod-name>"
    echo "  2. Describe resources: kubectl describe pod -n $NAMESPACE <pod-name>"
    echo "  3. Check events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    echo "  4. Verify DNS: dig wazuh.$DOMAIN"
    echo "  5. Check certificates: kubectl describe certificate -n $NAMESPACE"
    echo ""
    exit 1
fi
