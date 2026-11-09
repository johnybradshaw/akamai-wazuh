---
title: "Pin every GitHub Actions reference to a full commit SHA, and keep reviews in the wiki"
author: John
date: 2026-11-09
standing: true
id: l-ae0a18fb
scope: repo
status: active
src: init-review
---

## Decided
- Major tags are mutable and the change shows no diff in the repo. A later workflow was missed in the first pinning pass. In-repo markdown is limited to documentation that must live with the code.
- In the code: In `.github/workflows/*.yml` use full SHAs, for example checkout `3d3c42e5aac5ba805825da76410c181273ba90b1`. Put one-off review records in the wiki, not in `docs/`.

_From PR #15 here, Aug 15._
