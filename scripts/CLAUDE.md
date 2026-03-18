# CLAUDE.md — scripts Module

## Module Purpose

Utility scripts for registry management, certificate generation, image mirroring, and security initialisation.

## Key Files

| File | Description |
|------|-------------|
| `update-registry.sh` | Updates image registry references in kustomization files |
| `mirror-images.sh` | Mirrors Wazuh images to a private registry (e.g., Harbor) |
| `setup-harbor-credentials.sh` | Configures Harbor authentication for K8s image pulls |
| `generate-indexer-certs-with-sans.sh` | Generates indexer TLS certificates with Subject Alternative Names |
| `init-security.sh` | Initialises Wazuh security configuration |
| `regenerate-certs.sh` | Regenerates TLS certificates for the deployment |

## Dependencies

### External
- `openssl` — certificate generation
- `docker` — image mirroring
- `kubectl` — cluster interaction

## Conventions

- All scripts follow project bash standards (`set -euo pipefail`, colour-coded logging)
- Registry scripts support both direct and proxy (Harbor) configurations
- Certificate scripts handle SAN generation for indexer nodes
