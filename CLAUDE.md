# CLAUDE.md - AI Assistant Guide for akamai-wazuh

This document provides guidance for AI assistants working with the Akamai Cloud Wazuh Quick-Start repository.

## Project Overview

This repository provides a production-ready, turnkey deployment of Wazuh SIEM (Security Information and Event Management) platform on Akamai Cloud Computing (Linode Kubernetes Engine - LKE). It automates the deployment of Wazuh Manager, Indexer, and Dashboard components with supporting infrastructure.

**Tech Stack:**
- Kubernetes (LKE - Linode Kubernetes Engine)
- Kustomize for configuration management
- Bash scripts for automation
- Helm for infrastructure components (nginx-ingress, cert-manager, ExternalDNS)
- Docker for credential generation

## Repository Structure

```
akamai-wazuh/
├── deploy.sh                    # Main deployment script
├── config.env.example           # Configuration template
├── README.md                    # User documentation
├── REGISTRY-QUICK-FIX.md        # Registry troubleshooting guide
├── .github/workflows/           # CI/CD
│   ├── claude.yml               # Claude Code workflow
│   └── claude-code-review.yml   # Claude Code PR review
├── agent-deployment/            # Agent deployment scripts
│   ├── deploy-agent.sh          # Single VM agent deployment
│   ├── deploy-k8s-agent.sh      # Kubernetes DaemonSet deployment
│   ├── deploy-agents-bulk.sh    # Bulk VM deployment
│   ├── vm-list.txt.example      # Example VM list
│   └── README.md                # Agent deployment docs
├── .gitmodules                  # Pins the wazuh-kubernetes submodule (branch 4.14.6)
├── kubernetes/                  # Kubernetes manifests
│   ├── kustomization.yml        # Main kustomize config (active deploy target)
│   ├── wazuh-kubernetes/        # Wazuh K8s base manifests (git submodule, pinned)
│   ├── wazuh-policy-exception.yaml  # Policy exception manifest
│   ├── production-overlay/      # Production customizations (single source of truth)
│   │   ├── kustomization.yml    # Overlay config
│   │   ├── ingress.yaml         # Dashboard ingress
│   │   ├── manager-loadbalancers.yaml
│   │   ├── *-resources.yaml     # Resource limits
│   │   ├── service-patches.yaml
│   │   └── storage-class-patch.yaml
│   └── scripts/
│       ├── generate-credentials.sh
│       ├── verify-deployment.sh
│       └── install-prerequisites.sh
├── scripts/                     # Utility scripts
│   ├── update-registry.sh       # Registry configuration
│   ├── mirror-images.sh         # Image mirroring
│   ├── setup-harbor-credentials.sh
│   ├── generate-indexer-certs-with-sans.sh  # Indexer cert generation
│   ├── init-security.sh         # Security initialisation
│   └── regenerate-certs.sh      # Certificate regeneration
├── docs/                        # Additional documentation
│   ├── architecture.md          # High-level architecture overview
│   ├── decisions/               # Architecture Decision Records
│   │   ├── 001-use-adr-format.md
│   │   ├── 002-vendor-wazuh-kubernetes-as-submodule.md
│   │   └── 003-generate-and-wire-credentials.md
│   ├── runbooks/                # Operational runbooks
│   ├── EXISTING-CLUSTER.md      # Bring-your-own-cluster / submodule guide
│   ├── HARBOR-AUTHENTICATION.md
│   ├── HARBOR-PROXY-SETUP.md
│   ├── REGISTRY-POLICY.md
│   └── TROUBLESHOOTING-INDEXER-SSL.md
├── tools/                       # Utility tooling
│   ├── scripts/                 # Automation scripts
│   └── prompts/                 # Reusable prompt templates
└── .claude/                     # Claude Code configuration
    ├── settings.json            # Permissions, hooks (shellcheck, sensitive file blocking)
    ├── agents/                  # Subagent definitions
    │   └── security-reviewer.md # Security review subagent
    └── skills/                  # Custom skill definitions
        ├── code-review/
        ├── deploy/
        ├── release/
        └── kustomize-validate/  # Submodule pin, version consistency, build checks
```

Each major directory (`kubernetes/`, `scripts/`, `agent-deployment/`) has its own `CLAUDE.md` with module-specific context.

## Key Files and Their Purposes

### Main Entry Points

| File | Purpose |
|------|---------|
| `deploy.sh` | Main deployment orchestration script |
| `config.env.example` | Template for required configuration |
| `kubernetes/kustomization.yml` | Main Kustomize configuration |

### Agent Deployment

| Script | Purpose |
|--------|---------|
| `agent-deployment/deploy-agent.sh` | Deploy agent to single VM via SSH |
| `agent-deployment/deploy-k8s-agent.sh` | Deploy agents as K8s DaemonSet |
| `agent-deployment/deploy-agents-bulk.sh` | Bulk VM deployment from CSV |

### Kubernetes Scripts

| Script | Purpose |
|--------|---------|
| `kubernetes/scripts/generate-credentials.sh` | Generate secure random passwords |
| `kubernetes/scripts/verify-deployment.sh` | Verify deployment health |
| `kubernetes/scripts/install-prerequisites.sh` | Install nginx, cert-manager, ExternalDNS |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| `scripts/update-registry.sh` | Update image registry in kustomization |
| `scripts/mirror-images.sh` | Mirror images to private registry |
| `scripts/setup-harbor-credentials.sh` | Configure Harbor authentication |
| `scripts/generate-indexer-certs-with-sans.sh` | Generate indexer certs with SANs |
| `scripts/init-security.sh` | Initialise Wazuh security |
| `scripts/regenerate-certs.sh` | Regenerate TLS certificates |

## Development Workflow

### Prerequisites for Local Development

- `kubectl` - Kubernetes CLI
- `helm` - Kubernetes package manager (v3.x)
- `docker` - For password hash generation
- `jq` - JSON processor
- `git` - Version control

### Configuration

1. Copy `config.env.example` to `config.env`
2. Set required variables:
   - `DOMAIN` - Root domain (DNS must be on Linode)
   - `LINODE_API_TOKEN` - API token with Domains Read/Write
   - `LETSENCRYPT_EMAIL` - Email for certificates

### Deployment Process

The `deploy.sh` script performs:
1. Configuration validation (resolves the deployment profile: `akamai` or `existing-cluster`)
2. Initialise the wazuh-kubernetes base manifests (git submodule)
3. Generate TLS certificates
4. Install infrastructure prerequisites (akamai profile only)
5. Generate secure credentials
6. Substitute overlay placeholders and apply Kustomize configuration
7. Wait for deployment readiness
8. Display access information

### Deployment Profiles

- `akamai` (default): turnkey LKE deployment — installs nginx-ingress, cert-manager, ExternalDNS; verifies Linode DNS; provisions NodeBalancers.
- `existing-cluster`: bring-your-own infrastructure for any existing cluster — skips the Akamai/Linode provisioning. Selected via `DEPLOY_PROFILE` or `--existing-cluster`. See `docs/EXISTING-CLUSTER.md`.

### Dry Run Mode

```bash
./deploy.sh --dry-run  # Validate without deploying
```

## Code Conventions

### Bash Script Standards

- All scripts use `set -euo pipefail` for strict error handling
- Colour-coded logging functions: `log_info`, `log_success`, `log_warning`, `log_error` (see any script for implementation)
- Consistent argument parsing with `--help` support
- New scripts should follow the same structure: header comment, `set -euo pipefail`, color/logging setup, argument parsing, numbered steps, success output

## Kustomize Configuration

### Image Version Management

Images are managed via `newTag` in kustomization files. **Note:** There are two version references in this repo, decoupled on purpose:
- `newTag` in `kubernetes/kustomization.yml` and `kubernetes/production-overlay/kustomization.yml` — the container image tags actually deployed (currently `4.14.5`, the latest stable Wazuh release).
- The `kubernetes/wazuh-kubernetes` **git submodule**, pinned in `.gitmodules` to the `4.14.6` branch — the base manifests. Upstream publishes no 4.14 tags, only branches; `4.14.6` is the most mature (`4.14.7`/`main` are alpha).
- `WAZUH_VERSION` in `config.env` / `deploy.sh` (default `4.14.6`) is now only a **fallback clone ref** used when the repo was not checked out with submodules (e.g. a source tarball).

When updating versions, bump the image `newTag` in both kustomization files and, if needed, move the submodule pointer (see "Update Wazuh Version"). The `kustomize-validate` skill checks consistency.

### Resource and Replica Configuration

- Resource limits: `kubernetes/production-overlay/*-resources.yaml` (one per component)
- Replica counts: configured in `kubernetes/kustomization.yml` under `replicas:`

## Security Considerations

### Sensitive Files (gitignored)

- `config.env` - Contains API tokens
- `kubernetes/production-overlay/.credentials` - Generated passwords
- `kubernetes/production-overlay/internal_users.yml` - Hashed passwords
- `**/vm-list.txt` - Server hostnames
- Certificates generated inside the `kubernetes/wazuh-kubernetes/` submodule
  (`*.pem`, `*.key`, `*.crt`). The submodule **pointer** is tracked; its
  working-tree certs are not.

### Credential Management

- Passwords are generated with `openssl rand -base64 32`
- Bcrypt hashes generated via Docker httpd image
- Credentials file has `chmod 600` permissions

### Credentials are generated and wired in

The base Wazuh Kubernetes repo ships default credentials (`admin` /
`SecretPassword`, cluster key `123a45...`, etc.). `deploy.sh` does **not** use
them: `kubernetes/scripts/generate-credentials.sh` generates strong random
values and wires them into the deployment via:

- the generated `production-overlay/internal_users.yml` (admin/kibanaserver
  bcrypt hashes), consumed by the `indexer-conf` configMapGenerator, and
- strategic-merge patches `production-overlay/*.patch.yaml` overriding the
  `indexer-cred`, `dashboard-cred`, `wazuh-api-cred`, `wazuh-authd-pass` and
  `wazuh-cluster-key` secrets.

`securityadmin.sh` (deploy.sh) loads the hashes into the indexer security index.
All generated files are gitignored, so **run `generate-credentials.sh` (or
deploy.sh) before `kubectl apply -k kubernetes/`** — the kustomization references
them. The admin password is printed at the end of the run and saved to
`production-overlay/.credentials` (chmod 600). Rotating the admin password
periodically is still recommended.

## Common Tasks

### Update Wazuh Version

1. Edit `kubernetes/kustomization.yml` (and `kubernetes/production-overlay/kustomization.yml`)
2. Update `newTag` for all three images to the new stable release
3. (If needed) move the base manifests submodule:
   ```bash
   git -C kubernetes/wazuh-kubernetes fetch origin
   git -C kubernetes/wazuh-kubernetes checkout <branch-or-commit>
   git add kubernetes/wazuh-kubernetes
   ```
4. Apply: `kubectl apply -k kubernetes/`

### Change Image Registry

Use the update-registry script:
```bash
./scripts/update-registry.sh harbor.company.com/wazuh 4.14.5
# Or with Harbor proxy
./scripts/update-registry.sh harbor.company.com/dockerhub-proxy/wazuh --proxy
```

### Scale Workers

Edit `kubernetes/kustomization.yml`:
```yaml
replicas:
  - name: wazuh-manager-worker
    count: 4  # Change from 2
```

### Verify Deployment

```bash
./kubernetes/scripts/verify-deployment.sh
# Or with namespace
./kubernetes/scripts/verify-deployment.sh wazuh
```

### Deploy Agent to VM

```bash
./agent-deployment/deploy-agent.sh hostname.example.com agent-name agent-group
```

## Testing and Validation

```bash
# Run full deployment verification
./kubernetes/scripts/verify-deployment.sh [namespace]

# Manual checks
kubectl get pods -n wazuh
kubectl get svc -n wazuh
kubectl logs -n wazuh wazuh-manager-master-0
kubectl exec -n wazuh wazuh-manager-master-0 -- /var/ossec/bin/agent_control -l
```

## Environment Variables

### Required (config.env)

| Variable | Description |
|----------|-------------|
| `DOMAIN` | Root domain for DNS (always required) |
| `LINODE_API_TOKEN` | Linode API token (akamai profile / `MANAGE_DNS=true`) |
| `LETSENCRYPT_EMAIL` | Email for certificates (akamai profile only) |

### Optional (config.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `DEPLOY_PROFILE` | `akamai` | `akamai` or `existing-cluster` |
| `WAZUH_NAMESPACE` | `wazuh` | Kubernetes namespace |
| `WAZUH_VERSION` | `4.14.6` | Fallback wazuh-kubernetes clone ref (submodule normally used) |
| `STORAGE_PROVISIONER` | `linodebs.csi.linode.com` | CSI provisioner for `wazuh-storage` |
| `INGRESS_CLASS` | `nginx` | Ingress class for the dashboard |
| `CLUSTER_ISSUER` | `letsencrypt-prod` | cert-manager ClusterIssuer |
| `MANAGE_DNS` | profile-based | Manage Linode DNS (`true` for akamai) |
| `MANAGE_TLS` | profile-based | Wait for cert-manager TLS (`true` for akamai) |
| `DEPLOYMENT_TIMEOUT` | `600` | Seconds to wait |
| `WORKER_REPLICAS` | `2` | Manager worker count |
| `INDEXER_REPLICAS` | `3` | Indexer replica count |

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full architecture overview and data flow diagram.

**Key components:** Manager Master (registration, API) | Manager Workers (event processing) | Indexer (OpenSearch x3) | Dashboard (web UI)

**Infrastructure:** nginx-ingress (HTTPS) | cert-manager (Let's Encrypt) | ExternalDNS (Linode DNS)

**Load Balancers:** `wazuh-manager-lb` (port 1515, registration) | `wazuh-workers-lb` (port 1514, events) | nginx-ingress-lb (HTTPS dashboard)

Architecture Decision Records are stored in [docs/decisions/](docs/decisions/).

## Troubleshooting Tips

### Common Issues

1. **Pods not starting**: Check node resources with `kubectl describe nodes`
2. **DNS not resolving**: Wait 2-5 minutes for propagation, check ExternalDNS logs
3. **Certificate not issued**: Check cert-manager logs and certificate status
4. **LoadBalancer pending**: Verify LKE cluster has capacity
5. **Agent not connecting**: Check ports 1514/1515 are open, verify DNS

### Key Logs

- Dashboard: `kubectl logs -n wazuh -l app=wazuh-dashboard`
- Manager: `kubectl logs -n wazuh wazuh-manager-master-0`
- Indexer: `kubectl logs -n wazuh wazuh-indexer-0`
- ExternalDNS: `kubectl logs -n kube-system -l app=external-dns`
- cert-manager: `kubectl logs -n cert-manager -l app=cert-manager`
- See also: `docs/TROUBLESHOOTING-INDEXER-SSL.md` for indexer SSL issues

## Git Workflow

### Branch Naming

- Feature branches: `feature/<description>`
- Bug fixes: `fix/<description>`
- Claude branches: `claude/<description>-<session-id>`

### Files Never to Commit

- `config.env` (contains secrets)
- `.credentials` files
- `*.pem`, `*.key`, `*.crt` (certificates, including those generated inside the
  `kubernetes/wazuh-kubernetes/` submodule)
- `*.log` files

> Note: `kubernetes/wazuh-kubernetes/` is a git submodule — its **pointer** is
> committed (do not gitignore it), but generated certs inside it are not.

## Additional Resources

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Wazuh Kubernetes Guide](https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/)
- [Linode LKE Docs](https://www.linode.com/docs/kubernetes/)
- [Kustomize Reference](https://kubectl.docs.kubernetes.io/references/kustomize/)
