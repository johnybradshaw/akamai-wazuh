---
title: "Never hardcode annotations that Kubernetes itself updates, or GitOps shows permanent drift"
author: John
date: 2026-11-09
standing: true
id: l-2ae29d49
scope: repo
status: active
src: init-review
touches:
  - kubernetes/kustomization.yml
---

## Watch out
- A common annotation pinned the Deployment revision to 1 on every resource. The cluster moved it to 3 after restarts, so the Deployment stayed out of sync and no sync could fix it. StatefulSets hid the problem only because Kubernetes never updates that annotation on them.
- In the code: Do not put `deployment.kubernetes.io/revision` in `commonAnnotations` in `kubernetes/kustomization.yml`. Keep only the `documentation` annotation.

_From PR #22 here, Aug 22._
