# CLAUDE.md — kubernetes Module

## Module Purpose

Contains all Kubernetes manifests, Kustomize overlays, and deployment scripts for the Wazuh SIEM platform on LKE.

## Key Files

| File | Description |
|------|-------------|
| `kustomization.yml` | Main Kustomize config — the **active** deploy target (`kubectl apply -k kubernetes/`). Image tags, replicas, resource references, cert/config generators |
| `wazuh-kubernetes/` | Upstream base manifests — **git submodule**, pinned via `.gitmodules` to branch `4.14.6` |
| `production-overlay/` | Production customisations (resources, ingress, load balancers). Single source of truth |
| `wazuh-policy-exception.yaml` | Policy exception manifest for Wazuh pods |
| `scripts/generate-credentials.sh` | Generates secure random passwords and bcrypt hashes |
| `scripts/verify-deployment.sh` | Validates deployment health (pods, services, DNS, TLS) |
| `scripts/install-prerequisites.sh` | Installs nginx-ingress, cert-manager, ExternalDNS via Helm |

## Dependencies

### Internal
- `wazuh/wazuh-kubernetes` base manifests vendored as the `wazuh-kubernetes` git submodule (pinned; initialised with `git submodule update --init --recursive`)

### External
- `kubectl`, `helm` (v3.x, akamai profile only), `docker` (for bcrypt hashing), `jq`

## Conventions

- `production-overlay/` is the single source of truth (the old duplicate `overlays/production/` has been removed)
- The active kustomization MUST stay at `kubernetes/` so its `secretGenerator`/`configMapGenerator` can read cert/config files inside the `wazuh-kubernetes/` submodule (kustomize's default load restrictor blocks file refs outside the kustomization root)
- Image versions are controlled via `newTag` in kustomization files (currently `4.14.5`); the base manifests version is the submodule pin (`4.14.6`)
- Cloud-specific values are parameterised with `${DOMAIN}`, `${STORAGE_PROVISIONER}`, `${INGRESS_CLASS}`, `${CLUSTER_ISSUER}` and substituted by `deploy.sh` (defaults reproduce LKE behaviour)
- The cert-manager `Certificate` is intentionally NOT a standalone resource (ingress-shim creates it), so manifests apply cleanly on clusters without cert-manager
- Resource limits are defined in per-component `*-resources.yaml` files
- Scripts follow project bash conventions (`set -euo pipefail`, colour-coded logging)
