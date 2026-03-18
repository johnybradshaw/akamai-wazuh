# CLAUDE.md — kubernetes Module

## Module Purpose

Contains all Kubernetes manifests, Kustomize overlays, and deployment scripts for the Wazuh SIEM platform on LKE.

## Key Files

| File | Description |
|------|-------------|
| `kustomization.yml` | Main Kustomize config — image tags, replicas, resource references |
| `production-overlay/` | Production customisations (resources, ingress, load balancers) |
| `overlays/production/` | Alternative overlay directory (mirrors production-overlay) |
| `wazuh-policy-exception.yaml` | Policy exception manifest for Wazuh pods |
| `scripts/generate-credentials.sh` | Generates secure random passwords and bcrypt hashes |
| `scripts/verify-deployment.sh` | Validates deployment health (pods, services, DNS, TLS) |
| `scripts/install-prerequisites.sh` | Installs nginx-ingress, cert-manager, ExternalDNS via Helm |

## Dependencies

### Internal
- Clones `wazuh/wazuh-kubernetes` repo at deploy time (gitignored)

### External
- `kubectl`, `helm` (v3.x), `docker` (for bcrypt hashing), `jq`

## Conventions

- Two overlay directories exist (`production-overlay/` and `overlays/production/`) — keep them in sync when editing
- Image versions are controlled via `newTag` in kustomization files
- Resource limits are defined in per-component `*-resources.yaml` files
- Scripts follow project bash conventions (`set -euo pipefail`, colour-coded logging)
