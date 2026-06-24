# Akamai Cloud Wazuh SIEM Quick-Start

> Production-ready, turnkey deployment of Wazuh Security Information and Event Management (SIEM) platform on Akamai Cloud Computing (Linode Kubernetes Engine).

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Wazuh Version](https://img.shields.io/badge/Wazuh-4.14.5-green.svg)](https://wazuh.com/)
[![Platform](https://img.shields.io/badge/Platform-Akamai%20Cloud%20%7C%20any%20K8s-orange.svg)](https://www.linode.com/products/kubernetes/)

## ⚠️ Disclaimer

**This is an independent, community-driven project and is NOT officially affiliated with, endorsed by, or supported by Wazuh, Inc., Akamai Technologies, Inc., or Linode LLC.**

- All trademarks, service marks, trade names, product names, and logos are the property of their respective owners
- This project respects all applicable patents and intellectual property rights
- **Use at your own risk and discretion** - This software is provided "as is" without warranty of any kind
- The authors and contributors assume no liability for any damages or issues arising from the use of this project
- Always review and test configurations in a non-production environment before deploying to production
- For official Wazuh documentation and support, visit [wazuh.com](https://wazuh.com/)
- For official Akamai Cloud documentation, visit [linode.com/docs](https://www.linode.com/docs/)

By using this project, you acknowledge that you have read this disclaimer and agree to use the software at your own risk.

## Overview

This quick-start package deploys a complete, enterprise-ready Wazuh SIEM platform on Akamai Cloud Computing in under 10 minutes. It includes:

- **Wazuh Manager** - Security event processing and agent management
- **Wazuh Indexer** - OpenSearch-based data storage and analytics
- **Wazuh Dashboard** - Web-based security monitoring interface
- **Automated Infrastructure** - DNS, TLS certificates, load balancing
- **Agent Deployment Tools** - Automated agent installation scripts
- **Security by Default** - Random passwords, encrypted communications

### Why Wazuh?

Wazuh is an open-source security platform providing:
- Intrusion detection (HIDS/NIDS)
- Log analysis and correlation
- File integrity monitoring
- Vulnerability detection
- Compliance automation (PCI-DSS, GDPR, HIPAA)
- Cloud workload protection
- Threat intelligence integration

### Why Akamai Cloud Computing?

- **Performance** - Global edge network with low latency
- **Cost-Effective** - Transparent, predictable pricing (~$86/month)
- **Simple** - Managed Kubernetes (LKE) with no control plane costs
- **Scalable** - Easily scale resources as your needs grow
- **Reliable** - 99.99% uptime SLA

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Akamai Cloud (LKE Cluster)                   │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                   Wazuh Components                        │ │
│  │                                                           │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │   Manager    │  │   Workers    │  │   Indexer    │  │ │
│  │  │   Master     │  │   (x2)       │  │   (x3)       │  │ │
│  │  │              │  │              │  │              │  │ │
│  │  │ Registration │  │ Event        │  │ Data         │  │ │
│  │  │ API          │  │ Processing   │  │ Storage      │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │ │
│  │                                                           │ │
│  │                  ┌──────────────┐                        │ │
│  │                  │  Dashboard   │                        │ │
│  │                  │  (Web UI)    │                        │ │
│  │                  └──────────────┘                        │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              Infrastructure Services                       │ │
│  │                                                           │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │ │
│  │  │ nginx-ingress│  │ cert-manager │  │ ExternalDNS  │  │ │
│  │  │ (HTTPS)      │  │ (Let's       │  │ (Automatic   │  │ │
│  │  │              │  │  Encrypt)    │  │  DNS)        │  │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                  Load Balancers                           │ │
│  │                                                           │ │
│  │  wazuh-manager-lb    → wazuh-registration.domain:1515    │ │
│  │  wazuh-workers-lb    → wazuh-manager.domain:1514         │ │
│  │  nginx-ingress-lb    → wazuh.domain:443                  │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
         ↑                    ↑                      ↑
         │                    │                      │
    Dashboard              Agents                 Agents
    Browser              (Events)            (Registration)
```

## Quick Start

### Prerequisites

Before you begin, ensure you have:

#### 1. Akamai Cloud Resources
- **LKE Cluster**: 3+ nodes, 4GB RAM minimum per node
  - Create at: [cloud.linode.com/kubernetes/create](https://cloud.linode.com/kubernetes/create)
  - Recommended: 3x Linode 4GB ($36/month)
- **Domain**: DNS hosted on Linode/Akamai
  - Manage at: [cloud.linode.com/domains](https://cloud.linode.com/domains)
- **API Token**: Domains Read/Write permission (only needed for the `akamai`
  profile / `MANAGE_DNS=true`)
  - Create in the UI: [cloud.linode.com/profile/tokens](https://cloud.linode.com/profile/tokens), **or**
  - Create it from the CLI with a label, scope and expiry using
    [`linode-cli`](https://www.linode.com/docs/products/tools/cli/get-started/):

    ```bash
    # Wazuh only needs the Domains scope (DNS verification + ExternalDNS).
    # Pick the date expression for your OS:
    EXPIRY="$(date -u -d '+365 days' '+%Y-%m-%dT%H:%M:%S')"   # Linux / GNU date
    # EXPIRY="$(date -u -v+365d '+%Y-%m-%dT%H:%M:%S')"        # macOS / BSD date

    linode-cli profile token-create \
      --label "wazuh" \
      --scopes 'domains:read_write' \
      --expiry "$EXPIRY" \
      --json | jq -r '.[0].token'
    ```

    Copy the printed token into `LINODE_API_TOKEN` in `config.env`. ExternalDNS
    uses it continuously, so set an expiry you're willing to rotate (or omit
    `--expiry` for a non-expiring token). If you also plan to snapshot the
    indexer to Linode Object Storage, add `,object_storage:read_write` to
    `--scopes`. On macOS pipe to `| pbcopy` to copy it to the clipboard.

#### 2. Local Tools
- **kubectl**: Kubernetes command-line tool
  ```bash
  # Install kubectl
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  ```

- **helm**: Kubernetes package manager (v3.x)
  ```bash
  # Install helm
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ```

- **docker**: Container runtime (for password generation)
  ```bash
  # Install docker
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  sudo systemctl enable docker
  sudo systemctl start docker
  ```

- **jq**: JSON processor
  ```bash
  # Install jq
  sudo apt-get install -y jq  # Debian/Ubuntu
  sudo yum install -y jq      # RHEL/CentOS
  brew install jq             # macOS
  ```

#### 3. Kubectl Configuration
Download your LKE cluster's kubeconfig:
```bash
# From Linode Cloud Manager -> Kubernetes -> Your Cluster -> Download kubeconfig
export KUBECONFIG=/path/to/kubeconfig.yaml

# Verify connectivity
kubectl get nodes
```

### Installation

#### Step 1: Clone Repository

The Wazuh base manifests are vendored as a **git submodule**, so clone with
`--recurse-submodules`:

```bash
git clone --recurse-submodules https://github.com/johnybradshaw/akamai-wazuh.git
cd akamai-wazuh
```

Already cloned without `--recurse-submodules`? Initialise the submodule:

```bash
git submodule update --init --recursive
```

> `deploy.sh` will also initialise the submodule automatically if it is missing.

#### Step 2: Configure
```bash
# Copy configuration template
cp config.env.example config.env

# Edit configuration
nano config.env
```

Set these required variables:
```bash
DOMAIN="example.com"                      # Your domain (DNS on Linode)
LINODE_API_TOKEN="your-token-here"        # Linode API token
LETSENCRYPT_EMAIL="admin@example.com"     # Email for Let's Encrypt
```

#### Step 3: Deploy
```bash
# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh
```

The deployment takes approximately 5-10 minutes and will:
1. ✓ Validate configuration and prerequisites
2. ✓ Initialise the wazuh-kubernetes base manifests (git submodule)
3. ✓ Generate TLS certificates
4. ✓ Install infrastructure (nginx, cert-manager, ExternalDNS)
5. ✓ Generate secure random passwords
6. ✓ Deploy Wazuh components
7. ✓ Wait for readiness and DNS propagation
8. ✓ Initialize Wazuh Indexer security configuration
9. ✓ Display access credentials

#### Step 4: Access Dashboard

`deploy.sh` generates **strong, unique random credentials** and wires them into
the deployment — the upstream `admin` / `SecretPassword` defaults are **not**
used. The generated admin password is printed at the end of the run and saved
to `kubernetes/production-overlay/.credentials` (chmod 600):

```bash
Dashboard: https://wazuh.example.com
Username:  admin
Password:  <generated — see deploy output / .credentials>

# Retrieve it any time:
grep WAZUH_DASHBOARD_PASSWORD kubernetes/production-overlay/.credentials | cut -d= -f2- | tr -d '"'
```

**What gets generated and applied** (by `kubernetes/scripts/generate-credentials.sh`):

| Credential | Secret / file | Purpose |
|------------|---------------|---------|
| `admin` password | `indexer-cred` + `internal_users.yml` (bcrypt) | Dashboard login, filebeat→indexer |
| `kibanaserver` password | `dashboard-cred` + `internal_users.yml` (bcrypt) | Dashboard→indexer service account |
| Wazuh API password | `wazuh-api-cred` | `wazuh-wui` API user |
| Agent registration password | `wazuh-authd-pass` | Agent enrollment |
| Cluster key | `wazuh-cluster-key` | Manager master/worker cluster auth |

> The plaintext passwords in the secrets are kept consistent with the bcrypt
> hashes in `internal_users.yml`, and `deploy.sh` runs `securityadmin.sh` to load
> them into the indexer security index. It is still good practice to rotate the
> admin password periodically (see [Credential Rotation](#credential-rotation)).

## Deploying to an Existing Cluster (git submodule)

The default `akamai` profile above provisions everything for you on LKE. If you
already run a Kubernetes cluster (LKE, EKS, GKE, AKS, k3s, …) with your own
ingress controller, storage class, TLS and DNS, use the **`existing-cluster`
profile** instead. It deploys only the Wazuh workloads and skips the
Akamai/Linode-specific provisioning (Linode DNS checks, NodeBalancers,
nginx-ingress / cert-manager / ExternalDNS installation).

**Bring-your-own infrastructure you must already have:**

- An **ingress controller** (set `INGRESS_CLASS`, default `nginx`)
- A **storage class** provisioner (set `STORAGE_PROVISIONER`, e.g.
  `ebs.csi.aws.com`, `pd.csi.storage.gke.io`, `disk.csi.azure.com`)
- **TLS**: either cert-manager + a `ClusterIssuer` (set `CLUSTER_ISSUER`) or your
  own `wazuh-dashboard-tls` secret
- **DNS** records for `wazuh.<domain>`, `wazuh-manager.<domain>` and
  `wazuh-registration.<domain>`

### Option A — run deploy.sh with the existing-cluster profile

```bash
git clone --recurse-submodules https://github.com/johnybradshaw/akamai-wazuh.git
cd akamai-wazuh
cp config.env.example config.env

# In config.env set at least:
#   DEPLOY_PROFILE="existing-cluster"
#   DOMAIN="example.com"
#   STORAGE_PROVISIONER="ebs.csi.aws.com"   # match your cluster
#   INGRESS_CLASS="nginx"                    # match your ingress controller
#   CLUSTER_ISSUER="letsencrypt-prod"        # your cert-manager issuer (if any)

./deploy.sh --existing-cluster
```

### Option B — consume this repo as a submodule in your own GitOps repo

Add `akamai-wazuh` as a submodule of your infrastructure repository and pin it
to a tag/commit you control:

```bash
git submodule add https://github.com/johnybradshaw/akamai-wazuh.git vendor/akamai-wazuh
git submodule update --init --recursive   # pulls the nested wazuh-kubernetes submodule
```

Then drive the deployment from your repo (CI/CD, Argo CD, Flux, or a Makefile):

```bash
cd vendor/akamai-wazuh
./deploy.sh --existing-cluster      # reads config.env from this directory
```

See **[docs/EXISTING-CLUSTER.md](docs/EXISTING-CLUSTER.md)** for the full guide,
including raw `kustomize` usage and Argo CD / Flux notes.

## Post-Deployment

### Change Admin Password

**IMPORTANT**: Change the default admin password immediately after first login.

1. Log into dashboard: `https://wazuh.example.com`
2. Click user icon (top right) → "Account settings"
3. Navigate to "Security" → "Change password"
4. Enter current password and new password
5. Click "Save"

### Deploy Agents

Wazuh agents collect security data from your servers and send to the manager.

#### Single Agent Deployment
```bash
cd agent-deployment

# Deploy to a single VM
./deploy-agent.sh web-server-01.example.com

# With custom name and group
./deploy-agent.sh 192.168.1.10 web-01 web-servers
```

#### Bulk Agent Deployment
```bash
# Create VM list file
cp vm-list.txt.example vm-list.txt
nano vm-list.txt

# Format: hostname,agent_name,agent_group
# Example:
# web-server-01.example.com,web-01,web-servers
# 192.168.1.10,web-02,web-servers

# Deploy to all VMs (sequential)
./deploy-agents-bulk.sh vm-list.txt

# Deploy in parallel (5 concurrent)
./deploy-agents-bulk.sh vm-list.txt --parallel 5
```

#### Verify Agents
```bash
# List agents from manager
kubectl exec -n wazuh wazuh-manager-master-0 -- \
  /var/ossec/bin/agent_control -l

# Check agent status on VM
ssh your-vm "sudo systemctl status wazuh-agent"

# View agent logs on VM
ssh your-vm "sudo tail -f /var/ossec/logs/ossec.log"
```

### Verify Deployment

Run the verification script to check deployment health:
```bash
./kubernetes/scripts/verify-deployment.sh
```

This checks:
- ✓ All pods are running
- ✓ StatefulSets and Deployments are ready
- ✓ LoadBalancers have external IPs
- ✓ DNS records are configured
- ✓ TLS certificates are issued
- ✓ Dashboard is accessible
- ✓ Persistent volumes are bound

## Configuration

### Scaling

#### Scale Worker Nodes
```bash
# Edit kustomization.yml
nano kubernetes/kustomization.yml

# Change worker replicas
replicas:
  - name: wazuh-manager-worker
    count: 4  # Increase from 2 to 4

# Apply changes
kubectl apply -k kubernetes/
```

#### Scale Indexer Nodes
```bash
# Edit kustomization.yml
nano kubernetes/kustomization.yml

# Change indexer replicas
replicas:
  - name: wazuh-indexer
    count: 5  # Increase from 3 to 5

# Apply changes
kubectl apply -k kubernetes/
```

### Resource Limits

Edit resource limit files to adjust CPU/memory:
```bash
# Manager Master
nano kubernetes/production-overlay/manager-master-resources.yaml

# Manager Workers
nano kubernetes/production-overlay/manager-worker-resources.yaml

# Indexer
nano kubernetes/production-overlay/indexer-resources.yaml

# Dashboard
nano kubernetes/production-overlay/dashboard-resources.yaml

# Apply changes
kubectl apply -k kubernetes/
```

### Storage

#### Increase Storage Size
```bash
# Edit resource files to change PVC size
nano kubernetes/production-overlay/indexer-resources.yaml

# Change storage size
resources:
  requests:
    storage: 200Gi  # Increase from 100Gi

# For existing PVCs, you must create new StatefulSet
# See: https://kubernetes.io/docs/tasks/run-application/scale-stateful-set/
```

#### Change Storage Class
```bash
# Edit resource files
nano kubernetes/production-overlay/manager-master-resources.yaml

# Change storageClassName
storageClassName: linode-block-storage-retain  # or custom class

# Apply changes
kubectl apply -k kubernetes/
```

## Monitoring and Operations

### View Logs

```bash
# Dashboard logs
kubectl logs -n wazuh -l app=wazuh-dashboard

# Manager master logs
kubectl logs -n wazuh wazuh-manager-master-0

# Manager worker logs
kubectl logs -n wazuh wazuh-manager-worker-0

# Indexer logs
kubectl logs -n wazuh wazuh-indexer-0

# Follow logs in real-time
kubectl logs -n wazuh -f wazuh-manager-master-0
```

### Check Resources

```bash
# Pod status
kubectl get pods -n wazuh

# Service status
kubectl get svc -n wazuh

# Ingress status
kubectl get ingress -n wazuh

# Certificate status
kubectl get certificate -n wazuh

# PVC status
kubectl get pvc -n wazuh

# Node resources
kubectl top nodes

# Pod resources
kubectl top pods -n wazuh
```

### Access Manager Console

```bash
# Shell into manager master
kubectl exec -it -n wazuh wazuh-manager-master-0 -- bash

# Inside container
/var/ossec/bin/agent_control -l      # List agents
/var/ossec/bin/wazuh-control status  # Check services
/var/ossec/bin/manage_agents         # Manage agents
tail -f /var/ossec/logs/ossec.log    # View logs
```

### Backup and Restore

#### Backup Indexer Data
```bash
# Create snapshot repository
kubectl exec -n wazuh wazuh-indexer-0 -- curl -X PUT \
  "https://localhost:9200/_snapshot/backup" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "fs",
    "settings": {
      "location": "/backup"
    }
  }'

# Create snapshot
kubectl exec -n wazuh wazuh-indexer-0 -- curl -X PUT \
  "https://localhost:9200/_snapshot/backup/snapshot_$(date +%Y%m%d)" \
  -H "Content-Type: application/json" \
  -d '{
    "indices": "*",
    "ignore_unavailable": true,
    "include_global_state": false
  }'
```

#### Backup Configuration
```bash
# Backup credentials
cp kubernetes/production-overlay/.credentials backup/

# Backup Kubernetes manifests
kubectl get all -n wazuh -o yaml > backup/wazuh-backup.yaml

# Backup PVC data (requires additional tooling)
# Recommended: Use Velero or similar backup solution
```

### Credential Rotation

```bash
# 1. Regenerate credentials (answer "yes" when prompted to overwrite).
#    This rewrites internal_users.yml + the *.patch.yaml secret patches.
rm -f kubernetes/production-overlay/.credentials \
      kubernetes/production-overlay/internal_users.yml \
      kubernetes/production-overlay/*.patch.yaml
./kubernetes/scripts/generate-credentials.sh kubernetes/production-overlay

# 2. Re-apply: updates the indexer-conf ConfigMap and the credential Secrets
kubectl apply -k kubernetes/

# 3. Load the new admin/kibanaserver hashes into the indexer security index
./scripts/init-security.sh

# 4. Restart the consumers so they pick up the rotated Secrets
kubectl rollout restart -n wazuh \
  statefulset/wazuh-indexer statefulset/wazuh-manager-master \
  statefulset/wazuh-manager-worker deployment/wazuh-dashboard

# New admin password:
grep WAZUH_DASHBOARD_PASSWORD kubernetes/production-overlay/.credentials | cut -d= -f2- | tr -d '"'
```

## Troubleshooting

### Common Issues

#### Pods Not Starting
```bash
# Check pod status
kubectl get pods -n wazuh

# Describe pod for events
kubectl describe pod -n wazuh <pod-name>

# Check logs
kubectl logs -n wazuh <pod-name>

# Check resource availability
kubectl describe nodes
```

#### Indexer SSL/TLS Errors
If the Wazuh indexer fails to start with SSL/TLS errors like `javax.crypto.BadPaddingException` or certificate hostname verification errors like `x509: certificate is valid for X, not Y`, the TLS certificates are likely missing, corrupted, or don't have proper Subject Alternative Names (SANs).

**Quick Fix:**
```bash
# Regenerate certificates with proper SANs
./scripts/regenerate-certs.sh

# Delete and recreate secrets
kubectl delete secret -n wazuh indexer-certs dashboard-certs
kubectl apply -k kubernetes/

# Restart pods
kubectl rollout restart statefulset/wazuh-indexer -n wazuh
```

**Note:** The deployment script (`./deploy.sh`) automatically generates certificates with proper SANs for new deployments.

**Detailed troubleshooting:** See [docs/TROUBLESHOOTING-INDEXER-SSL.md](docs/TROUBLESHOOTING-INDEXER-SSL.md)

#### Indexer Security Not Initialized
If you see "Not yet initialized (you may need to run securityadmin)" in the indexer logs:

**Quick Fix:**
```bash
# Initialize security configuration
./scripts/init-security.sh
```

This initializes the OpenSearch security plugin and creates the security index. See the troubleshooting guide for details.

#### DNS Not Resolving
```bash
# Check ExternalDNS logs
kubectl logs -n kube-system -l app=external-dns

# Verify domain in Linode
curl -H "Authorization: Bearer $LINODE_API_TOKEN" \
  https://api.linode.com/v4/domains

# Manual DNS check
dig wazuh.example.com
dig wazuh-manager.example.com
dig wazuh-registration.example.com
```

#### Certificate Not Issued
```bash
# Check certificate status (cert-manager names the cert after the TLS secret)
kubectl get certificate -n wazuh
kubectl describe certificate -n wazuh wazuh-dashboard-tls

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Check certificate request
kubectl get certificaterequest -n wazuh
```

#### LoadBalancer Pending
```bash
# Check service status
kubectl get svc -n wazuh

# Describe service
kubectl describe svc -n wazuh wazuh-manager-lb

# Check Linode NodeBalancer
# Visit: cloud.linode.com/nodebalancers
```

#### Agent Not Connecting
```bash
# On VM, check agent logs
sudo tail -f /var/ossec/logs/ossec.log

# Check agent status
sudo systemctl status wazuh-agent

# Test connectivity
telnet wazuh-manager.example.com 1514
telnet wazuh-registration.example.com 1515

# Verify manager can see agent
kubectl exec -n wazuh wazuh-manager-master-0 -- \
  /var/ossec/bin/agent_control -l
```

### Get Support

1. **Check logs**: Most issues are evident in logs
   ```bash
   ./kubernetes/scripts/verify-deployment.sh
   kubectl logs -n wazuh <pod-name>
   ```

2. **Review documentation**:
   - Wazuh: https://documentation.wazuh.com/
   - Kubernetes: https://kubernetes.io/docs/

3. **Search issues**: Check if others have encountered the same problem
   - GitHub Issues: https://github.com/johnybradshaw/akamai-wazuh/issues
   - Wazuh Forum: https://groups.google.com/g/wazuh

4. **Open an issue**: Provide detailed information
   - Description of the problem
   - Steps to reproduce
   - Relevant logs
   - Environment details

## Cost Breakdown

Estimated monthly costs on Akamai Cloud Computing:

| Component | Resource | Monthly Cost |
|-----------|----------|--------------|
| LKE Nodes | 3x Linode 4GB | $36.00 |
| Block Storage | 300GB (3x 100GB) | $30.00 |
| LoadBalancers | 2x NodeBalancer | $20.00 |
| **Total** | | **~$86.00** |

Notes:
- No control plane costs (LKE is free)
- Egress bandwidth: First 1TB free per month
- Additional nodes: $12/month per 4GB node
- Storage: $0.10/GB/month

### Cost Optimization

1. **Right-size resources**: Adjust CPU/memory limits
2. **Reduce storage**: Lower retention period, smaller PVCs
3. **Fewer LoadBalancers**: Already optimized (only 2 LBs)
4. **Single-zone**: Use 1 availability zone (lower egress)
5. **Reserved capacity**: Contact Akamai for volume discounts

## Security Best Practices

### Network Security

1. **Firewall Rules**: Restrict access to Wazuh services
   ```bash
   # Only allow specific IPs to access dashboard
   # Configure in Linode Cloud Manager -> Firewalls
   ```

2. **Network Policies**: Implement Kubernetes network policies
   ```bash
   # Example: Only allow dashboard to access indexer
   kubectl apply -f network-policies.yaml
   ```

### Credential Management

1. **Change default passwords**: Immediately after deployment
2. **Use password managers**: Store credentials securely
3. **Rotate regularly**: Every 90 days recommended
4. **Limit access**: Use Kubernetes RBAC

### Update Management

1. **Monitor for updates**: Subscribe to Wazuh security announcements
2. **Test in staging**: Always test updates before production
3. **Backup before update**: Take snapshots before major changes
4. **Update regularly**: Apply security patches promptly

### Audit and Compliance

1. **Enable audit logs**: Kubernetes audit logging
2. **Monitor access**: Track who accesses the dashboard
3. **Regular reviews**: Audit agent deployments and rules
4. **Compliance reports**: Use Wazuh built-in compliance dashboards

## Updating Wazuh

Two things carry a version in this repo (see also [CLAUDE.md](CLAUDE.md)):

- **Container image tags** — `newTag` in `kubernetes/kustomization.yml` (what
  actually gets deployed; currently `4.14.5`).
- **Base manifests** — the `kubernetes/wazuh-kubernetes` **git submodule**,
  pinned in `.gitmodules` to the `4.14.6` branch.

### Minor Updates (e.g., 4.14.4 → 4.14.5)

```bash
# Update image tags in kustomization.yml
nano kubernetes/kustomization.yml

# Change image tags
images:
  - name: wazuh/wazuh-indexer
    newTag: 4.14.5
  - name: wazuh/wazuh-manager
    newTag: 4.14.5
  - name: wazuh/wazuh-dashboard
    newTag: 4.14.5

# Apply update
kubectl apply -k kubernetes/

# Monitor rollout
kubectl rollout status statefulset/wazuh-indexer -n wazuh
kubectl rollout status statefulset/wazuh-manager-master -n wazuh
```

### Updating the wazuh-kubernetes submodule

To move the base manifests to a different upstream branch/commit and record the
new pin in this repo:

```bash
# Fetch and move the submodule to the desired ref
git -C kubernetes/wazuh-kubernetes fetch origin
git -C kubernetes/wazuh-kubernetes checkout <branch-or-commit>

# Stage the new submodule pointer
git add kubernetes/wazuh-kubernetes
git commit -m "Bump wazuh-kubernetes submodule to <ref>"
```

### Major Updates (e.g., 4.9.x → 5.0.x)

Major updates require careful planning:

1. **Review release notes**: Understand breaking changes
2. **Backup everything**: Data, configurations, credentials
3. **Test in staging**: Deploy new version in test environment
4. **Plan maintenance window**: Schedule downtime
5. **Follow official guide**: Wazuh upgrade documentation
6. **Verify after update**: Run verification script

## Uninstalling

### Remove Wazuh Deployment

```bash
# Delete Wazuh resources
kubectl delete -k kubernetes/

# Delete namespace
kubectl delete namespace wazuh

# Delete persistent volumes (WARNING: Data loss!)
kubectl delete pvc -n wazuh --all
```

### Remove Infrastructure Components

```bash
# Delete nginx-ingress
helm uninstall ingress-nginx -n ingress-nginx

# Delete cert-manager
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Delete ExternalDNS
kubectl delete deployment external-dns -n kube-system
kubectl delete secret external-dns-linode -n kube-system
```

### Clean Up DNS Records

DNS records created by ExternalDNS are not automatically deleted. Remove them manually:
1. Visit: https://cloud.linode.com/domains
2. Select your domain
3. Delete A records: `wazuh`, `wazuh-manager`, `wazuh-registration`

## FAQ

**Q: Can I use a different domain provider?**
A: No, this quick-start requires DNS hosted on Linode/Akamai for ExternalDNS integration. You can modify ExternalDNS configuration for other providers.

**Q: Can I deploy on non-Akamai Kubernetes?**
A: Yes. Use the `existing-cluster` profile (`./deploy.sh --existing-cluster`) and
set `STORAGE_PROVISIONER`, `INGRESS_CLASS` and `CLUSTER_ISSUER` to match your
cluster. See [Deploying to an Existing Cluster](#deploying-to-an-existing-cluster-git-submodule)
and [docs/EXISTING-CLUSTER.md](docs/EXISTING-CLUSTER.md).

**Q: How many agents can this handle?**
A: With default resources (3 nodes, 4GB each), approximately 100-200 agents. Scale workers and indexers for more.

**Q: Is this production-ready?**
A: Yes, but we recommend additional hardening for mission-critical deployments (network policies, RBAC, monitoring).

**Q: What about high availability?**
A: This deployment includes HA with 3 indexer replicas and 2 worker replicas. Manager master is a single pod (Wazuh limitation).

**Q: Can I use custom TLS certificates?**
A: Yes, replace Let's Encrypt with your own CA by modifying the cert-manager ClusterIssuer.

**Q: How do I add custom Wazuh rules?**
A: SSH into manager pod and edit `/var/ossec/etc/rules/local_rules.xml`, or use ConfigMaps.

**Q: What about Wazuh upgrades?**
A: Follow the "Updating Wazuh" section above. Always backup before upgrading.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Wazuh](https://wazuh.com/) - Open-source security platform
- [Akamai Cloud Computing](https://www.linode.com/) - Cloud infrastructure
- [Kubernetes](https://kubernetes.io/) - Container orchestration

## Additional Resources

- **Wazuh Documentation**: https://documentation.wazuh.com/
- **Akamai Cloud Docs**: https://www.linode.com/docs/
- **LKE Guide**: https://www.linode.com/docs/kubernetes/
- **Wazuh GitHub**: https://github.com/wazuh/wazuh-kubernetes
- **Community Forum**: https://groups.google.com/g/wazuh
- **Security Blog**: https://wazuh.com/blog/

---

**Need Help?** Open an issue: https://github.com/johnybradshaw/akamai-wazuh/issues

**Maintained by:** Akamai Cloud Computing Team
