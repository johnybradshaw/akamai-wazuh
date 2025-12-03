# Handling Registry Policy Violations

## Problem

Your Kubernetes cluster has a Kyverno policy (`orcs-compliance-cluster/validate-orcs-registry-cluster`) that requires all container images to come from approved registries. The Wazuh deployment uses images from Docker Hub (`docker.io/wazuh/*`), which is not in the approved registry list.

## Error Message

```
PolicyViolation: policy orcs-compliance-cluster/validate-orcs-registry-cluster fail:
validation failure: validation error: rule validate-orcs-registry-cluster failed
```

## Solutions

You have three options to resolve this:

### Option 1: Apply PolicyException (Recommended for Quick Setup)

Create an exception to allow Wazuh images from Docker Hub.

**Apply the exception:**

```bash
kubectl apply -f kubernetes/wazuh-policy-exception.yaml
```

**Verify the exception:**

```bash
# Check if exception was created
kubectl get policyexception -n wazuh

# Restart pods to clear violations
kubectl rollout restart statefulset wazuh-indexer -n wazuh
kubectl rollout restart statefulset wazuh-manager-master -n wazuh
kubectl rollout restart statefulset wazuh-manager-worker -n wazuh
kubectl rollout restart deployment wazuh-dashboard -n wazuh
```

**Pros:**
- ✅ Quick and easy
- ✅ Uses official Wazuh images
- ✅ Automatic updates when changing image tags

**Cons:**
- ⚠️ May not meet strict compliance requirements
- ⚠️ Requires policy exception approval

---

### Option 2: Use Internal Registry Mirror (Recommended for Production)

Mirror Wazuh images to your organization's approved container registry.

#### Step 1: Mirror Images to Your Registry

```bash
# Set your internal registry
INTERNAL_REGISTRY="your-registry.company.com/wazuh"

# Pull, tag, and push Wazuh images
for image in wazuh-indexer wazuh-manager wazuh-dashboard; do
  docker pull wazuh/${image}:4.14.1
  docker tag wazuh/${image}:4.14.1 ${INTERNAL_REGISTRY}/${image}:4.14.1
  docker push ${INTERNAL_REGISTRY}/${image}:4.14.1
done
```

#### Step 2: Update Kustomization

Edit `kubernetes/kustomization.yml`:

```yaml
images:
  - name: wazuh/wazuh-indexer
    newName: your-registry.company.com/wazuh/wazuh-indexer
    newTag: 4.14.1
  - name: wazuh/wazuh-manager
    newName: your-registry.company.com/wazuh/wazuh-manager
    newTag: 4.14.1
  - name: wazuh/wazuh-dashboard
    newName: your-registry.company.com/wazuh/wazuh-dashboard
    newTag: 4.14.1
```

#### Step 3: Redeploy

```bash
kubectl apply -k kubernetes/
```

**Pros:**
- ✅ Meets compliance requirements
- ✅ Full control over image versions
- ✅ Can scan images before deployment
- ✅ No internet dependency for cluster

**Cons:**
- ⚠️ Requires registry infrastructure
- ⚠️ Manual image mirroring process
- ⚠️ Need to update mirrors for new versions

---

### Option 3: Automated Registry Mirror (Best for Enterprise)

Use a tool to automatically mirror and sync images.

#### Using Harbor Registry

If using Harbor with proxy cache or replication:

1. **Create Proxy Project in Harbor:**
   ```
   Project Name: dockerhub-proxy
   Registry: https://registry-1.docker.io
   ```

2. **Update Kustomization:**
   ```yaml
   images:
     - name: wazuh/wazuh-indexer
       newName: harbor.company.com/dockerhub-proxy/wazuh/wazuh-indexer
       newTag: 4.14.1
   ```

#### Using Artifactory

If using JFrog Artifactory with remote repositories:

1. **Create Docker Remote Repository:**
   ```
   Repository Key: dockerhub-remote
   URL: https://registry-1.docker.io
   ```

2. **Update Kustomization:**
   ```yaml
   images:
     - name: wazuh/wazuh-indexer
       newName: artifactory.company.com/dockerhub-remote/wazuh/wazuh-indexer
       newTag: 4.14.1
   ```

**Pros:**
- ✅ Automatic image caching
- ✅ Meets compliance requirements
- ✅ Minimal manual maintenance
- ✅ Centralized image management

---

## Applying the Solution

### Quick Fix (Option 1 - PolicyException)

```bash
# 1. Apply the exception
kubectl apply -f kubernetes/wazuh-policy-exception.yaml

# 2. Wait for exception to be processed
sleep 10

# 3. Restart all Wazuh pods
kubectl rollout restart statefulset wazuh-indexer -n wazuh
kubectl rollout restart statefulset wazuh-manager-master -n wazuh
kubectl rollout restart statefulset wazuh-manager-worker -n wazuh
kubectl rollout restart deployment wazuh-dashboard -n wazuh

# 4. Verify pods are running
kubectl get pods -n wazuh

# 5. Check for policy violations
kubectl get events -n wazuh | grep PolicyViolation
```

### Production Fix (Option 2 - Internal Registry)

See the detailed steps above for mirroring images to your internal registry.

---

## Troubleshooting

### PolicyException Not Working

1. **Verify Kyverno version:**
   ```bash
   kubectl get deployment kyverno -n kyverno -o yaml | grep image:
   ```

   PolicyException requires Kyverno 1.9.0+

2. **Check exception status:**
   ```bash
   kubectl get policyexception wazuh-registry-exception -n wazuh -o yaml
   ```

3. **Try ClusterPolicyException instead:**
   ```bash
   # The manifest includes both - try applying the ClusterPolicyException
   kubectl apply -f kubernetes/wazuh-policy-exception.yaml
   ```

### Still Seeing Violations After Exception

1. **Delete and recreate pods:**
   ```bash
   kubectl delete pods -n wazuh -l app=wazuh-indexer
   kubectl delete pods -n wazuh -l app=wazuh-manager
   kubectl delete pods -n wazuh -l app=wazuh-dashboard
   ```

2. **Verify exception is active:**
   ```bash
   kubectl get policyexception -A
   ```

### Need to Check Policy Details

If you have cluster admin access:

```bash
# View the ORCS policy
kubectl get clusterpolicy orcs-compliance-cluster -o yaml

# Check what registries are allowed
kubectl get clusterpolicy orcs-compliance-cluster -o jsonpath='{.spec.rules[*].validate}'
```

---

## Recommendations

### For Development/Testing
- **Use Option 1** (PolicyException) - Fastest to implement

### For Production
- **Use Option 2 or 3** (Internal Registry) - Best practices:
  1. Mirror images to internal registry
  2. Scan images for vulnerabilities
  3. Use specific version tags (not `latest`)
  4. Document image provenance

### For Compliance Requirements
- **Use Option 3** (Automated Mirror) with:
  - Image scanning (Trivy, Clair, etc.)
  - Signed images (Cosign, Notary)
  - Audit trail of image usage
  - Automated vulnerability patching

---

## Additional Resources

- [Kyverno PolicyExceptions](https://kyverno.io/docs/writing-policies/exceptions/)
- [Harbor Proxy Cache](https://goharbor.io/docs/latest/administration/configure-proxy-cache/)
- [Artifactory Remote Repositories](https://www.jfrog.com/confluence/display/JFROG/Remote+Repositories)
- [Wazuh Docker Images](https://hub.docker.com/u/wazuh)

---

## Support

If you continue to experience issues:

1. Check your organization's container registry policies
2. Contact your cluster administrator about approved registries
3. Review the Kyverno policy configuration
4. Open an issue: https://github.com/johnybradshaw/akamai-wazuh/issues
