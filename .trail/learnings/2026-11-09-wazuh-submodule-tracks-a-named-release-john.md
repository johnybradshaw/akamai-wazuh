---
title: "Wazuh submodule tracks a named release tag, not a loose commit"
author: John
date: 2026-11-09
standing: true
id: l-27134368
scope: repo
status: active
src: init-sessions
---

## Decided
- The submodule pointed at an orphaned commit with no named ref. Moving it to a release tag makes the version traceable and keeps it reachable upstream.
- In the code: Pin the Wazuh submodule to the `v4.14.9` tag. Upgrade by checking out a new release tag, not an arbitrary commit.

_From past Claude sessions here, Oct 26._
