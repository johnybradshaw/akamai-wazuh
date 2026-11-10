---
title: The Wazuh base manifests stay pinned to an exact upstream commit; move the pin only with an explicit checkout
author: John
date: 2026-11-10
branch: chore/supersede-submodule-learning-25
cost: { minutes: 1, tokens: 7807 }
id: l-1c85ca12
scope: repo
status: active
replaces: l-27134368
src: agent
touches:
  - ".gitmodules"
  - deploy.sh
  - kubernetes/wazuh-kubernetes
---

## Decided
- The wazuh-kubernetes submodule is pinned by commit, on purpose, and the commit is the only thing that pins it. The earlier claim that it tracks the `v4.14.9` tag was never true on main.
- To move it, check out an explicit tag or commit inside the submodule and commit the new pointer. The deploy fallback's commit must move with it, so a checkout without submodules yields identical manifests.

## Tried and ruled out
- Pinning by a named branch: upstream deletes release branches. `4.14.6` vanished, then `4.14.8` and `4.14.9`, and a branch key naming a deleted ref breaks `git clone -b`.

## Watch out
- Never run `git submodule update --remote` here. With no branch key it follows upstream's default branch, which is alpha.
- The pinned commit came from a branch upstream has since deleted. It was still fetchable by SHA on 2026-11-10; if upstream ever garbage-collects it, the fallback clone breaks.

In the code:
- `.gitmodules`: no `branch` key, with a comment explaining why.
- Pin: `e918d811760b943a4b3acca02e691b70b1a0b597`. `deploy.sh` `WAZUH_K8S_COMMIT` defaults to the same SHA.
- Move it: `git -C kubernetes/wazuh-kubernetes fetch origin && git -C kubernetes/wazuh-kubernetes checkout <ref> && git add kubernetes/wazuh-kubernetes`, then update `WAZUH_K8S_COMMIT`.
- Check it's still reachable: `git fetch --depth=1 https://github.com/wazuh/wazuh-kubernetes.git <sha>`.
