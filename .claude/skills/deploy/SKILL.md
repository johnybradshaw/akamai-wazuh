---
name: deploy
description: "Guide deployment of Wazuh SIEM to Akamai Cloud, including pre-flight checks and post-deployment verification."
trigger: "When the user asks to deploy, run deployment, or check deployment readiness."
---

# deploy

## Overview

Assists with deploying or updating the Wazuh SIEM platform on LKE, including configuration validation, deployment execution, and post-deployment health checks.

## Inputs

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `mode` | `full`, `dry-run`, or `verify-only` | No | `dry-run` |
| `namespace` | Kubernetes namespace | No | `wazuh` |

## Expected Outputs

- Pre-flight check results
- Deployment status or dry-run diff
- Post-deployment health verification

## Steps

1. Verify `config.env` exists and contains required variables.
2. Check kubectl connectivity to the cluster.
3. Run `deploy.sh --dry-run` for validation (or full deploy if confirmed).
4. Execute `verify-deployment.sh` to confirm health.
5. Report deployment status and access information.
