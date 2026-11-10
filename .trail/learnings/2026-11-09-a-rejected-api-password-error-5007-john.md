---
title: A rejected API password error 5007 does not crash the manager at first start
author: John
date: 2026-11-09
standing: true
id: l-3b5f20ff
scope: repo
status: active
src: init-review
---

## Watch out
- An earlier note claimed 5007 caused CrashLoopBackOff. In fact the init script exits 0, the API user is created and authenticates, and only later idempotent updates fail. Believing the wrong claim cost hours of misdirected debugging downstream.
- In the code: When a manager crashloops with 5007 in the log, don't assume 5007 is the cause. Look for the real fatal line, such as the `s6-svscanctl` supervisor error, further down. Keep the comment in `generate-credentials.sh` accurate.

_From PR #20 here, Aug 22._
