---
name: kustomize-validate
description: "Validate Kustomize overlays are in sync and image versions are consistent across all kustomization files."
---

# kustomize-validate

Validate the consistency of Kustomize configuration across the repository.

## Checks

Perform these validation checks and report results:

### 1. Overlay Sync Check
Compare `kubernetes/production-overlay/` and `kubernetes/overlays/production/` directories:
- List files present in one but not the other
- Diff files that exist in both to find discrepancies
- Flag any structural differences

### 2. Image Version Consistency
Extract `newTag` values from all kustomization files:
- `kubernetes/kustomization.yml`
- `kubernetes/production-overlay/kustomization.yml`
- `kubernetes/overlays/production/kustomization.yml`

Report if image tags differ between files and whether the difference is intentional.

### 3. WAZUH_VERSION Cross-Reference
Compare the `WAZUH_VERSION` value in `config.env.example` and `deploy.sh` with the `newTag` values in kustomization files. Note that these serve different purposes (git branch vs container image tag) but flag if they appear inconsistent.

### 4. Kustomize Syntax Validation
Run `kubectl kustomize kubernetes/ --enable-helm 2>&1` and report any errors other than the expected missing `wazuh-kubernetes/` directory.

## Output Format

```
## Kustomize Validation Report

### Overlay Sync: PASS/FAIL
[details]

### Image Versions: PASS/WARN
[version table]

### WAZUH_VERSION: PASS/WARN
[cross-reference details]

### Syntax Check: PASS/FAIL
[errors if any]
```
