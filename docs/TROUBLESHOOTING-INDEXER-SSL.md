# Troubleshooting: Wazuh Indexer SSL/TLS Startup Errors

## Error Symptoms

The Wazuh indexer pod fails to start with SSL/TLS errors such as:

```
javax.crypto.BadPaddingException: Insufficient buffer remaining for AEAD cipher fragment (2). Needs to be more than tag size (16)
at java.base/sun.security.ssl.SSLCipher$T13GcmReadCipherGenerator$GcmReadCipher.decrypt(SSLCipher.java:1864)
```

This error indicates that the indexer cannot properly decrypt SSL/TLS communications.

## Root Cause

The TLS certificates required for secure communication between Wazuh components are either:
1. **Missing** - Not generated before deployment
2. **Corrupted** - Files are damaged or incomplete
3. **Incorrect** - Wrong permissions or format

Most commonly, this occurs when:
- The `kubernetes/wazuh-kubernetes/` directory is missing
- The certificate generation scripts were not run
- Certificates were deleted after deployment

## Solution

### Step 1: Verify the Issue

Check if the wazuh-kubernetes repository and certificates exist:

```bash
# Check if repository exists
ls -la kubernetes/wazuh-kubernetes/

# Check if certificates exist
ls -la kubernetes/wazuh-kubernetes/wazuh/certs/indexer_cluster/
ls -la kubernetes/wazuh-kubernetes/wazuh/certs/dashboard_http/
```

### Step 2: Clone Repository (if missing)

If the `kubernetes/wazuh-kubernetes/` directory doesn't exist:

```bash
git clone https://github.com/wazuh/wazuh-kubernetes.git kubernetes/wazuh-kubernetes
```

### Step 3: Generate Certificates

Generate the required TLS certificates:

```bash
# Generate indexer cluster certificates
cd kubernetes/wazuh-kubernetes/wazuh/certs/indexer_cluster
bash generate_certs.sh

# Generate dashboard HTTP certificates
cd ../dashboard_http
bash generate_certs.sh

# Return to project root
cd ../../../../
```

### Step 4: Verify Certificate Generation

Confirm all required certificate files are present:

```bash
# Indexer certificates (should see 9 .pem files)
ls -la kubernetes/wazuh-kubernetes/wazuh/certs/indexer_cluster/*.pem

# Dashboard certificates (should see 2 .pem files)
ls -la kubernetes/wazuh-kubernetes/wazuh/certs/dashboard_http/*.pem
```

Required files:
- **Indexer cluster**: root-ca.pem, node.pem, node-key.pem, dashboard.pem, dashboard-key.pem, admin.pem, admin-key.pem, filebeat.pem, filebeat-key.pem
- **Dashboard HTTP**: cert.pem, key.pem

### Step 5: Redeploy or Update Secrets

If you're doing a fresh deployment:

```bash
kubectl apply -k kubernetes/
```

If the deployment already exists, update the secrets:

```bash
# Delete existing certificate secrets
kubectl delete secret -n wazuh indexer-certs
kubectl delete secret -n wazuh dashboard-certs

# Recreate with new certificates
kubectl apply -k kubernetes/
```

### Step 6: Restart Pods

Force pods to restart with the new certificates:

```bash
# Restart indexer pods
kubectl rollout restart statefulset/wazuh-indexer -n wazuh

# Restart dashboard pods
kubectl rollout restart deployment/wazuh-dashboard -n wazuh

# Restart manager pods (if needed)
kubectl rollout restart statefulset/wazuh-manager-master -n wazuh
kubectl rollout restart statefulset/wazuh-manager-worker -n wazuh
```

### Step 7: Verify Fix

Check that pods start successfully:

```bash
# Watch pod status
kubectl get pods -n wazuh -w

# Check indexer logs
kubectl logs -n wazuh wazuh-indexer-0 --tail=50

# Check for errors
kubectl describe pod -n wazuh wazuh-indexer-0
```

## Prevention

To prevent this issue in the future:

1. **Use the deployment script**: Always run `./deploy.sh` which handles certificate generation automatically

2. **Don't delete wazuh-kubernetes**: The `kubernetes/wazuh-kubernetes/` directory is needed for deployments (it's gitignored intentionally)

3. **Backup certificates**: If you need to redeploy, keep a backup of the certificates:
   ```bash
   tar -czf wazuh-certs-backup.tar.gz kubernetes/wazuh-kubernetes/wazuh/certs/
   ```

4. **Check before deploying**: Always verify certificates exist before running `kubectl apply`

## Quick Fix Script

You can create a quick fix script to automate this:

```bash
#!/bin/bash
# fix-indexer-certs.sh

set -e

echo "Checking wazuh-kubernetes repository..."
if [ ! -d "kubernetes/wazuh-kubernetes" ]; then
    echo "Cloning wazuh-kubernetes repository..."
    git clone https://github.com/wazuh/wazuh-kubernetes.git kubernetes/wazuh-kubernetes
fi

echo "Generating indexer certificates..."
cd kubernetes/wazuh-kubernetes/wazuh/certs/indexer_cluster
bash generate_certs.sh

echo "Generating dashboard certificates..."
cd ../dashboard_http
bash generate_certs.sh

echo "Certificates generated successfully!"
echo "Now run: kubectl rollout restart statefulset/wazuh-indexer -n wazuh"
```

## Related Issues

### Security Not Initialized Error

After fixing certificate issues, you may see:
```
[ERROR][o.o.s.a.BackendRegistry] Not yet initialized (you may need to run securityadmin)
```

This means the OpenSearch security plugin needs to be initialized.

**Quick Fix:**
```bash
# Run the security initialization script
./scripts/init-security.sh

# Or manually run securityadmin
kubectl exec -n wazuh wazuh-indexer-0 -- bash -c '
  cd /usr/share/wazuh-indexer/plugins/opensearch-security/tools && \
  JAVA_HOME=/usr/share/wazuh-indexer/jdk bash securityadmin.sh \
    -cd /usr/share/wazuh-indexer/config/opensearch-security \
    -icl -nhnv \
    -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
    -cert /usr/share/wazuh-indexer/config/certs/admin.pem \
    -key /usr/share/wazuh-indexer/config/certs/admin-key.pem \
    -h localhost
'
```

**Why this happens:**
- The security plugin requires initialization on first startup
- The `internal_users.yml` and other security configs need to be loaded
- The security index (`.opendistro_security`) needs to be created

**Auto-initialization:**
The indexer is configured with `plugins.security.allow_default_init_securityindex: true`, which should auto-initialize. However, this only works if:
- All cluster nodes are healthy
- Certificates are valid
- The cluster has reached quorum

If auto-initialization fails, run the script above to manually initialize.

### Other Common Issues

- If you see "certificate verify failed" errors, the root CA might not be trusted
- If you see "hostname verification failed", check that certificate CN matches service names
- If pods still won't start, check resource limits and node capacity

## Additional Resources

- Wazuh Kubernetes Documentation: https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/
- OpenSearch Security Configuration: https://opensearch.org/docs/latest/security/configuration/
- Kubernetes Secrets Management: https://kubernetes.io/docs/concepts/configuration/secret/
