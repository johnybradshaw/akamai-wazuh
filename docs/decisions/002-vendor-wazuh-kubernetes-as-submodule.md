# ADR-002: Vendor wazuh-kubernetes as a git submodule

## Status

Accepted

## Context

The deployment depends on the upstream [`wazuh/wazuh-kubernetes`](https://github.com/wazuh/wazuh-kubernetes)
base manifests. Previously `deploy.sh` performed a runtime `git clone` of that
repository (branch `v4.9.2`) into a **gitignored** directory at
`kubernetes/wazuh-kubernetes/`.

This had several drawbacks:

- **Not reproducible** — the cloned ref could drift, and nothing in the repo
  recorded exactly which upstream commit was deployed.
- **Not composable** — consumers could not add this project to their own GitOps
  repository as a submodule and get a complete, self-contained tree.
- **Hidden dependency** — the base manifests did not appear in version control,
  making upgrades and audits harder.

We also want to support deploying to an **existing** Kubernetes cluster (not just
a freshly provisioned LKE cluster).

## Decision Drivers

- Reproducible, pinned deployments.
- Ability to consume this repository as a git submodule of a parent repo.
- Keep `kubectl apply -k kubernetes/` working (the active kustomization must stay
  at `kubernetes/` so its file-based generators can read certs/configs inside the
  base manifests).
- Upstream `wazuh-kubernetes` no longer tags releases for the 4.14 line; the
  manifests are published on **branches** (`4.14.6`, `4.14.7`, …).

## Options Considered

1. **Keep the runtime `git clone`.** Simple, but unpinned and not composable.
2. **Vendor the manifests by copying them into the repo.** Pinned, but loses the
   clean upstream lineage and makes upgrades a manual copy.
3. **Add `wazuh-kubernetes` as a pinned git submodule.** Records the exact
   upstream commit, keeps a clean lineage, and lets the whole project be nested
   as a submodule (`git submodule update --init --recursive`).

## Decision Outcome

Option 3 — add `wazuh-kubernetes` as a git submodule at
`kubernetes/wazuh-kubernetes`, pinned via `.gitmodules` to the `4.14.6` branch
(the most mature 4.14 branch; `4.14.7`/`main` are alpha). The container image
tags in `kubernetes/kustomization.yml` are pinned independently to the latest
**stable** release, `4.14.5`.

`deploy.sh` now initialises the submodule (`git submodule update --init
--recursive`) instead of cloning, with a fallback to a pinned clone when the
project is used outside a git checkout (e.g. a source tarball).

To support existing clusters, cloud-specific values are parameterised
(`STORAGE_PROVISIONER`, `INGRESS_CLASS`, `CLUSTER_ISSUER`) and a new
`existing-cluster` deployment profile skips the Akamai/Linode provisioning.

## Consequences

- The submodule pointer is tracked in git; deployments are reproducible.
- Contributors must clone with `--recurse-submodules` (or run `git submodule
  update --init --recursive`); `deploy.sh` does this automatically.
- Image tags (`4.14.5`) and the manifest branch (`4.14.6`) are intentionally
  decoupled — image tags follow the latest GA release, manifests follow the
  closest maintained branch (upstream publishes no 4.14 tags). Both are checked
  by the `kustomize-validate` skill.
- Bumping the base manifests is a deliberate, reviewable change (move the
  submodule pointer and commit it) rather than an implicit runtime clone.

## Amendment (2026-11-11, #29)

Two premises above no longer hold; the decision itself (vendor as a pinned
submodule) stands.

- **Pin by commit, not branch.** Upstream deleted the `4.14.6` branch (and later
  `4.14.8` / `4.14.9`), so `.gitmodules` now carries no `branch` key. The
  recorded submodule commit is the only pin, and `WAZUH_K8S_COMMIT` (the
  fallback clone target in `deploy.sh`, `scripts/regenerate-certs.sh` and
  `config.env.example`) must equal it.
- **Upstream does tag 4.14 releases** (`v4.14.0`..`v4.14.10` as of 2026-11-10).
  The pin moved from `e918d81176` (a commit from the deleted branch) to
  `84e99645ce`, the commit tag `v4.14.6` points at, so the pin maps to a named
  ref. The two differ only in `VERSION.json` (`stage` `rc1` → `rc2`); the
  manifests are identical. Upstream's tagged commit is titled
  `Revert tag for v4.14.6-rc2` and still self-labels as `rc2`.
