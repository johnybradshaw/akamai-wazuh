# Harbor Authentication for Image Pulls

## Problem: ImagePullBackOff

If you're seeing `ImagePullBackOff` or `ErrImagePull` errors, it means Kubernetes can't pull images from your Harbor registry because it lacks credentials.

```
Error: ImagePullBackOff
Failed to pull image "harbor.company.com/wazuh/wazuh-indexer:4.14.1":
rpc error: code = Unknown desc = failed to pull and unpack image:
failed to resolve reference: pull access denied
```

## Quick Fix

Run the setup script:

```bash
./scripts/setup-harbor-credentials.sh
```

The script will:
1. Prompt for your Harbor credentials
2. Create a Kubernetes image pull secret
3. Configure the wazuh namespace to use it
4. Restart pods to pick up the credentials

## Manual Setup (Alternative)

If you prefer manual setup or the script doesn't work:

### Step 1: Create Image Pull Secret

```bash
# Set your Harbor details
HARBOR_URL="harbor.company.com"
HARBOR_USERNAME="your-username"
HARBOR_PASSWORD="your-password"

# Create the secret
kubectl create secret docker-registry harbor-credentials \
  --docker-server="$HARBOR_URL" \
  --docker-username="$HARBOR_USERNAME" \
  --docker-password="$HARBOR_PASSWORD" \
  --docker-email="$HARBOR_USERNAME@example.com" \
  -n wazuh
```

### Step 2: Configure Service Account

```bash
# Patch default service account to use the secret
kubectl patch serviceaccount default -n wazuh \
  -p '{"imagePullSecrets": [{"name": "harbor-credentials"}]}'
```

### Step 3: Restart Pods

```bash
# Restart all Wazuh components
kubectl rollout restart statefulset wazuh-indexer -n wazuh
kubectl rollout restart statefulset wazuh-manager-master -n wazuh
kubectl rollout restart statefulset wazuh-manager-worker -n wazuh
kubectl rollout restart deployment wazuh-dashboard -n wazuh

# Watch pods restart
kubectl get pods -n wazuh -w
```

### Step 4: Verify

```bash
# Check pod status
kubectl get pods -n wazuh

# Check for pull errors
kubectl get events -n wazuh | grep -i "pull\|backoff"

# Describe a pod to see detailed status
kubectl describe pod <pod-name> -n wazuh
```

## Using Harbor Robot Accounts (Recommended)

Robot accounts are service accounts designed for automated access. They're more secure than using personal credentials.

### Create Robot Account in Harbor

1. **Log into Harbor UI**
2. **Go to your project** (e.g., "wazuh")
3. **Click "Robot Accounts"** in the left menu
4. **Click "New Robot Account"**
   ```
   Name: wazuh-puller
   Expiration: 90 days (or Never)
   Description: For Kubernetes to pull Wazuh images
   ```
5. **Set Permissions:**
   - ✅ Pull (read) - Required
   - ❌ Push (write) - Not needed
6. **Click "Add"**
7. **Copy the token** (shown only once!)

### Use Robot Account in Kubernetes

```bash
# Robot account format: robot$<account-name>
HARBOR_URL="harbor.company.com"
ROBOT_NAME="robot\$wazuh-puller"
ROBOT_TOKEN="<paste-token-here>"

# Create secret with robot account
kubectl create secret docker-registry harbor-robot \
  --docker-server="$HARBOR_URL" \
  --docker-username="$ROBOT_NAME" \
  --docker-password="$ROBOT_TOKEN" \
  -n wazuh

# Configure service account
kubectl patch serviceaccount default -n wazuh \
  -p '{"imagePullSecrets": [{"name": "harbor-robot"}]}'

# Restart pods
kubectl rollout restart statefulset -n wazuh --all
kubectl rollout restart deployment -n wazuh --all
```

## Environment Variables Method

For automation, use environment variables:

```bash
# Set credentials
export HARBOR_URL="harbor.company.com"
export HARBOR_USERNAME="admin"
export HARBOR_PASSWORD="your-password"

# Run setup script (won't prompt)
./scripts/setup-harbor-credentials.sh
```

## Troubleshooting

### Secret Not Working

1. **Verify secret exists:**
   ```bash
   kubectl get secret harbor-credentials -n wazuh
   ```

2. **Check secret contents:**
   ```bash
   kubectl get secret harbor-credentials -n wazuh -o yaml
   ```

3. **Verify it's attached to service account:**
   ```bash
   kubectl get serviceaccount default -n wazuh -o yaml | grep imagePullSecrets
   ```

### Still Getting ImagePullBackOff

1. **Test credentials manually:**
   ```bash
   docker login harbor.company.com -u <username>
   docker pull harbor.company.com/wazuh/wazuh-indexer:4.14.1
   ```

2. **Check pod events:**
   ```bash
   kubectl describe pod <pod-name> -n wazuh | grep -A 10 Events
   ```

3. **Verify image paths are correct:**
   ```bash
   kubectl get pods -n wazuh -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n'
   ```

4. **Check Harbor project permissions:**
   - Is the project public or private?
   - Does your user/robot have pull access?
   - Are the images actually in Harbor?

### Wrong Credentials Format

If you get "unauthorized" errors:

```bash
# Delete old secret
kubectl delete secret harbor-credentials -n wazuh

# Recreate with correct format
kubectl create secret docker-registry harbor-credentials \
  --docker-server="harbor.company.com" \
  --docker-username="admin" \
  --docker-password="Harbor12345" \
  -n wazuh

# Restart pods
kubectl rollout restart statefulset -n wazuh --all
```

### Multiple Registries

If you need credentials for multiple registries:

```bash
# Create secrets for each registry
kubectl create secret docker-registry harbor-creds \
  --docker-server="harbor.company.com" \
  --docker-username="user1" \
  --docker-password="pass1" \
  -n wazuh

kubectl create secret docker-registry gcr-creds \
  --docker-server="gcr.io" \
  --docker-username="_json_key" \
  --docker-password="$(cat key.json)" \
  -n wazuh

# Add both to service account
kubectl patch serviceaccount default -n wazuh \
  -p '{"imagePullSecrets": [{"name": "harbor-creds"}, {"name": "gcr-creds"}]}'
```

## Security Best Practices

1. **Use Robot Accounts** - Don't use personal Harbor accounts
2. **Set Expiration** - Rotate credentials regularly (90 days recommended)
3. **Least Privilege** - Only grant Pull permissions, not Push
4. **Separate Secrets per Namespace** - Don't share secrets across namespaces
5. **Use Kubernetes Secrets Encryption** - Enable at-rest encryption
6. **Audit Access** - Monitor Harbor logs for unauthorized access

## Checking Credentials Are Working

### View Current Secret

```bash
# Decode and view the secret (base64 encoded)
kubectl get secret harbor-credentials -n wazuh -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq
```

### Test Image Pull

```bash
# Get a pod that's running
POD=$(kubectl get pods -n wazuh -o name | head -1)

# Check image pull events
kubectl get events -n wazuh --field-selector involvedObject.name=${POD#pod/} | grep -i pull
```

### Monitor Real-time

```bash
# Watch pod status
watch kubectl get pods -n wazuh

# Stream events
kubectl get events -n wazuh --watch | grep -i "pull\|image"
```

## Automating Credential Updates

### Create a Secret Update Script

```bash
#!/bin/bash
# update-harbor-secret.sh

HARBOR_URL="harbor.company.com"
HARBOR_USERNAME="robot\$wazuh-puller"
NEW_TOKEN="$1"

if [[ -z "$NEW_TOKEN" ]]; then
  echo "Usage: $0 <new-robot-token>"
  exit 1
fi

kubectl delete secret harbor-credentials -n wazuh 2>/dev/null || true

kubectl create secret docker-registry harbor-credentials \
  --docker-server="$HARBOR_URL" \
  --docker-username="$HARBOR_USERNAME" \
  --docker-password="$NEW_TOKEN" \
  -n wazuh

kubectl rollout restart statefulset -n wazuh --all
kubectl rollout restart deployment -n wazuh --all

echo "Credentials updated and pods restarted"
```

## Related Documentation

- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [Harbor Robot Accounts](https://goharbor.io/docs/latest/working-with-projects/project-configuration/create-robot-accounts/)
- [Harbor User Guide](https://goharbor.io/docs/latest/working-with-projects/)
