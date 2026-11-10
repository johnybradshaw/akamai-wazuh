---
title: Ubuntu 26.04 CIS checks are deferred until Wazuh 5.0 is released
author: John
date: 2026-11-09
standing: true
id: l-48601834
scope: repo
status: active
src: init-sessions
---

## Decided
- The Ubuntu 26.04 CIS policy only ships in Wazuh 5.0, which is still pre-release. The team chose to upgrade to the latest stable 4.x and leave CIS support for later.
- In the code: Do not add Ubuntu 26.04 CIS/SCA content on 4.14.x. The repo has no SCA/CIS content today. Revisit once Wazuh 5.0 is GA.

_From past Claude sessions here, Oct 26._
