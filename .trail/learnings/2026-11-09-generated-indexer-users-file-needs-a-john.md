---
title: Generated indexer users file needs a metadata header or admin users silently never load
author: John
date: 2026-11-09
standing: true
id: l-80ae255e
scope: repo
status: active
src: init-review
---

## Watch out
- OpenSearch Security 7 rejects an internal users file without a `_meta` block. The securityadmin tool still reports success for the other eight documents, so the security index has roles but no users. The symptoms look like infrastructure faults: the Dashboard loops on errors and Filebeat gets 503.
- In the code: Keep the `_meta` header (type internalusers, config_version 2) in the `internal_users.yml` that `generate-credentials.sh` emits. Check that `securityadmin.sh` exits 0, not only that it prints SUCC lines.

_From PR #21 here, Aug 21._
