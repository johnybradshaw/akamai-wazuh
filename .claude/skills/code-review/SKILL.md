---
name: code-review
description: "Review bash scripts and Kustomize manifests for correctness, security, and adherence to project conventions."
trigger: "When the user asks to review code, check a script, or validate changes before committing."
---

# code-review

## Overview

Reviews code changes against project conventions defined in CLAUDE.md: `set -euo pipefail`, colour-coded logging functions, proper argument parsing, and Kustomize best practices.

## Inputs

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `target` | File path or git diff to review | Yes | staged changes |

## Expected Outputs

- List of issues categorised by severity (error, warning, suggestion)
- Specific line references and fix recommendations

## Steps

1. Identify changed files (from git diff or specified path).
2. For bash scripts: check for `set -euo pipefail`, logging function usage, proper quoting, shellcheck-style issues.
3. For Kustomize manifests: validate structure, check image tags, verify overlay consistency.
4. For security: check for hardcoded secrets, proper file permissions, credential handling.
5. Report findings with severity levels.
