---
title: "Dashboard HTTPS cert needs a real hostname and SANs, since modern proxies ignore CN"
author: John
date: 2026-11-09
standing: true
id: l-23fb75df
scope: repo
status: active
src: init-review
---

## Decided
- The stock upstream generator makes a cert with a placeholder subject and no subjectAltName. Go-based proxies such as Traefik ignore CN, so nothing can verify it. That forces insecureSkipVerify on anything fronting the Dashboard.
- In the code: Do not use upstream `wazuh/certs/dashboard_http/generate_certs.sh` for the port 5601 cert. Generate it with a CN and SANs, as in the repo's cert scripts. This is separate from `dashboard.pem` in `generate-indexer-certs-with-sans.sh`.

_From PR #18 here, Aug 20._
