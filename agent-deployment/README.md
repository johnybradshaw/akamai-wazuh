# Wazuh Agent Deployment

This directory contains scripts for deploying Wazuh agents to different environments.

## Quick Start

### Deploy to Kubernetes Cluster (DaemonSet)

Monitor your Kubernetes cluster nodes and workloads:

```bash
cd agent-deployment
./deploy-k8s-agent.sh
```

This deploys Wazuh agents as a DaemonSet to all nodes in your cluster.

### Deploy to Single VM

Monitor a single Linux VM/server:

```bash
./deploy-agent.sh web-server-01.example.com
```

### Deploy to Multiple VMs

Monitor multiple VMs from a CSV file:

```bash
# Create your VM list
cp vm-list.txt.example vm-list.txt
nano vm-list.txt  # Add your VMs

# Deploy
./deploy-agents-bulk.sh vm-list.txt

# Or deploy in parallel (faster)
./deploy-agents-bulk.sh vm-list.txt --parallel 5
```

## Deployment Options

### 1. Kubernetes DaemonSet Deployment

**Use Case:** Monitor Kubernetes cluster nodes, containers, and workloads

**Script:** `deploy-k8s-agent.sh`

**Features:**
- Deploys agents to all cluster nodes automatically
- Uses DaemonSet for automatic scaling
- Monitors host filesystems, processes, and containers
- Optional privileged mode for deeper system access

**Usage:**
```bash
# Basic deployment
./deploy-k8s-agent.sh

# Custom namespace
./deploy-k8s-agent.sh --namespace monitoring-agents

# With privileged access (for deeper monitoring)
./deploy-k8s-agent.sh --privileged

# Custom agent group
./deploy-k8s-agent.sh --agent-group production-k8s

# Full options
./deploy-k8s-agent.sh \
  --namespace wazuh-agents \
  --manager-ns wazuh \
  --agent-group kubernetes \
  --privileged
```

**Options:**
- `--namespace NAME` - Namespace for agent DaemonSet (default: wazuh-agents)
- `--manager-ns NAME` - Namespace where Wazuh manager is deployed (default: wazuh)
- `--agent-group NAME` - Agent group name (default: kubernetes)
- `--privileged` - Run with elevated privileges for system-level monitoring
- `--help` - Show help message

**Requirements:**
- kubectl configured for target cluster
- Wazuh manager already deployed
- Cluster admin permissions

**What It Monitors:**
- Node system logs and metrics
- Container activities
- Pod security events
- Kubernetes API activities
- Host filesystem integrity
- Network connections
- Process executions

---

### 2. Single VM Deployment

**Use Case:** Monitor a single Linux server or VM

**Script:** `deploy-agent.sh`

**Usage:**
```bash
# Deploy to hostname
./deploy-agent.sh web-server-01.example.com

# Deploy with custom name and group
./deploy-agent.sh 192.168.1.10 web-01 web-servers

# Deploy with SSH user
./deploy-agent.sh ubuntu@hostname db-server database-servers
```

**Arguments:**
1. `vm-hostname` - SSH hostname or IP (required)
2. `agent-name` - Custom agent name (optional, defaults to hostname)
3. `agent-group` - Agent group for organization (optional, defaults to "default")

**Requirements:**
- SSH access to target VM
- kubectl configured for Wazuh cluster
- Target VM running Ubuntu 18.04+ or Debian 9+
- Root/sudo access on target VM

---

### 3. Bulk VM Deployment

**Use Case:** Monitor multiple Linux servers or VMs

**Script:** `deploy-agents-bulk.sh`

**CSV Format:**
```csv
hostname,agent_name,agent_group
web-server-01.example.com,web-01,web-servers
192.168.1.10,web-02,web-servers
root@db-server.example.com,db-01,database-servers
```

**Usage:**
```bash
# Sequential deployment (one at a time)
./deploy-agents-bulk.sh vm-list.txt

# Parallel deployment (faster for many VMs)
./deploy-agents-bulk.sh vm-list.txt --parallel 5
```

**Options:**
- `--parallel N` - Deploy to N VMs simultaneously (default: 1)

**Requirements:**
- Same as single VM deployment
- CSV file with VM list

## Agent Groups

Organize your agents by environment, function, or location:

- `web-servers` - Web/application servers
- `database-servers` - Database servers
- `kubernetes` - Kubernetes cluster nodes
- `load-balancers` - Load balancer nodes
- `monitoring` - Monitoring infrastructure
- `production` - Production environment
- `staging` - Staging environment
- `development` - Development environment

Custom groups help with:
- Applying specific security policies
- Organizing alerts and reports
- Managing agent configurations
- Scaling monitoring strategies

## Verifying Agents

### Check Agent Status on Manager

```bash
# Get manager pod name
MANAGER_POD=$(kubectl get pods -n wazuh -l app=wazuh-manager,node-type=master -o jsonpath='{.items[0].metadata.name}')

# List all agents
kubectl exec -n wazuh $MANAGER_POD -- /var/ossec/bin/agent_control -l

# Check specific agent
kubectl exec -n wazuh $MANAGER_POD -- /var/ossec/bin/agent_control -i AGENT_ID
```

### Check Kubernetes Agent Pods

```bash
# View all agent pods
kubectl get pods -n wazuh-agents -l app=wazuh-agent -o wide

# View agent logs
kubectl logs -n wazuh-agents -l app=wazuh-agent --tail=50

# Check DaemonSet status
kubectl get daemonset wazuh-agent -n wazuh-agents
```

### Check VM Agent Status

```bash
# On the VM
ssh vm-hostname 'sudo systemctl status wazuh-agent'

# View agent logs on VM
ssh vm-hostname 'sudo tail -f /var/ossec/logs/ossec.log'
```

## Troubleshooting

### Kubernetes Agents Not Registering

1. Check agent pod logs:
   ```bash
   kubectl logs -n wazuh-agents -l app=wazuh-agent --tail=100
   ```

2. Verify manager endpoints:
   ```bash
   kubectl get configmap wazuh-agent-config -n wazuh-agents -o yaml
   ```

3. Check network connectivity:
   ```bash
   kubectl exec -n wazuh-agents <agent-pod> -- ping wazuh-manager.<domain>
   ```

4. Verify registration password:
   ```bash
   kubectl get secret wazuh-agent-password -n wazuh-agents -o yaml
   ```

### VM Agents Not Connecting

1. Check agent status:
   ```bash
   ssh vm-hostname 'sudo systemctl status wazuh-agent'
   ```

2. View agent logs:
   ```bash
   ssh vm-hostname 'sudo cat /var/ossec/logs/ossec.log'
   ```

3. Verify manager connectivity:
   ```bash
   ssh vm-hostname 'ping wazuh-manager.<domain>'
   ssh vm-hostname 'nc -zv wazuh-manager.<domain> 1514'
   ```

4. Check firewall rules:
   - Port 1514 (agent events)
   - Port 1515 (agent registration)

### Agent Shows as Disconnected

1. Restart the agent:
   ```bash
   # Kubernetes
   kubectl rollout restart daemonset/wazuh-agent -n wazuh-agents

   # VM
   ssh vm-hostname 'sudo systemctl restart wazuh-agent'
   ```

2. Check manager LoadBalancer:
   ```bash
   kubectl get svc -n wazuh wazuh-manager-lb
   ```

3. Verify DNS records:
   ```bash
   dig wazuh-manager.<domain>
   dig wazuh-registration.<domain>
   ```

## Removing Agents

### Remove Kubernetes Agents

```bash
kubectl delete daemonset wazuh-agent -n wazuh-agents
kubectl delete namespace wazuh-agents
```

### Remove VM Agent

```bash
ssh vm-hostname 'sudo systemctl stop wazuh-agent'
ssh vm-hostname 'sudo apt-get remove --purge wazuh-agent'
ssh vm-hostname 'sudo rm -rf /var/ossec'
```

### Remove from Manager

```bash
MANAGER_POD=$(kubectl get pods -n wazuh -l app=wazuh-manager,node-type=master -o jsonpath='{.items[0].metadata.name}')

# List agents to find ID
kubectl exec -n wazuh $MANAGER_POD -- /var/ossec/bin/agent_control -l

# Remove specific agent
kubectl exec -n wazuh $MANAGER_POD -- /var/ossec/bin/manage_agents -r AGENT_ID
```

## Best Practices

1. **Use Agent Groups** - Organize agents by environment, function, or location
2. **Monitor Logs** - Regularly check agent logs for errors
3. **Keep Agents Updated** - Update agent versions to match manager
4. **Secure SSH Access** - Use key-based authentication for VM deployments
5. **Test in Stages** - Deploy to dev/staging before production
6. **Document Changes** - Keep track of which systems have agents deployed
7. **Regular Audits** - Periodically verify all agents are active and reporting

## Additional Resources

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Wazuh Kubernetes Guide](https://documentation.wazuh.com/current/deployment-options/deploying-with-kubernetes/index.html)
- [Agent Management](https://documentation.wazuh.com/current/user-manual/registering/index.html)
