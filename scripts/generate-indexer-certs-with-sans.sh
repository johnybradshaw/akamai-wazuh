#!/bin/bash
# ============================================================================
# Wazuh Indexer Certificate Generation Script (with SANs)
# ============================================================================
# This script generates TLS certificates for Wazuh Indexer with proper
# Subject Alternative Names (SANs) for hostname verification.
#
# The certificates include SANs for:
# - indexer (Kubernetes service name)
# - wazuh-indexer (StatefulSet service name)
# - wazuh-indexer-0, wazuh-indexer-1, wazuh-indexer-2 (pod hostnames)
# - Fully qualified domain names
# - localhost
#
# This fixes the "x509: certificate is valid for X, not Y" errors.
# ============================================================================

set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Generating Wazuh Indexer certificates with Subject Alternative Names..."
echo ""

# Clean up old certificates
rm -f *.pem *.csr *.srl

# ============================================================================
# Root CA
# ============================================================================
echo "1. Generating Root CA..."

openssl genrsa -out root-ca-key.pem 2048 2>/dev/null

openssl req -days 3650 -new -x509 -sha256 \
  -key root-ca-key.pem \
  -out root-ca.pem \
  -subj "/C=US/L=California/O=Company/CN=root-ca"

echo "   ✓ root-ca.pem created"

# ============================================================================
# Admin Certificate
# ============================================================================
echo "2. Generating Admin certificate..."

openssl genrsa -out admin-key-temp.pem 2048 2>/dev/null

openssl pkcs8 -inform PEM -outform PEM \
  -in admin-key-temp.pem \
  -topk8 -nocrypt -v1 PBE-SHA1-3DES \
  -out admin-key.pem

openssl req -new -key admin-key.pem \
  -out admin.csr \
  -subj "/C=US/L=California/O=Company/CN=admin"

openssl x509 -req -days 3650 \
  -in admin.csr \
  -CA root-ca.pem \
  -CAkey root-ca-key.pem \
  -CAcreateserial \
  -sha256 \
  -out admin.pem 2>/dev/null

echo "   ✓ admin.pem created"

# ============================================================================
# Node Certificate (with SANs)
# ============================================================================
echo "3. Generating Node certificate with SANs..."

# Create OpenSSL config for SANs
cat > node-openssl.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
L = California
O = Company
CN = indexer

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = indexer
DNS.2 = wazuh-indexer
DNS.3 = wazuh-indexer-0
DNS.4 = wazuh-indexer-1
DNS.5 = wazuh-indexer-2
DNS.6 = wazuh-indexer.wazuh
DNS.7 = wazuh-indexer.wazuh.svc
DNS.8 = wazuh-indexer.wazuh.svc.cluster.local
DNS.9 = wazuh-indexer-0.wazuh-indexer
DNS.10 = wazuh-indexer-1.wazuh-indexer
DNS.11 = wazuh-indexer-2.wazuh-indexer
DNS.12 = wazuh-indexer-0.wazuh-indexer.wazuh.svc.cluster.local
DNS.13 = wazuh-indexer-1.wazuh-indexer.wazuh.svc.cluster.local
DNS.14 = wazuh-indexer-2.wazuh-indexer.wazuh.svc.cluster.local
DNS.15 = localhost
IP.1 = 127.0.0.1
EOF

openssl genrsa -out node-key-temp.pem 2048 2>/dev/null

openssl pkcs8 -inform PEM -outform PEM \
  -in node-key-temp.pem \
  -topk8 -nocrypt -v1 PBE-SHA1-3DES \
  -out node-key.pem

openssl req -new -key node-key.pem \
  -out node.csr \
  -config node-openssl.cnf

openssl x509 -req -days 3650 \
  -in node.csr \
  -CA root-ca.pem \
  -CAkey root-ca-key.pem \
  -CAcreateserial \
  -sha256 \
  -extensions v3_req \
  -extfile node-openssl.cnf \
  -out node.pem 2>/dev/null

echo "   ✓ node.pem created with SANs"

# Verify SANs in certificate
echo "   Verifying SANs..."
openssl x509 -in node.pem -text -noout | grep -A 1 "Subject Alternative Name" || echo "   ⚠ No SANs found!"

# ============================================================================
# Dashboard Certificate (with SANs)
# ============================================================================
echo "4. Generating Dashboard certificate with SANs..."

cat > dashboard-openssl.cnf << EOF
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
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = dashboard
DNS.2 = wazuh-dashboard
DNS.3 = wazuh-dashboard.wazuh
DNS.4 = wazuh-dashboard.wazuh.svc
DNS.5 = wazuh-dashboard.wazuh.svc.cluster.local
DNS.6 = localhost
IP.1 = 127.0.0.1
EOF

openssl genrsa -out dashboard-key-temp.pem 2048 2>/dev/null

openssl pkcs8 -inform PEM -outform PEM \
  -in dashboard-key-temp.pem \
  -topk8 -nocrypt -v1 PBE-SHA1-3DES \
  -out dashboard-key.pem

openssl req -new -key dashboard-key.pem \
  -out dashboard.csr \
  -config dashboard-openssl.cnf

openssl x509 -req -days 3650 \
  -in dashboard.csr \
  -CA root-ca.pem \
  -CAkey root-ca-key.pem \
  -CAcreateserial \
  -sha256 \
  -extensions v3_req \
  -extfile dashboard-openssl.cnf \
  -out dashboard.pem 2>/dev/null

echo "   ✓ dashboard.pem created with SANs"

# ============================================================================
# Filebeat Certificate (with SANs)
# ============================================================================
echo "5. Generating Filebeat certificate with SANs..."

cat > filebeat-openssl.cnf << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
L = California
O = Company
CN = filebeat

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = filebeat
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl genrsa -out filebeat-key-temp.pem 2048 2>/dev/null

openssl pkcs8 -inform PEM -outform PEM \
  -in filebeat-key-temp.pem \
  -topk8 -nocrypt -v1 PBE-SHA1-3DES \
  -out filebeat-key.pem

openssl req -new -key filebeat-key.pem \
  -out filebeat.csr \
  -config filebeat-openssl.cnf

openssl x509 -req -days 3650 \
  -in filebeat.csr \
  -CA root-ca.pem \
  -CAkey root-ca-key.pem \
  -CAcreateserial \
  -sha256 \
  -extensions v3_req \
  -extfile filebeat-openssl.cnf \
  -out filebeat.pem 2>/dev/null

echo "   ✓ filebeat.pem created with SANs"

# ============================================================================
# Cleanup
# ============================================================================
echo ""
echo "Cleaning up temporary files..."
rm -f *.cnf *.csr *-temp.pem *.srl

echo ""
echo "✓ Certificate generation completed successfully!"
echo ""
echo "Generated certificates:"
echo "  - root-ca.pem (Root CA)"
echo "  - admin.pem + admin-key.pem (Admin client cert)"
echo "  - node.pem + node-key.pem (Indexer node cert with SANs)"
echo "  - dashboard.pem + dashboard-key.pem (Dashboard cert with SANs)"
echo "  - filebeat.pem + filebeat-key.pem (Filebeat client cert with SANs)"
