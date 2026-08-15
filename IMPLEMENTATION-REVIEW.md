# Implementation Review

## Outcome

The deployment configuration has been hardened and made testable. Compatible helper images now use Docker Hardened Images (DHI), both supported Kustomize configurations render successfully with non-sensitive fixtures, and continuous validation has been added.

| Area | Finding | Implemented resolution |
|---|---|---|
| BusyBox init containers | The deployment used mutable upstream BusyBox references. DHI BusyBox defaults to a non-root user, which would break the upstream `chown` and privileged `sysctl` tasks without an explicit override. | Replaced all rendered BusyBox references in the active and standalone Kustomizations with `dhi.io/busybox:1.37-alpine3.23`. Added explicit UID/GID `0` only to the Indexer init containers that require it. |
| ExternalDNS | The prerequisite installer used ExternalDNS `v0.14.0`. A compatible DHI ExternalDNS `0.21.0` image exists, and the existing Linode provider configuration remains supported. | Replaced the image with `dhi.io/external-dns:0.21.0-alpine3.23`; preserved the existing least-privilege pod security context and provider arguments. |
| Standalone production overlay | Its Wazuh submodule paths were stale, its credential generator attempted to replace a secret that does not exist, and its multi-document service patch was declared with an incompatible shared target. The overlay could not render. | Corrected upstream paths, restored certificate and ConfigMap generators, applied generated credential patches to the correct secrets, and used the appropriate multi-document strategic-merge declaration. |
| Regression control | There was no automated verification of maintained scripts or rendered configuration. | Added `.github/workflows/validate.yml`, covering shell syntax, non-sensitive generated fixtures, both Kustomization render paths, and final DHI reference checks. |
| Operator documentation | The active deployment path and hardened-helper policy were not documented accurately. | Updated the README with the active Kustomization location, DHI policy, and Wazuh version-update guidance. |

## Validation Completed

| Check | Result |
|---|---|
| Maintained shell scripts parsed with `bash -n` | Passed |
| Active `kubernetes/` Kustomization rendered with generated non-sensitive fixtures | Passed |
| Standalone `kubernetes/production-overlay/` Kustomization rendered with explicit cross-directory loading | Passed |
| Expected DHI BusyBox references in both rendered outputs | Three in each output |
| ExternalDNS DHI image reference | Present |
| Changed Kubernetes and workflow YAML parsed successfully | Passed |
| `git diff --check` | Passed |
| Pinned Wazuh submodule working tree | Clean |

## Deliberately Deferred Change

The bcrypt password-generation helper still uses `httpd:2.4-alpine`. Docker publishes a hardened Apache HTTP Server image, but this repository invokes the non-server `htpasswd` utility directly. Docker’s public DHI runtime guide documents the daemon, `httpd-foreground`, and `apachectl`, but does not explicitly document `htpasswd`; replacing this image without a pull-and-execution compatibility test could break credential generation. It should be migrated only after a CI test confirms `dhi.io/httpd` exposes a compatible `htpasswd` binary and output format.[1]

The Kustomize renderer also warns that `commonLabels` is deprecated. It is non-blocking, but replacing it with the modern `labels` field should be done in a separate, rendered-diff-reviewed change rather than coupled to the security migration.

## References

[1] [Docker Hardened Images — Apache HTTP Server guide](https://hub.docker.com/hardened-images/catalog/dhi/httpd/guides)

[2] [Docker Hardened Images — BusyBox catalog](https://hub.docker.com/hardened-images/catalog/dhi/busybox)

[3] [Docker Hardened Images — ExternalDNS catalog](https://hub.docker.com/hardened-images/catalog/dhi/external-dns)

[4] [ExternalDNS v0.21 Linode tutorial](https://github.com/kubernetes-sigs/external-dns/blob/v0.21.0/docs/tutorials/linode.md)
