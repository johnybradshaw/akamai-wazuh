---
title: "The Wazuh base manifests stay pinned to an exact upstream commit, now the one tag v4.14.6 names; move the pin only with an explicit checkout"
author: John
date: 2026-11-11
branch: 29-pin-v4.14.6-tag
cost: { minutes: 9, tokens: 73845 }
id: l-a88d7d6f
scope: repo
status: active
replaces: l-1c85ca12
src: agent
touches:
  - deploy.sh
  - scripts/regenerate-certs.sh
---

## Decided
- The wazuh-kubernetes submodule is pinned by commit, on purpose, and the commit is the only thing that pins it.
- On 2026-11-11 (#29) the pin moved from a commit on the deleted `4.14.6` branch to the commit tag `v4.14.6` points at, so the pin maps to a named upstream ref. Manifests are identical; only VERSION.json differs.
- To move it, check out an explicit tag or commit inside the submodule and commit the new pointer. The fallback commit must move with it, in every file that carries it, so a checkout without submodules yields identical manifests.

## Tried and ruled out
- Pinning by a named branch: upstream deletes release branches. `4.14.6` vanished, then `4.14.8` and `4.14.9`, and a branch key naming a deleted ref breaks `git clone -b`.

## Watch out
- Never run `git submodule update --remote` here. With no branch key it follows upstream's default branch, which is alpha.
- Upstream's `v4.14.6` tagged commit is titled "Revert tag for v4.14.6-rc2" and its VERSION.json still says rc2. A tag name alone is not proof of a GA release.
- Several docs once claimed the pin was "the 4.14.6 branch in .gitmodules". Grep for the old SHA and for "4.14.6" when the pin moves.

In the code:
- Pin: `84e99645ce4c10cc2062eb22febee563667fef39` (tag `v4.14.6`). Previous: `e918d811760b943a4b3acca02e691b70b1a0b597`.
- Fallback `WAZUH_K8S_COMMIT` must equal the pin in `deploy.sh`, `scripts/regenerate-certs.sh` and `config.env.example`.
- `.gitmodules`: no `branch` key, with a comment explaining why.
- Move it: `git -C kubernetes/wazuh-kubernetes fetch origin --tags && git -C kubernetes/wazuh-kubernetes checkout '<tag>^{commit}' && git add kubernetes/wazuh-kubernetes`, then update the fallbacks and docs.
- Check reachability: `git fetch --depth=1 https://github.com/wazuh/wazuh-kubernetes.git <sha>`.
