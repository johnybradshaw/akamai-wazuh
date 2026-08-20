#!/bin/bash
# ============================================================================
# Wazuh Dashboard HTTPS Certificate Generation Script (with SANs)
# ============================================================================
# This script generates the TLS certificate the Wazuh Dashboard presents on its
# own HTTPS listener (container port 5601), with a real CN and proper Subject
# Alternative Names, so that a reverse proxy in front of it can VERIFY the
# certificate instead of skipping verification.
#
# Why this exists
# ---------------
# The stock upstream generator (wazuh-kubernetes' own
# wazuh/certs/dashboard_http/generate_certs.sh) is a single line:
#
#     openssl req -x509 -batch -nodes -days 365 -newkey rsa:2048 \
#       -keyout key.pem -out cert.pem
#
# With -batch and no -subj and no config, OpenSSL falls back to its placeholder
# subject (O = Internet Widgits Pty Ltd) with no CN naming any host, and emits
# NO subjectAltName extension at all. Go's TLS stack -- which is Traefik's, and
# most modern proxies' -- has ignored CN for hostname verification since Go 1.15.
# With no SAN there is nothing to match, so that certificate can be verified
# against NO hostname whatsoever. Pinning it as a CA does not rescue it either:
# the chain would validate and the hostname check would still fail. The only
# posture left is to skip verification entirely.
#
# This script fixes that at the source. It mints a small dedicated CA and signs
# a normal server certificate off it:
#
#   ca.pem / ca-key.pem   the CA to pin in the proxy's trust store
#   cert.pem / key.pem    the leaf the Dashboard serves (names below)
#
# The leaf is a plain server certificate (CA:FALSE) and the pin is the CA, so
# reissuing the leaf does not invalidate whatever the proxy has pinned. To make
# that true in practice and not just on paper, a rerun REUSES an existing
# ca.pem/ca-key.pem pair rather than minting a new CA: rotating the leaf is the
# common operation, and it must not silently break every proxy that already
# trusts the advertised pin. Replacing the CA is a deliberate, separate act --
# set WAZUH_DASHBOARD_ROTATE_CA=true -- because it requires redistributing the
# new ca.pem to every proxy before the change takes effect.
#
# This is deliberately NOT chained to the indexer cluster root CA
# (wazuh/certs/indexer_cluster/root-ca.pem). That CA secures indexer<->node and
# dashboard<->indexer traffic; the Dashboard's public-facing HTTPS listener is a
# separate concern, and keeping them apart means this certificate can be rotated
# without touching the indexer security index (no securityadmin.sh run).
#
# Only cert.pem and key.pem are consumed by kubernetes/kustomization.yml's
# dashboard-certs secretGenerator. ca.pem is left in place for the operator to
# hand to whatever fronts the Dashboard; ca-key.pem is only needed if you want
# to reissue the leaf later against the same pin.
#
# Usage: Run this script from the directory where you want certificates
#        generated.
# Example: cd /path/to/wazuh/certs/dashboard_http && bash /path/to/this/script.sh
#
# Environment Variables:
#   WAZUH_NAMESPACE            Kubernetes namespace (default: wazuh)
#   WAZUH_DASHBOARD_EXTRA_DNS  Space-separated extra DNS names to add as SANs,
#                              for an external hostname the Dashboard is served
#                              under. Example:
#                                WAZUH_DASHBOARD_EXTRA_DNS="wazuh.example.com"
#   WAZUH_DASHBOARD_ROTATE_CA  Set to "true" to discard an existing CA and mint
#                              a new one (default: false -- an existing CA is
#                              reused so the proxy's pin keeps working). Every
#                              proxy pinning the old ca.pem MUST be given the
#                              new one; until it is, it will reject the
#                              Dashboard.
# ============================================================================

set -euo pipefail

NAMESPACE="${WAZUH_NAMESPACE:-wazuh}"
EXTRA_DNS="${WAZUH_DASHBOARD_EXTRA_DNS:-}"
ROTATE_CA="${WAZUH_DASHBOARD_ROTATE_CA:-false}"

# Generate certificates in the current working directory (where the script is
# called from). Do NOT change to the script's directory.

echo "Generating Wazuh Dashboard HTTPS certificate with Subject Alternative Names..."
echo "Using namespace: $NAMESPACE"
echo "Target directory: $(pwd)"
echo ""

# Clean up old material.
#
# Deliberately scoped to the leaf and to temporary files. ca.pem/ca-key.pem are
# the operator's advertised pin and survive a rerun unless CA rotation was asked
# for explicitly -- see WAZUH_DASHBOARD_ROTATE_CA in the header.
rm -f ./cert.pem ./key.pem ./*.csr ./*.srl ./*.cnf

if [ "$ROTATE_CA" = "true" ]; then
    echo "WARNING: WAZUH_DASHBOARD_ROTATE_CA=true -- discarding any existing CA."
    echo "         Every proxy pinning the old ca.pem will reject the Dashboard"
    echo "         until it is given the new ca.pem."
    rm -f ./ca.pem ./ca-key.pem
fi

# ============================================================================
# Dashboard HTTPS CA
# ============================================================================
echo "1. Dashboard HTTPS CA..."

# A half-present CA cannot be reused and must not be silently replaced: minting
# a fresh one here would invalidate a pin the operator may still be relying on,
# with no signal that it happened. Fail loudly and make them choose.
if [ -f ca.pem ] && [ ! -f ca-key.pem ]; then
    echo "   [FAIL] ca.pem exists but ca-key.pem is missing -- cannot sign a new"
    echo "          leaf against the pinned CA. Restore ca-key.pem, or rerun with"
    echo "          WAZUH_DASHBOARD_ROTATE_CA=true to mint a new CA (and then"
    echo "          redistribute ca.pem to every proxy that pins it)."
    exit 1
fi
if [ ! -f ca.pem ] && [ -f ca-key.pem ]; then
    echo "   [FAIL] ca-key.pem exists but ca.pem is missing -- refusing to guess."
    echo "          Restore ca.pem, or rerun with WAZUH_DASHBOARD_ROTATE_CA=true."
    exit 1
fi

if [ -f ca.pem ] && [ -f ca-key.pem ]; then
    echo "   [ok] reusing existing ca.pem (the pin in your proxy stays valid)"
else
    openssl genrsa -out ca-key.pem 2048 2>/dev/null

    openssl req -days 3650 -new -x509 -sha256 \
      -key ca-key.pem \
      -out ca.pem \
      -subj "/C=US/L=California/O=Company/CN=wazuh-dashboard-http-ca"

    echo "   [ok] ca.pem created"
fi

# ============================================================================
# Dashboard HTTPS server certificate (with SANs)
# ============================================================================
echo "2. Generating Dashboard HTTPS server certificate with SANs..."

# The Service in wazuh-kubernetes is named `dashboard`; the Deployment is named
# `wazuh-dashboard`. Cover both, at every level of the cluster search domain, so
# a proxy can pin whichever name it happens to dial.
cat > dashboard-http-openssl.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
L = California
O = Company
CN = dashboard

[v3_req]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = dashboard
DNS.2 = dashboard.${NAMESPACE}
DNS.3 = dashboard.${NAMESPACE}.svc
DNS.4 = dashboard.${NAMESPACE}.svc.cluster.local
DNS.5 = wazuh-dashboard
DNS.6 = wazuh-dashboard.${NAMESPACE}
DNS.7 = wazuh-dashboard.${NAMESPACE}.svc
DNS.8 = wazuh-dashboard.${NAMESPACE}.svc.cluster.local
DNS.9 = localhost
IP.1 = 127.0.0.1
EOF

# Append any operator-supplied external hostnames.
if [ -n "$EXTRA_DNS" ]; then
    i=10
    for name in $EXTRA_DNS; do
        echo "DNS.${i} = ${name}" >> dashboard-http-openssl.cnf
        echo "   +  extra SAN: ${name}"
        i=$((i + 1))
    done
fi

# `openssl req -newkey ... -nodes` emits an unencrypted PKCS#8 key, the same
# shape the stock upstream generator produced, so the Dashboard's Node.js TLS
# listener reads it unchanged.
openssl req -new -newkey rsa:2048 -nodes \
  -keyout key.pem \
  -out dashboard-http.csr \
  -config dashboard-http-openssl.cnf 2>/dev/null

openssl x509 -req -days 3650 \
  -in dashboard-http.csr \
  -CA ca.pem \
  -CAkey ca-key.pem \
  -CAcreateserial \
  -sha256 \
  -extensions v3_req \
  -extfile dashboard-http-openssl.cnf \
  -out cert.pem 2>/dev/null

echo "   [ok] cert.pem created with SANs"

# ============================================================================
# Verification
# ============================================================================
echo ""
echo "3. Verifying..."

if ! openssl verify -CAfile ca.pem cert.pem > /dev/null 2>&1; then
    echo "   [FAIL] cert.pem does not verify against ca.pem"
    exit 1
fi
echo "   [ok] cert.pem verifies against ca.pem"

# A missing SAN extension is the exact failure this script exists to prevent, so
# treat it as fatal rather than printing a warning and carrying on.
if ! openssl x509 -in cert.pem -text -noout | grep -q "Subject Alternative Name"; then
    echo "   [FAIL] No subjectAltName in cert.pem -- hostname verification would fail"
    exit 1
fi
openssl x509 -in cert.pem -noout -ext subjectAltName | sed 's/^/   /'

# ============================================================================
# Cleanup
# ============================================================================
echo ""
echo "Cleaning up temporary files..."
rm -f ./*.cnf ./*.csr ./*.srl

echo ""
echo "[ok] Dashboard HTTPS certificate generation completed successfully!"
echo ""
echo "Generated files:"
echo "  - ca.pem + ca-key.pem   (Dashboard HTTPS CA -- pin ca.pem in your proxy;"
echo "                           reused on rerun unless WAZUH_DASHBOARD_ROTATE_CA=true)"
echo "  - cert.pem + key.pem    (Dashboard HTTPS server cert with SANs)"
