---
name: release
description: "Prepare and execute a release, including version bumps, changelog generation, and tagging."
trigger: "When the user asks to create a release, bump versions, or prepare for a new version."
---

# release

## Overview

Manages the release process for the Wazuh deployment configuration, including updating image tags, generating changelogs, and creating git tags.

## Inputs

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `version` | Target Wazuh version (e.g., `4.14.1`) | Yes | — |
| `dry-run` | Preview changes without applying | No | `true` |

## Expected Outputs

- Updated image tags across all kustomization files
- Generated changelog from git history
- Git tag for the release

## Steps

1. Update `newTag` in `kubernetes/kustomization.yml` and overlay kustomization files.
2. Update `WAZUH_VERSION` in `config.env.example` and `deploy.sh` if applicable.
3. Generate changelog from commits since last tag.
4. Create commit and tag.
5. Summarise changes for review before push.
