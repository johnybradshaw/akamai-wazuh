#!/usr/bin/env python3
"""Unit tests for deployment helper and Kustomize validation behaviour.

The tests create their generated certificates and credentials in a temporary
copy of the repository. They never read, overwrite, or remove operator-owned
secrets in the working tree.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
OVERLAY_FILES = (
    "internal_users.yml",
    "indexer-cred.patch.yaml",
    "dashboard-cred.patch.yaml",
    "wazuh-api-cred.patch.yaml",
    "wazuh-authd-pass.patch.yaml",
    "wazuh-cluster-key.patch.yaml",
)
CERTIFICATE_FILES = (
    "indexer_cluster/root-ca.pem",
    "indexer_cluster/node.pem",
    "indexer_cluster/node-key.pem",
    "indexer_cluster/dashboard.pem",
    "indexer_cluster/dashboard-key.pem",
    "indexer_cluster/admin.pem",
    "indexer_cluster/admin-key.pem",
    "indexer_cluster/filebeat.pem",
    "indexer_cluster/filebeat-key.pem",
    "dashboard_http/cert.pem",
    "dashboard_http/key.pem",
)


class DeploymentConfigurationTestCase(unittest.TestCase):
    """Render the deployment forms with non-sensitive fixtures."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.kubectl = shutil.which("kubectl")
        if not cls.kubectl:
            raise unittest.SkipTest("kubectl is required to render Kustomize configurations")

        cls.temporary_directory = tempfile.TemporaryDirectory()
        cls.repository = Path(cls.temporary_directory.name) / "akamai-wazuh"
        shutil.copytree(
            REPOSITORY_ROOT,
            cls.repository,
            ignore=shutil.ignore_patterns(
                ".git",
                "__pycache__",
                "*.pyc",
                "config.env",
                "deploy.log",
                ".credentials",
                "*.patch.yaml",
                "*.pem",
            ),
        )
        cls._write_validation_fixtures()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    @classmethod
    def _write_validation_fixtures(cls) -> None:
        overlay = cls.repository / "kubernetes/production-overlay"
        (overlay / "internal_users.yml").write_text(
            "_meta:\n  type: internalusers\n  config_version: 2\n",
            encoding="utf-8",
        )

        certificate_root = cls.repository / "kubernetes/wazuh-kubernetes/wazuh/certs"
        for relative_path in CERTIFICATE_FILES:
            target = certificate_root / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("unit-test fixture\n", encoding="utf-8")

        patches = {
            "indexer-cred.patch.yaml": ("indexer-cred", "  username: dGVzdA==\n  password: dGVzdA=="),
            "dashboard-cred.patch.yaml": ("dashboard-cred", "  username: dGVzdA==\n  password: dGVzdA=="),
            "wazuh-api-cred.patch.yaml": ("wazuh-api-cred", "  username: dGVzdA==\n  password: dGVzdA=="),
            "wazuh-authd-pass.patch.yaml": ("wazuh-authd-pass", "  authd.pass: dGVzdA=="),
            "wazuh-cluster-key.patch.yaml": ("wazuh-cluster-key", "  key: dGVzdA=="),
        }
        for filename, (secret_name, data) in patches.items():
            (overlay / filename).write_text(
                "apiVersion: v1\n"
                "kind: Secret\n"
                "metadata:\n"
                f"  name: {secret_name}\n"
                "data:\n"
                f"{data}\n",
                encoding="utf-8",
            )

    def _render(self, directory: str, *extra_arguments: str) -> str:
        result = subprocess.run(
            [self.kubectl, "kustomize", *extra_arguments, directory],
            cwd=self.repository,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(
            result.returncode,
            0,
            f"Kustomize render failed for {directory}: {result.stderr}",
        )
        return result.stdout

    def test_active_kustomization_renders_hardened_busybox_init_containers(self) -> None:
        rendered = self._render("kubernetes")

        self.assertEqual(
            rendered.count("image: dhi.io/busybox:1.37-alpine3.23"),
            3,
            "The active deployment must harden every Indexer BusyBox init container.",
        )
        self.assertIn("name: volume-mount-hack", rendered)
        self.assertIn("name: increase-the-vm-max-map-count", rendered)
        self.assertIn("name: sysctl", rendered)

    def test_standalone_overlay_renders_the_same_hardened_busybox_policy(self) -> None:
        rendered = self._render(
            "kubernetes/production-overlay",
            "--load-restrictor",
            "LoadRestrictionsNone",
        )

        self.assertEqual(
            rendered.count("image: dhi.io/busybox:1.37-alpine3.23"),
            3,
            "The standalone overlay must retain the active deployment's DHI policy.",
        )
        self.assertIn("name: indexer-certs", rendered)
        self.assertIn("name: dashboard-certs", rendered)
        self.assertIn("name: indexer-conf", rendered)

    def test_root_required_init_containers_are_explicitly_overridden(self) -> None:
        resources_patch = (
            REPOSITORY_ROOT / "kubernetes/production-overlay/indexer-resources.yaml"
        ).read_text(encoding="utf-8")

        for container_name in (
            "volume-mount-hack",
            "increase-the-vm-max-map-count",
            "sysctl",
        ):
            container_start = resources_patch.index(f"- name: {container_name}")
            container_end = resources_patch.find("\n        - name:", container_start + 1)
            container_block = resources_patch[container_start:]
            if container_end != -1:
                container_block = resources_patch[container_start:container_end]
            self.assertIn("runAsUser: 0", container_block)
            self.assertIn("runAsGroup: 0", container_block)


class ExternalDnsHelperTestCase(unittest.TestCase):
    """Verify the rendered ExternalDNS deployment helper template."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.script = (
            REPOSITORY_ROOT / "kubernetes/scripts/install-prerequisites.sh"
        ).read_text(encoding="utf-8")

    def test_external_dns_uses_pinned_hardened_image_and_linode_provider(self) -> None:
        helper_start = self.script.index("# Deploy ExternalDNS")
        helper_end = self.script.index("# Wait for ExternalDNS to be ready", helper_start)
        manifest = self.script[helper_start:helper_end]

        expected_fragments = (
            "image: dhi.io/external-dns:0.21.0-alpine3.23",
            "- --provider=linode",
            "- --registry=txt",
            "- --txt-owner-id=wazuh-k8s-cluster",
            "runAsNonRoot: true",
            "readOnlyRootFilesystem: true",
            'drop: ["ALL"]',
        )
        for fragment in expected_fragments:
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, manifest)


if __name__ == "__main__":
    unittest.main(verbosity=2)
