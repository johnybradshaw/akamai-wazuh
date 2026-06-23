# Deploying Wazuh to an Existing Cluster (git submodule)

This guide covers deploying the Wazuh stack onto a Kubernetes cluster you
already operate — on Akamai Cloud (LKE) or any other provider (EKS, GKE, AKS,
k3s, on-prem) — using your **own** ingress controller, storage class, TLS and
DNS ("bring-your-own infrastructure").

For the turnkey Akamai/LKE experience that provisions everything for you, see
the [README](../README.md) instead.

## How the project is structured

- The Wazuh base manifests (`wazuh/wazuh-kubernetes`) are vendored as a **git
  submodule** at `kubernetes/wazuh-kubernetes`, pinned in
  [`.gitmodules`](../.gitmodules) to the `4.14.6` branch. This makes the
  deployment reproducible and lets you consume this repository as a submodule of
  your own GitOps repo.
- Container image tags are pinned in
  [`kubernetes/kustomization.yml`](../kubernetes/kustomization.yml) to the latest
  stable Wazuh release (`4.14.5`).
- Cloud-specific values are **parameterised** and substituted by `deploy.sh`:
  `${DOMAIN}`, `${STORAGE_PROVISIONER}`, `${INGRESS_CLASS}`, `${CLUSTER_ISSUER}`.

## Prerequisites you must provide

| Concern | What you need | How to configure |
|---------|---------------|------------------|
| Ingress | An ingress controller | `INGRESS_CLASS` (default `nginx`) |
| Storage | A CSI provisioner / default StorageClass | `STORAGE_PROVISIONER` |
| TLS | cert-manager + ClusterIssuer **or** your own TLS secret | `CLUSTER_ISSUER`, or pre-create the `wazuh-dashboard-tls` secret |
| DNS | Records for the three hostnames below | managed by you (`MANAGE_DNS=false`) |
| Tools | `kubectl`, `git`, `docker` (bcrypt), `jq` | — |

Common `STORAGE_PROVISIONER` values:

| Platform | Provisioner |
|----------|-------------|
| Akamai Cloud / LKE | `linodebs.csi.linode.com` |
| AWS EKS | `ebs.csi.aws.com` |
| Google GKE | `pd.csi.storage.gke.io` |
| Azure AKS | `disk.csi.azure.com` |
| k3s / local-path | `rancher.io/local-path` |

DNS records to create (point them at your ingress / load balancers):

- `wazuh.<domain>` → dashboard (HTTPS via ingress)
- `wazuh-manager.<domain>` → `wazuh-workers-lb` service (agent events, TCP 1514)
- `wazuh-registration.<domain>` → `wazuh-manager-lb` service (registration, TCP 1515 / API 55000)

> The manager/worker services are `type: LoadBalancer`. On managed clouds they
> get an external IP automatically. On bare-metal install MetalLB (or patch them
> to `NodePort`).

## Option A — `deploy.sh --existing-cluster`

```bash
git clone --recurse-submodules https://github.com/johnybradshaw/akamai-wazuh.git
cd akamai-wazuh
cp config.env.example config.env
```

Edit `config.env`:

```bash
DEPLOY_PROFILE="existing-cluster"
DOMAIN="example.com"
STORAGE_PROVISIONER="ebs.csi.aws.com"   # match your cluster
INGRESS_CLASS="nginx"                    # match your ingress controller
CLUSTER_ISSUER="letsencrypt-prod"        # your cert-manager issuer (if used)

# Optional — let deploy.sh manage these too (default false for existing-cluster)
# MANAGE_DNS="false"   # set true + LINODE_API_TOKEN to use Linode ExternalDNS
# MANAGE_TLS="false"   # set true to wait for cert-manager to issue the cert
```

Deploy:

```bash
./deploy.sh --existing-cluster
```

What the `existing-cluster` profile does **not** do (compared to `akamai`):

- ❌ Does not install nginx-ingress, cert-manager or ExternalDNS
- ❌ Does not verify the domain on Linode DNS
- ❌ Does not require `LINODE_API_TOKEN` (unless `MANAGE_DNS=true`)
- ❌ Does not require `LETSENCRYPT_EMAIL`
- ✅ Generates certs + credentials, substitutes your values, applies Kustomize,
  initialises the indexer security plugin

## Option B — consume this repo as a submodule of your GitOps repo

```bash
# In your infrastructure repository
git submodule add https://github.com/johnybradshaw/akamai-wazuh.git vendor/akamai-wazuh
git -C vendor/akamai-wazuh checkout <tag-or-commit>   # pin to a release you control
git submodule update --init --recursive               # also pulls wazuh-kubernetes
git add .gitmodules vendor/akamai-wazuh
git commit -m "Vendor akamai-wazuh"
```

Drive deployment from your pipeline:

```bash
cd vendor/akamai-wazuh
cp config.env.example config.env   # or template it from your secrets store
./deploy.sh --existing-cluster
```

To update later, move the submodule pointer and commit it:

```bash
git -C vendor/akamai-wazuh fetch origin
git -C vendor/akamai-wazuh checkout <new-ref>
git add vendor/akamai-wazuh && git commit -m "Bump akamai-wazuh"
```

## Option C — raw Kustomize (advanced / Argo CD / Flux)

The active overlay lives at the repository root level kustomization
`kubernetes/` (it must sit there so its `secretGenerator`/`configMapGenerator`
can read cert and config files inside the `wazuh-kubernetes` submodule).

Because a few values use `${...}` placeholders, you must substitute them before
`kubectl apply -k`. The simplest approach is to let `deploy.sh` do it; for a pure
GitOps flow, render with substitution in CI, e.g.:

```bash
# 1. Initialise submodules and generate certs (once)
git submodule update --init --recursive
( cd kubernetes/wazuh-kubernetes/wazuh/certs/indexer_cluster && bash "$OLDPWD/scripts/generate-indexer-certs-with-sans.sh" )
( cd kubernetes/wazuh-kubernetes/wazuh/certs/dashboard_http && bash generate_certs.sh )

# 2. Substitute placeholders and apply
export DOMAIN=example.com STORAGE_PROVISIONER=ebs.csi.aws.com \
       INGRESS_CLASS=nginx CLUSTER_ISSUER=letsencrypt-prod
sed -e "s|\${DOMAIN}|$DOMAIN|g" \
    -e "s|\${STORAGE_PROVISIONER}|$STORAGE_PROVISIONER|g" \
    -e "s|\${INGRESS_CLASS}|$INGRESS_CLASS|g" \
    -e "s|\${CLUSTER_ISSUER}|$CLUSTER_ISSUER|g" \
    -i kubernetes/production-overlay/*.yaml
kubectl apply -k kubernetes/
```

> **Argo CD / Flux:** point the Application/Kustomization at `kubernetes/`, enable
> submodule fetching, and provide the four values via a Kustomize *replacements*
> overlay or a pre-render step. The manifests intentionally avoid hard
> dependencies on cert-manager CRDs, so they apply cleanly even when cert-manager
> is not installed (provide your own `wazuh-dashboard-tls` secret in that case).

## TLS without cert-manager

If you do not run cert-manager, pre-create the dashboard TLS secret and set
`MANAGE_TLS=false` (the default for `existing-cluster`). The
`cert-manager.io/cluster-issuer` annotation on the Ingress is simply ignored:

```bash
kubectl create secret tls wazuh-dashboard-tls \
  --cert=fullchain.pem --key=privkey.pem -n wazuh
```

## Verifying

```bash
./kubernetes/scripts/verify-deployment.sh wazuh
kubectl get pods,svc,ingress -n wazuh
```

## Post-deployment

The deployment ships with the upstream Wazuh **default credentials**
(`admin` / `SecretPassword`). **Change them immediately** — see
[README → Change Admin Password](../README.md#change-admin-password).
