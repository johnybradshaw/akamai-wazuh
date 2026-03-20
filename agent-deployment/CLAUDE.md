# CLAUDE.md — agent-deployment Module

## Module Purpose

Scripts for deploying Wazuh agents to monitored infrastructure — individual VMs, bulk VM fleets, and Kubernetes clusters.

## Key Files

| File | Description |
|------|-------------|
| `deploy-agent.sh` | Deploy a Wazuh agent to a single VM via SSH |
| `deploy-k8s-agent.sh` | Deploy agents as a Kubernetes DaemonSet |
| `deploy-agents-bulk.sh` | Bulk deployment to multiple VMs from a CSV list |
| `vm-list.txt.example` | Example format for bulk deployment target list |
| `README.md` | Agent deployment documentation |

## Dependencies

### External
- SSH access to target VMs (for VM deployments)
- `kubectl` (for K8s DaemonSet deployment)
- Running Wazuh Manager with accessible registration endpoint (port 1515)

## Conventions

- `vm-list.txt` is gitignored — never commit actual server lists
- Agent scripts expect the Manager address to be resolvable via DNS
- Bulk deployment logs are written to `agent-deployment/logs/` (gitignored)
