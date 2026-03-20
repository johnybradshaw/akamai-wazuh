# Architecture Overview — akamai-wazuh

## Context

This system provides a production-ready deployment of Wazuh SIEM on Akamai Cloud Computing (Linode Kubernetes Engine). It serves security teams who need centralised threat detection, log analysis, and compliance monitoring across their infrastructure.

## High-Level Design

```
                    ┌─────────────────────────────────────┐
                    │        Linode Kubernetes Engine      │
                    │                                     │
  Agents ──────────►│  ┌─────────────┐  ┌──────────────┐ │
  (1514/1515)       │  │   Manager    │  │   Manager    │ │
                    │  │   Master     │──│   Workers    │ │
                    │  └──────┬───┬──┘  └──────────────┘ │
                    │         │   │                       │
                    │  ┌──────▼───▼──────────────┐       │
                    │  │    Indexer Cluster       │       │
                    │  │    (OpenSearch x3)       │       │
                    │  └──────────┬──────────────┘       │
                    │             │                       │
                    │  ┌──────────▼──────────────┐       │
  Users ───────────►│  │    Dashboard (HTTPS)     │       │
  (443)             │  └─────────────────────────┘       │
                    │                                     │
                    │  Infrastructure Services:           │
                    │  • nginx-ingress (HTTPS)            │
                    │  • cert-manager (Let's Encrypt)     │
                    │  • ExternalDNS (Linode DNS)         │
                    └─────────────────────────────────────┘
```

## Component Summary

| Component | Responsibility | Key Technologies |
|-----------|---------------|-----------------|
| `kubernetes/` | K8s manifests, Kustomize overlays, deployment scripts | Kustomize, Helm |
| `scripts/` | Registry management, certificate generation, image mirroring | Bash, OpenSSL |
| `agent-deployment/` | Wazuh agent installation on VMs and K8s clusters | Bash, SSH |

## Data Flow

1. **Agent Registration**: Agents connect to Manager Master via LoadBalancer (port 1515)
2. **Event Ingestion**: Agents send events to Manager Workers via LoadBalancer (port 1514)
3. **Processing**: Manager Workers apply rules, decoders, and generate alerts
4. **Indexing**: Processed events are stored in the Indexer cluster (OpenSearch)
5. **Visualisation**: Dashboard queries the Indexer and presents data via HTTPS ingress

## Cross-Cutting Concerns

### Authentication & Authorisation
- Wazuh internal users managed via `internal_users.yml` with bcrypt-hashed passwords
- Dashboard access via HTTPS with generated credentials
- Agent authentication via registration keys

### TLS/SSL
- Let's Encrypt certificates via cert-manager for dashboard ingress
- Internal cluster communication uses self-signed certificates generated during deployment

### Observability
- Wazuh Manager and Indexer logs available via `kubectl logs`
- Deployment health verified via `verify-deployment.sh`

## Deployment

- **Platform**: Akamai Cloud Computing (Linode Kubernetes Engine)
- **Orchestration**: Single `deploy.sh` script handles end-to-end provisioning
- **Configuration**: Kustomize overlays for production customisation
- **DNS**: Automated via ExternalDNS with Linode DNS provider
