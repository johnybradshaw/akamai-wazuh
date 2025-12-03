# Harbor Proxy Project Setup (Recommended Solution)

Harbor proxy projects provide **automatic pull-through caching** of Docker Hub images, which is far superior to manual mirroring.

## Why Harbor Proxy is Better

✅ **No manual mirroring** - Images are cached automatically on first pull
✅ **Always up-to-date** - Pulls latest from upstream if not cached
✅ **Zero maintenance** - No scripts to run for updates
✅ **Simple setup** - Just change the image path prefix
✅ **Meets compliance** - Images come from approved Harbor registry

## Setup Harbor Proxy Project

### Step 1: Create Proxy Project in Harbor

1. Log into your Harbor instance as admin
2. Go to **Projects** → **New Project**
3. Configure:
   ```
   Project Name: dockerhub-proxy
   Registry Type: Docker Hub
   Access Level: Public (or Private with robot accounts)
   Proxy Cache: ✓ Enabled
   Endpoint URL: https://registry-1.docker.io
   ```
4. Click **OK** to create

### Step 2: Update Wazuh Configuration

Use the update script with `--proxy` flag:

```bash
# Update configuration for Harbor proxy
./scripts/update-registry.sh harbor.company.com/dockerhub-proxy/wazuh --proxy
```

This will update your kustomization to use:
```yaml
images:
  - name: wazuh/wazuh-indexer
    newName: harbor.company.com/dockerhub-proxy/wazuh/wazuh-indexer
    newTag: 4.14.1
  - name: wazuh/wazuh-manager
    newName: harbor.company.com/dockerhub-proxy/wazuh/wazuh-manager
    newTag: 4.14.1
  - name: wazuh/wazuh-dashboard
    newName: harbor.company.com/dockerhub-proxy/wazuh/wazuh-dashboard
    newTag: 4.14.1
```

### Step 3: Deploy

```bash
# Apply the updated configuration
kubectl apply -k kubernetes/

# Watch the deployment
kubectl get pods -n wazuh -w
```

Harbor will automatically:
1. Receive the image pull request
2. Check its cache
3. Pull from Docker Hub if not cached
4. Cache it for future use
5. Serve it to your cluster

### Step 4: Verify

```bash
# Check pods are running without policy violations
kubectl get pods -n wazuh
kubectl get events -n wazuh | grep -i policy

# Check Harbor for cached images
# Go to Harbor UI → dockerhub-proxy project → Repositories
```

## Complete Example

```bash
# 1. Get your Harbor URL from your cluster admin
HARBOR_URL="harbor.company.com"
PROXY_PROJECT="dockerhub-proxy"

# 2. Update configuration
./scripts/update-registry.sh ${HARBOR_URL}/${PROXY_PROJECT}/wazuh --proxy

# 3. Deploy
kubectl apply -k kubernetes/

# 4. Verify
kubectl get pods -n wazuh
```

## Harbor Proxy with Authentication

If your Harbor proxy project requires authentication:

### Option 1: Image Pull Secrets

```bash
# Create docker-registry secret
kubectl create secret docker-registry harbor-credentials \
  --docker-server=harbor.company.com \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  -n wazuh

# Add to service accounts
kubectl patch serviceaccount default -n wazuh \
  -p '{"imagePullSecrets": [{"name": "harbor-credentials"}]}'
```

### Option 2: Robot Accounts (Recommended)

1. In Harbor, go to **Projects** → **dockerhub-proxy** → **Robot Accounts**
2. Click **New Robot Account**:
   ```
   Name: wazuh-puller
   Expiration: 90 days (or never)
   Permissions: Pull
   ```
3. Copy the token
4. Create Kubernetes secret:
   ```bash
   kubectl create secret docker-registry harbor-robot \
     --docker-server=harbor.company.com \
     --docker-username=robot$wazuh-puller \
     --docker-password=<robot-token> \
     -n wazuh

   kubectl patch serviceaccount default -n wazuh \
     -p '{"imagePullSecrets": [{"name": "harbor-robot"}]}'
   ```

## Troubleshooting

### Images Not Pulling from Harbor

1. **Check Harbor proxy configuration:**
   ```bash
   # Verify you can reach Harbor
   curl -I https://harbor.company.com

   # Test image pull
   docker pull harbor.company.com/dockerhub-proxy/wazuh/wazuh-indexer:4.14.1
   ```

2. **Check Harbor logs:**
   - Go to Harbor UI → Projects → dockerhub-proxy → Logs
   - Look for pull requests and errors

3. **Verify proxy project settings:**
   - Harbor UI → Projects → dockerhub-proxy → Configuration
   - Ensure "Proxy Cache" is enabled
   - Verify endpoint URL: `https://registry-1.docker.io`

### Authentication Errors

```bash
# Check if image pull secret exists
kubectl get secret harbor-credentials -n wazuh

# Check if it's attached to service account
kubectl get serviceaccount default -n wazuh -o yaml | grep imagePullSecrets

# Test credentials
docker login harbor.company.com -u <username>
```

### Policy Violations Persist

```bash
# Verify the image paths in kustomization
grep -A 3 "name: wazuh/" kubernetes/kustomization.yml

# Check what images pods are actually using
kubectl get pods -n wazuh -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n'

# Restart pods to pick up new configuration
kubectl rollout restart statefulset -n wazuh --all
kubectl rollout restart deployment -n wazuh --all
```

## Advanced: Multiple Docker Hub Namespaces

If you need images from multiple Docker Hub namespaces:

```yaml
# Harbor proxy supports full Docker Hub paths
images:
  - name: wazuh/wazuh-indexer
    newName: harbor.company.com/dockerhub-proxy/wazuh/wazuh-indexer
  - name: bitnami/postgresql
    newName: harbor.company.com/dockerhub-proxy/bitnami/postgresql
  - name: library/nginx  # Official images
    newName: harbor.company.com/dockerhub-proxy/library/nginx
```

## Comparison: Proxy vs Manual Mirror

| Feature | Harbor Proxy | Manual Mirror |
|---------|--------------|---------------|
| Setup | One-time Harbor config | Mirror each version |
| Updates | Automatic | Manual script |
| Maintenance | Zero | Regular re-mirroring |
| Storage | On-demand | Pre-cached |
| Upstream sync | Always fresh | Can be stale |
| **Recommended** | ✅ **Yes** | ❌ No |

## Benefits Summary

1. **Zero-touch operation** - Set it up once, forget about it
2. **Automatic updates** - Always pulls latest when cache expires
3. **Bandwidth efficient** - Only caches what you use
4. **Compliance friendly** - All images via approved Harbor
5. **Audit trail** - Harbor logs all image pulls
6. **Vulnerability scanning** - Harbor can scan cached images

## Next Steps

After setting up Harbor proxy:

1. **Configure image scanning** in Harbor for security
2. **Set cache retention policies** to manage storage
3. **Enable vulnerability notifications** for critical images
4. **Document the Harbor proxy URL** for your team
5. **Update deployment docs** to reference Harbor proxy

## Additional Resources

- [Harbor Proxy Cache Documentation](https://goharbor.io/docs/latest/administration/configure-proxy-cache/)
- [Harbor Robot Accounts](https://goharbor.io/docs/latest/working-with-projects/project-configuration/create-robot-accounts/)
- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
