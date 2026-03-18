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
├── kubernetes/                  # Kubernetes manifests
│   ├── kustomization.yml        # Main kustomize config
│   ├── wazuh-kubernetes/        # Cloned Wazuh K8s repo (gitignored)
│   ├── wazuh-policy-exception.yaml  # Policy exception manifest
│   ├── production-overlay/      # Production customizations
│   │   ├── kustomization.yml    # Overlay config
│   │   ├── ingress.yaml         # Dashboard ingress
│   │   ├── manager-loadbalancers.yaml
│   │   ├── *-resources.yaml     # Resource limits
│   │   ├── service-patches.yaml
│   │   └── storage-class-patch.yaml
│   ├── overlays/production/     # Alternative overlay (mirrors production-overlay)
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
│   │   └── 001-use-adr-format.md
│   ├── runbooks/                # Operational runbooks
│   ├── HARBOR-AUTHENTICATION.md
│   ├── HARBOR-PROXY-SETUP.md
│   ├── REGISTRY-POLICY.md
│   └── TROUBLESHOOTING-INDEXER-SSL.md
├── tools/                       # Utility tooling
│   ├── scripts/                 # Automation scripts
│   └── prompts/                 # Reusable prompt templates
└── .claude/                     # Claude Code configuration
    ├── settings.json            # Permissions and hooks
    └── skills/                  # Custom skill definitions
        ├── code-review/
        ├── deploy/
        └── release/
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
1. Configuration validation
2. Clone Wazuh Kubernetes repository
3. Generate TLS certificates
4. Install infrastructure prerequisites
5. Generate secure credentials
6. Apply Kustomize configuration
7. Wait for deployment readiness
8. Display access information

### Dry Run Mode

```bash
./deploy.sh --dry-run  # Validate without deploying
```

## Code Conventions

### Bash Script Standards

- All scripts use `set -euo pipefail` for strict error handling
- Color-coded logging functions: `log_info`, `log_success`, `log_warning`, `log_error` (see any script for implementation)
- Consistent argument parsing with `--help` support
- New scripts should follow the same structure: header comment, `set -euo pipefail`, color/logging setup, argument parsing, numbered steps, success output

## Kustomize Configuration

### Image Version Management

Images are managed via `newTag` in kustomization files. **Note:** There are two version references in this repo:
- `WAZUH_VERSION` in `config.env` / `deploy.sh` — controls which git branch of the Wazuh K8s repo to clone (currently `v4.9.2`)
- `newTag` in `kubernetes/kustomization.yml` — controls the container image tags (currently `4.14.1` in main kustomization, `4.9.2` in production overlays)

These may intentionally differ. When updating versions, check both.

### Resource and Replica Configuration

- Resource limits: `kubernetes/production-overlay/*-resources.yaml` (one per component)
- Replica counts: configured in `kubernetes/kustomization.yml` under `replicas:`

## Security Considerations

### Sensitive Files (gitignored)

- `config.env` - Contains API tokens
- `kubernetes/production-overlay/.credentials` - Generated passwords
- `kubernetes/production-overlay/internal_users.yml` - Hashed passwords
- `**/vm-list.txt` - Server hostnames
- `kubernetes/wazuh-kubernetes/` - Cloned repository with certs

### Credential Management

- Passwords are generated with `openssl rand -base64 32`
- Bcrypt hashes generated via Docker httpd image
- Credentials file has `chmod 600` permissions

### Default Credentials Warning

The base Wazuh Kubernetes repo uses default credentials:
- Username: `admin`
- Password: `SecretPassword`

**These must be changed immediately after deployment.**

## Common Tasks

### Update Wazuh Version

1. Edit `kubernetes/kustomization.yml`
2. Update `newTag` for all three images
3. Apply: `kubectl apply -k kubernetes/`

### Change Image Registry

Use the update-registry script:
```bash
./scripts/update-registry.sh harbor.company.com/wazuh 4.14.1
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
| `DOMAIN` | Root domain for DNS |
| `LINODE_API_TOKEN` | Linode API token |
| `LETSENCRYPT_EMAIL` | Email for certificates |

### Optional (config.env)

| Variable | Default | Description |
|----------|---------|-------------|
| `WAZUH_NAMESPACE` | `wazuh` | Kubernetes namespace |
| `WAZUH_VERSION` | `v4.9.2` | Wazuh version tag |
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
- `*.pem`, `*.key`, `*.crt` (certificates)
- `kubernetes/wazuh-kubernetes/` (cloned during deployment)
- `*.log` files

## Additional Resources

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Wazuh Kubernetes Guide](https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/)
- [Linode LKE Docs](https://www.linode.com/docs/kubernetes/)
- [Kustomize Reference](https://kubectl.docs.kubernetes.io/references/kustomize/)
