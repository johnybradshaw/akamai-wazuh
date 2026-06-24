# ADR-003: Generate and wire deployment credentials

## Status

Accepted

## Context

The upstream `wazuh-kubernetes` base manifests ship well-known default
credentials: dashboard `admin` / `SecretPassword`, `kibanaserver` /
`kibanaserver`, a fixed Wazuh API password, agent registration password
`password`, and the publicly documented cluster key `123a45bc67def891gh23i45jk67l8mn9`.

The repository already included `kubernetes/scripts/generate-credentials.sh`,
which produced strong random passwords, bcrypt hashes and a `.credentials` file —
but **nothing consumed them**. The active `kubernetes/kustomization.yml`
referenced the base default secrets, so deployments ran with the upstream
defaults while the deploy output misleadingly printed the (unused) generated
admin password.

## Decision Drivers

- "Security by default" — a fresh deployment must not use publicly known
  credentials.
- The plaintext service secrets and the bcrypt hashes in `internal_users.yml`
  must stay **consistent** (a mismatch breaks dashboard ↔ indexer auth).
- Keep working with plain `kubectl apply -k` and the existing deploy flow.
- Avoid committing secrets to git.

## Options Considered

1. **Document manual post-deploy password changes.** Low effort, but insecure by
   default and error-prone.
2. **Imperatively `kubectl apply` secrets after `kubectl apply -k`.** Fights
   Kustomize; the next apply reverts it; not GitOps-friendly.
3. **Generate the values and wire them in via Kustomize.** `generate-credentials.sh`
   writes the (gitignored) `internal_users.yml` plus strategic-merge secret
   patches; the kustomization consumes them. Consistent with how generated TLS
   certs are already consumed.

## Decision Outcome

Option 3. `generate-credentials.sh` now also emits, into
`kubernetes/production-overlay/` (all gitignored):

- `internal_users.yml` — admin/kibanaserver bcrypt hashes (consumed by the
  `indexer-conf` configMapGenerator), and
- `indexer-cred.patch.yaml`, `dashboard-cred.patch.yaml`,
  `wazuh-api-cred.patch.yaml`, `wazuh-authd-pass.patch.yaml`,
  `wazuh-cluster-key.patch.yaml` — strategic-merge patches that override the base
  secrets' `data`, referenced from `kustomization.yml` under `patches:`.

The plaintext passwords match the bcrypt hashes; `deploy.sh` runs
`securityadmin.sh` to load them into the indexer security index, and prints the
generated admin password at the end.

## Consequences

- A fresh deployment uses strong, unique credentials — no public defaults.
- Because the kustomization now references generated files, you **must** run
  `generate-credentials.sh` (or `deploy.sh`) before `kubectl apply -k` — the same
  prerequisite that already applied to the generated TLS certs.
- Rotation = regenerate → `kubectl apply -k` → `init-security.sh` → restart
  consumers (see README → Credential Rotation).
- The demo users `kibanaro`/`logstash`/`readall`/`snapshotrestore` are dropped
  from `internal_users.yml` (they had known default hashes); re-add them to the
  generator template if you need them.
- `generate-credentials.sh` requires Docker (bcrypt hashing via the `httpd`
  image), which is already a documented prerequisite.
