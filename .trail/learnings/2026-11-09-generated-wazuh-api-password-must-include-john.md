---
title: Generated Wazuh API password must include a symbol or the manager breaks on later boots
author: John
date: 2026-11-09
standing: true
id: l-37097d6f
scope: repo
status: active
src: init-review
touches:
  - kubernetes/scripts/generate-credentials.sh
---

## Watch out
- The generator stripped every non-alphanumeric character, but the Wazuh API policy requires one. It fails with error 5007. Every deployment hit this, and the real fatal line was easy to miss behind the 5007 traceback.
- In the code: In `kubernetes/scripts/generate-credentials.sh`, keep a non-alphanumeric character in `WAZUH_API_PASSWORD`. It must match `^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$`.

_From PR #19 here, Aug 20._
