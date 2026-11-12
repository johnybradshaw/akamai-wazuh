---
name: kustomize-validate
description: "Validate the Kustomize config: submodule pin, image-version consistency across kustomization files, and a clean build."
---

# kustomize-validate

Validate the consistency of Kustomize configuration across the repository.

## Checks

Perform these validation checks and report results:

### 1. Submodule Pin Check
Confirm `kubernetes/wazuh-kubernetes` is a properly pinned submodule:
- `.gitmodules` contains the `kubernetes/wazuh-kubernetes` entry with a `branch`
- The submodule is initialised (`kubernetes/wazuh-kubernetes/wazuh/kustomization.yml` exists)
- Report the pinned branch and current commit (`git -C kubernetes/wazuh-kubernetes log --oneline -1`)

### 2. Image Version Consistency
Extract `newTag` values from all kustomization files:
- `kubernetes/kustomization.yml`
- `kubernetes/production-overlay/kustomization.yml`

Report if image tags differ (they should all match the latest stable release, currently `4.14.10`).

### 3. Version Cross-Reference
Two versions are intentionally decoupled — flag anything unexpected:
- Image `newTag` (container images, e.g. `4.14.10`, the latest GA release)
- Submodule pin: the commit recorded for `kubernetes/wazuh-kubernetes` (base manifests; currently `97bc03d9fa`, tag `v4.14.10`). `.gitmodules` must carry no `branch` key.
- `WAZUH_K8S_COMMIT` in `config.env.example`, `deploy.sh` and `scripts/regenerate-certs.sh` is only a fallback clone target; all three must equal the submodule commit.

### 4. Kustomize Syntax Validation
Run `kubectl kustomize kubernetes/ 2>&1` (or `kustomize build kubernetes/`) and report errors. Expected, non-failing notes:
- A `commonLabels is deprecated` warning
- Unresolved `${DOMAIN}` / `${STORAGE_PROVISIONER}` / `${INGRESS_CLASS}` / `${CLUSTER_ISSUER}` placeholders (substituted by `deploy.sh` at deploy time)
- The build needs the submodule initialised, certs generated (the `secretGenerator` reads cert files), AND credentials generated (`generate-credentials.sh` writes `production-overlay/internal_users.yml` + `*.patch.yaml`, referenced by the configMapGenerator and `patches:`); otherwise a missing-files error is expected.

## Output Format

```
## Kustomize Validation Report

### Submodule Pin: PASS/FAIL
[branch + commit]

### Image Versions: PASS/WARN
[version table]

### Version Cross-Reference: PASS/WARN
[image tag vs submodule branch vs WAZUH_VERSION]

### Syntax Check: PASS/FAIL
[errors if any]
```
