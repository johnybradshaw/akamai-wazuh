# Integrating akamai-wazuh into a multi-application deployment

> **Audience:** engineers and AI coding assistants (e.g. Claude) who are working
> in a *different* repository and want to add this Wazuh SIEM deployment as a
> **git submodule** and run it alongside other applications on a shared cluster.
>
> For deploying this repo on its own, see the [README](../README.md). For the
> bring-your-own-infrastructure details, see [EXISTING-CLUSTER.md](EXISTING-CLUSTER.md).

---

## What you are integrating

- A **Kustomize**-based deployment of Wazuh (Manager, Indexer/OpenSearch x3,
  Dashboard) rooted at `kubernetes/`.
- The upstream `wazuh/wazuh-kubernetes` base manifests are themselves a **nested
  git submodule** at `kubernetes/wazuh-kubernetes` (so submodule init must be
  **recursive**).
- Two deploy profiles: `akamai` (turnkey LKE — installs ingress/cert-manager/
  ExternalDNS) and `existing-cluster` (**use this for multi-app clusters** — it
  assumes you already run those and only deploys Wazuh).
- Wazuh installs into its **own `wazuh` namespace**, which isolates it from your
  other workloads.

## Agent quickstart (TL;DR)

Run from the root of the **parent** repository:

```bash
# 1. Add as a submodule and pin it (recursive — there is a nested submodule)
git submodule add https://github.com/johnybradshaw/akamai-wazuh.git vendor/akamai-wazuh
git -C vendor/akamai-wazuh checkout <tag-or-commit>      # pin to a known-good ref
git submodule update --init --recursive
git add .gitmodules vendor/akamai-wazuh && git commit -m "Vendor akamai-wazuh"

# 2. Configure for an existing, shared cluster
cd vendor/akamai-wazuh
cp config.env.example config.env
#   In config.env set at minimum:
#     DEPLOY_PROFILE="existing-cluster"
#     DOMAIN="example.com"
#     STORAGE_PROVISIONER="<your cluster's CSI provisioner>"
#     INGRESS_CLASS="<your ingress class>"     # e.g. nginx
#     CLUSTER_ISSUER="<your cert-manager ClusterIssuer>"   # if you use cert-manager

# 3. Deploy (generates certs + credentials, applies Kustomize, inits security)
./deploy.sh --existing-cluster
```

Then verify: `./kubernetes/scripts/verify-deployment.sh wazuh`.

## Prerequisites the agent must ensure

| Need | Why | Notes |
|------|-----|-------|
| Recursive submodule init | nested `wazuh-kubernetes` submodule | `git submodule update --init --recursive` |
| `kubectl`, `git`, `jq`, `openssl` | deploy + cert generation | — |
| `docker` (running) | bcrypt hashing for credentials | required by `generate-credentials.sh` |
| Ingress controller | dashboard HTTPS | set `INGRESS_CLASS` to match |
| StorageClass / CSI provisioner | indexer + manager PVCs | set `STORAGE_PROVISIONER` |
| cert-manager + ClusterIssuer *(optional)* | dashboard TLS | else pre-create the `wazuh-dashboard-tls` secret |
| `helm` | **not** needed for `existing-cluster` | only the `akamai` profile uses it |

## Coexisting with other applications

This is the key part for a shared cluster. Wazuh is designed to be a good tenant:

- **Namespace isolation.** Everything lands in the `wazuh` namespace. Your other
  apps are untouched. (The namespace is currently fixed to `wazuh`; to change it
  you must edit `namespace:` in `kubernetes/kustomization.yml` and the
  `namespace: wazuh` fields in `kubernetes/production-overlay/*.yaml`.)
- **Use the `existing-cluster` profile.** On a multi-app cluster the ingress
  controller, cert-manager and DNS are usually already installed and shared — the
  `akamai` profile would try to (re)install them cluster-wide. `existing-cluster`
  skips all of that and reuses what you have.
- **Cluster-scoped resources to check for conflicts** (the only objects that
  leave the `wazuh` namespace):
  - a `StorageClass` named **`wazuh-storage`** (dedicated; unlikely to clash).
  - *(akamai profile only)* a `letsencrypt-prod`/`letsencrypt-staging`
    `ClusterIssuer` and the `external-dns` `ClusterRole`/`ClusterRoleBinding`.
    Skip these by using `existing-cluster`.
- **Ingress host.** The dashboard claims `wazuh.<DOMAIN>` on your shared ingress
  class — make sure that host is free.
- **LoadBalancer services.** `wazuh-manager-lb` and `wazuh-workers-lb` are
  `type: LoadBalancer` and provision cloud load balancers (for agents on
  1514/1515). On bare metal they need MetalLB or a patch to `NodePort`.
- **Resource footprint.** Plan capacity: 3× indexer + manager master + N workers
  + dashboard. Tune via `config.env` (`INDEXER_*`, `MANAGER_*`, `DASHBOARD_*`,
  `WORKER_REPLICAS`, `INDEXER_REPLICAS`).

## Driving it from a parent repo / orchestrator

`deploy.sh --existing-cluster` is the simplest entry point and is safe to call
from a Makefile, CI job, or a wrapper script in the parent repo. Example
umbrella layout:

```
my-platform/
├── vendor/
│   └── akamai-wazuh/          # this submodule (pinned)
│       └── config.env         # gitignored; templated from your secrets store
├── apps/
│   ├── app-a/ ...
│   └── app-b/ ...
└── Makefile                   # `make wazuh` -> cd vendor/akamai-wazuh && ./deploy.sh --existing-cluster
```

## GitOps (Argo CD / Flux) — important caveat

This deployment **generates TLS certificates and credentials at deploy time**,
and those files are **gitignored** (never committed). A purely declarative
GitOps sync of `kubernetes/` will therefore fail, because the `secretGenerator`/
`configMapGenerator`/`patches` reference files that do not exist in git
(`*.pem`, `internal_users.yml`, `*.patch.yaml`). Choose one:

1. **Render-and-apply in CI (recommended).** Run `./deploy.sh --existing-cluster`
   (or the manual steps in [EXISTING-CLUSTER.md → Option C](EXISTING-CLUSTER.md#option-c--raw-kustomize-advanced--argo-cd--flux))
   from a pipeline with cluster credentials. The generated secrets stay in the
   runner, not in git.
2. **Generate once, then manage secrets externally.** Generate certs/credentials
   once, store them in your secrets manager (SealedSecrets / External Secrets /
   Vault), and have the GitOps controller reconcile the workloads while the
   secrets are supplied out-of-band.

Also enable **recursive submodule** fetching in your GitOps tool, and supply the
four placeholders (`${DOMAIN}`, `${STORAGE_PROVISIONER}`, `${INGRESS_CLASS}`,
`${CLUSTER_ISSUER}`) via a pre-render/substitution step — they are filled in by
`deploy.sh` but not by a bare `kubectl apply -k`.

## Updating the pinned version

```bash
git -C vendor/akamai-wazuh fetch origin
git -C vendor/akamai-wazuh checkout <new-tag-or-commit>
git submodule update --init --recursive
git add vendor/akamai-wazuh && git commit -m "Bump akamai-wazuh to <ref>"
```

Review this repo's [CHANGELOG / releases](https://github.com/johnybradshaw/akamai-wazuh/releases)
and the [Updating Wazuh](../README.md#updating-wazuh) section before bumping.

## Uninstall

```bash
kubectl delete -k vendor/akamai-wazuh/kubernetes/   # removes the wazuh namespace workloads
kubectl delete namespace wazuh                      # if anything remains
# wazuh-storage StorageClass is cluster-scoped — remove only if nothing else uses it:
kubectl delete storageclass wazuh-storage
```

## Integration checklist

- [ ] Added as a submodule and **pinned** to a specific tag/commit
- [ ] `git submodule update --init --recursive` succeeds (nested submodule present)
- [ ] `config.env` has `DEPLOY_PROFILE=existing-cluster` + `DOMAIN` + storage/ingress/issuer set for your cluster
- [ ] Ingress class, storage class, and (optional) cert-manager issuer exist on the cluster
- [ ] `wazuh.<DOMAIN>` host and the `wazuh-storage` StorageClass name are free
- [ ] Cluster has capacity for the indexer/manager/dashboard footprint
- [ ] DNS records point at your ingress / load balancers (you manage DNS)
- [ ] Deployed via `deploy.sh --existing-cluster` (or a CI render-and-apply step)
- [ ] `verify-deployment.sh wazuh` passes; admin password retrieved from `.credentials`
