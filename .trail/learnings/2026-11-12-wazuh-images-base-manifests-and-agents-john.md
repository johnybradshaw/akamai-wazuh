---
title: "Wazuh images, base manifests and agents move together; agents are pinned and never newer than the manager"
author: John
date: 2026-11-12
branch: 31-upgrade-wazuh-4.14.10
cost: { minutes: 10, tokens: 272140 }
id: l-244bade8
scope: repo
status: active
replaces: l-a88d7d6f
src: agent
touches:
  - ".gitmodules"
  - CLAUDE.md
  - README.md
  - config.env.example
  - deploy.sh
  - docs/EXISTING-CLUSTER.md
  - docs/architecture.md
  - docs/decisions/002-vendor-wazuh-kubernetes-as-submodule.md
  - kubernetes/CLAUDE.md
  - kubernetes/wazuh-kubernetes
---

## Decided
- The submodule is pinned by commit, now the one tag v4.14.10 names (#31). Image `newTag`, the pin, `WAZUH_K8S_COMMIT` and the agent version all move together in one change.
- Agents are pinned: `WAZUH_AGENT_VERSION` in the agent scripts (apt `=<v>-1` plus `apt-mark hold`, or the image tag). Wazuh supports agents at the manager's version or older only, so agents are upgraded after the manager.

## Tried and ruled out
- Pinning by a named branch: upstream deletes release branches.
- Unpinned `apt-get install wazuh-agent` from the 4.x repo: it silently installed 4.14.10 against a 4.14.5 manager.

## Watch out
- Never run `git submodule update --remote` here; it follows upstream `main`, which is alpha.
- Upstream VERSION.json says "stage": "rc2" even on GA tags. Check documentation.wazuh.com release notes for release status, not that field.
- the live deployment does not track this repo: its private GitOps repo commits rendered manifests and bumps image tags in place. A bump here does not reach the cluster by itself.

In the code:
- Pin `97bc03d9fa03342302e76aca5b0f3200269a63a1` (tag v4.14.10); `WAZUH_K8S_COMMIT` equals it in `deploy.sh`, `scripts/regenerate-certs.sh`, `config.env.example`.
- `agent-deployment/deploy-agent.sh` and `deploy-k8s-agent.sh`: `WAZUH_AGENT_VERSION` default 4.14.10.
- Before a bump, diff `wazuh/` between the two upstream tags; image-tag-only diffs need no other change.
