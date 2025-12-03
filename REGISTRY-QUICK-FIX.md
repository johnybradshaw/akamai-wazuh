# Quick Fix: Registry Policy Violations

## Problem
PolicyExceptions are **not enabled** in your Kyverno installation, so the exception approach won't work. You must use an approved container registry.

## Solution: Mirror Images to Approved Registry

### Step 1: Find Your Approved Registry

Ask your cluster administrator what container registry is approved. Examples:
- `harbor.company.com/wazuh`
- `registry.company.com/security/wazuh`
- `artifactory.company.com/docker/wazuh`
- `<account>.dkr.ecr.us-east-1.amazonaws.com/wazuh`

### Step 2: Authenticate to Your Registry

```bash
# For Harbor
docker login harbor.company.com

# For AWS ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com

# For Artifactory
docker login artifactory.company.com

# For Google GCR
gcloud auth configure-docker

# For Azure ACR
az acr login --name <registry-name>
```

### Step 3: Mirror the Images

Replace `YOUR-REGISTRY` with your approved registry path:

```bash
# Example: If your registry is harbor.company.com/wazuh
./scripts/mirror-images.sh harbor.company.com/wazuh

# Or with full path
./scripts/mirror-images.sh registry.company.com/security/wazuh
```

This script will:
1. Pull Wazuh images from Docker Hub
2. Tag them for your internal registry
3. Push them to your registry

### Step 4: Update Kustomization

Update the configuration to use your registry:

```bash
# Example: If your registry is harbor.company.com/wazuh
./scripts/update-registry.sh harbor.company.com/wazuh

# Or with custom version
./scripts/update-registry.sh harbor.company.com/wazuh 4.14.1
```

### Step 5: Redeploy Wazuh

```bash
# Apply updated configuration
kubectl apply -k kubernetes/

# Verify pods are running without violations
kubectl get pods -n wazuh
kubectl get events -n wazuh | grep PolicyViolation
```

## Manual Alternative

If the scripts don't work, manually mirror each image:

```bash
# Set your registry
REGISTRY="harbor.company.com/wazuh"

# Mirror indexer
docker pull wazuh/wazuh-indexer:4.14.1
docker tag wazuh/wazuh-indexer:4.14.1 $REGISTRY/wazuh-indexer:4.14.1
docker push $REGISTRY/wazuh-indexer:4.14.1

# Mirror manager
docker pull wazuh/wazuh-manager:4.14.1
docker tag wazuh/wazuh-manager:4.14.1 $REGISTRY/wazuh-manager:4.14.1
docker push $REGISTRY/wazuh-manager:4.14.1

# Mirror dashboard
docker pull wazuh/wazuh-dashboard:4.14.1
docker tag wazuh/wazuh-dashboard:4.14.1 $REGISTRY/wazuh-dashboard:4.14.1
docker push $REGISTRY/wazuh-dashboard:4.14.1
```

Then manually edit `kubernetes/kustomization.yml`:

```yaml
images:
  - name: wazuh/wazuh-indexer
    newName: harbor.company.com/wazuh/wazuh-indexer
    newTag: 4.14.1
  - name: wazuh/wazuh-manager
    newName: harbor.company.com/wazuh/wazuh-manager
    newTag: 4.14.1
  - name: wazuh/wazuh-dashboard
    newName: harbor.company.com/wazuh/wazuh-dashboard
    newTag: 4.14.1
```

## Troubleshooting

### "Authentication required"
```bash
# Make sure you're logged in to your registry
docker login <your-registry>
```

### "Unauthorized" or "Access denied"
Ask your administrator to grant you push access to the registry project/repository.

### "Network timeout"
Check if you can reach your registry:
```bash
curl -I https://<your-registry>
```

### Images pushed but policy still failing
Make sure you updated the kustomization.yml correctly and redeployed:
```bash
grep -A 10 "^images:" kubernetes/kustomization.yml
kubectl apply -k kubernetes/
```

## Alternative: Enable PolicyExceptions (Requires Admin)

If you have cluster admin access, enable PolicyExceptions:

```bash
# Enable PolicyExceptions in Kyverno
kubectl patch configmap kyverno -n kyverno --type merge \
  -p '{"data":{"enablePolicyException":"true"}}'

# Restart Kyverno
kubectl rollout restart deployment kyverno -n kyverno

# Wait for Kyverno to be ready
kubectl wait --for=condition=available --timeout=60s \
  deployment/kyverno -n kyverno

# Re-apply the PolicyException
kubectl apply -f kubernetes/wazuh-policy-exception.yaml

# Restart Wazuh pods
kubectl rollout restart statefulset -n wazuh --all
kubectl rollout restart deployment -n wazuh --all
```

## Need Help?

Contact your cluster administrator and provide:
1. This error message: `PolicyException resources would not be processed until it is enabled`
2. The policy name: `orcs-compliance-cluster/validate-orcs-registry-cluster`
3. Request: Either enable PolicyExceptions or provide the approved registry path

## Documentation

- Full guide: [docs/REGISTRY-POLICY.md](docs/REGISTRY-POLICY.md)
- Mirror script: [scripts/mirror-images.sh](scripts/mirror-images.sh)
- Update script: [scripts/update-registry.sh](scripts/update-registry.sh)
