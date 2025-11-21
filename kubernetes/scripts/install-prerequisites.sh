#!/bin/bash
# ============================================================================
# Akamai Cloud Wazuh Quick-Start - Prerequisites Installation
# ============================================================================
# This script installs the required infrastructure components:
#   - nginx-ingress controller (for HTTPS access)
#   - cert-manager (for Let's Encrypt TLS certificates)
#   - ExternalDNS (for automatic DNS management)
#
# Usage: ./install-prerequisites.sh
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

# Check required environment variables
if [[ -z "${DOMAIN:-}" ]]; then
    log_error "DOMAIN environment variable is not set"
    exit 1
fi

if [[ -z "${LINODE_API_TOKEN:-}" ]]; then
    log_error "LINODE_API_TOKEN environment variable is not set"
    exit 1
fi

if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
    log_error "LETSENCRYPT_EMAIL environment variable is not set"
    exit 1
fi

# ============================================================================
# 1. Install NGINX Ingress Controller
# ============================================================================
log_info "Installing NGINX Ingress Controller..."

if kubectl get namespace ingress-nginx &>/dev/null; then
    log_warning "ingress-nginx namespace already exists, skipping..."
else
    # Add helm repository
    if ! helm repo list | grep -q "ingress-nginx"; then
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
    fi

    # Install nginx-ingress
    helm install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --create-namespace \
        --set controller.service.type=LoadBalancer \
        --set controller.publishService.enabled=true \
        --set controller.metrics.enabled=true \
        --wait \
        --timeout 5m

    log_success "NGINX Ingress Controller installed successfully"
fi

# Wait for LoadBalancer to get external IP
log_info "Waiting for Ingress LoadBalancer to get external IP..."
RETRIES=0
MAX_RETRIES=30
while [[ $RETRIES -lt $MAX_RETRIES ]]; do
    INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$INGRESS_IP" ]]; then
        log_success "Ingress LoadBalancer IP: $INGRESS_IP"
        break
    fi
    RETRIES=$((RETRIES + 1))
    sleep 10
done

if [[ -z "$INGRESS_IP" ]]; then
    log_error "Failed to get Ingress LoadBalancer IP after ${MAX_RETRIES} attempts"
    exit 1
fi

# ============================================================================
# 2. Install cert-manager
# ============================================================================
log_info "Installing cert-manager..."

if kubectl get namespace cert-manager &>/dev/null; then
    log_warning "cert-manager namespace already exists, skipping..."
else
    # Install cert-manager CRDs and controller
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

    # Wait for cert-manager to be ready
    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/instance=cert-manager \
        -n cert-manager \
        --timeout=180s

    log_success "cert-manager installed successfully"
fi

# Create Let's Encrypt ClusterIssuer
log_info "Creating Let's Encrypt ClusterIssuer..."

cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

log_success "Let's Encrypt ClusterIssuers created"

# ============================================================================
# 3. Install ExternalDNS for Linode
# ============================================================================
log_info "Installing ExternalDNS for Linode..."

if kubectl get secret external-dns-linode -n kube-system &>/dev/null; then
    log_warning "ExternalDNS secret already exists, updating..."
    kubectl delete secret external-dns-linode -n kube-system
fi

# Create secret for Linode API token
kubectl create secret generic external-dns-linode \
    --from-literal=token="${LINODE_API_TOKEN}" \
    -n kube-system

# Deploy ExternalDNS
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: kube-system
  labels:
    app: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
  labels:
    app: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
  labels:
    app: external-dns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: kube-system
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: kube-system
  labels:
    app: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.k8s.io/external-dns/external-dns:v0.14.0
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=${DOMAIN}
        - --provider=linode
        - --registry=txt
        - --txt-owner-id=wazuh-k8s-cluster
        - --txt-prefix=_externaldns-
        - --log-level=info
        - --interval=1m
        env:
        - name: LINODE_TOKEN
          valueFrom:
            secretKeyRef:
              name: external-dns-linode
              key: token
        resources:
          limits:
            memory: 50Mi
            cpu: 50m
          requests:
            memory: 50Mi
            cpu: 10m
        securityContext:
          runAsNonRoot: true
          runAsUser: 65534
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
EOF

# Wait for ExternalDNS to be ready
log_info "Waiting for ExternalDNS to be ready..."
kubectl wait --for=condition=available deployment/external-dns \
    -n kube-system \
    --timeout=60s

log_success "ExternalDNS installed successfully"

# ============================================================================
# Summary
# ============================================================================
echo ""
log_success "All prerequisites installed successfully!"
echo ""
log_info "Installed components:"
echo "  • NGINX Ingress Controller (LoadBalancer IP: $INGRESS_IP)"
echo "  • cert-manager (with Let's Encrypt ClusterIssuers)"
echo "  • ExternalDNS (configured for domain: $DOMAIN)"
echo ""
log_info "Next steps:"
echo "  1. Verify DNS configuration for your domain on Linode"
echo "  2. Ensure kubectl has access to your LKE cluster"
echo "  3. Run the main deployment script: ./deploy.sh"
echo ""
