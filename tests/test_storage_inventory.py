#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "storage-inventory.py"


class StorageInventoryTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.tree = self.root / "tree"
        self.tree.mkdir()
        self.ownership_map = self.root / "ownership.json"
        self.budgets = self.root / "budgets.json"
        self.ownership_map.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "default_owner": "unclassified",
                    "rules": [
                        {"path": ".tools", "owner": "image-owned-software"},
                        {"path": ".tools/config", "owner": "image-owned-default"},
                        {"path": "state", "owner": "construct-owned-state"},
                    ],
                }
            ),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_budgets(self, maximum: int | None) -> None:
        self.budgets.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "measurements": {
                        "home_template_apparent_bytes": {"max_bytes": maximum}
                    },
                }
            ),
            encoding="utf-8",
        )

    def run_inventory(self, *extra_arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--root",
                str(self.tree),
                "--ownership-map",
                str(self.ownership_map),
                "--budgets",
                str(self.budgets),
                *extra_arguments,
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def populate_tree(self) -> None:
        (self.tree / ".tools" / "config").mkdir(parents=True)
        (self.tree / "state").mkdir()
        (self.tree / "misc").mkdir()
        (self.tree / ".tools" / "runtime").write_bytes(b"tool")
        (self.tree / ".tools" / "config" / "default").write_bytes(b"cfg")
        (self.tree / "state" / "memory").write_bytes(b"memory")
        (self.tree / "misc" / "note").write_bytes(b"note")
        os.symlink("runtime", self.tree / ".tools" / "runtime-link")

    def test_inventory_is_deterministic_and_uses_longest_path_rule(self) -> None:
        self.populate_tree()
        self.write_budgets(None)

        first = self.run_inventory()
        second = self.run_inventory()

        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        report = json.loads(first.stdout)
        paths = {item["path"]: item for item in report["paths"]}
        self.assertEqual(paths[".tools"]["apparent_bytes"], 11)
        self.assertEqual(paths[".tools"]["regular_files"], 1)
        self.assertEqual(paths[".tools"]["symlinks"], 1)
        self.assertEqual(paths[".tools/config"]["apparent_bytes"], 3)
        self.assertEqual(paths["state"]["apparent_bytes"], 6)
        self.assertEqual(paths["<unclassified>"]["apparent_bytes"], 4)
        self.assertEqual(report["budget"]["status"], "unconfigured")

    def test_configured_budget_passes_at_exact_limit(self) -> None:
        (self.tree / "payload").write_bytes(b"1234")
        self.write_budgets(4)

        result = self.run_inventory()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["budget"]["status"], "pass")

    def test_configured_budget_exits_two_when_exceeded(self) -> None:
        (self.tree / "payload").write_bytes(b"12345")
        self.write_budgets(4)

        result = self.run_inventory()

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(json.loads(result.stdout)["budget"]["status"], "exceeded")

    def test_invalid_ownership_path_fails_closed(self) -> None:
        self.ownership_map.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "default_owner": "unclassified",
                    "rules": [{"path": "../escape", "owner": "bad"}],
                }
            ),
            encoding="utf-8",
        )
        self.write_budgets(None)

        result = self.run_inventory()

        self.assertEqual(result.returncode, 1)
        self.assertIn("invalid relative path", result.stderr)

    def test_output_inside_inventory_root_fails_without_changing_tree(self) -> None:
        (self.tree / "payload").write_bytes(b"1234")
        self.write_budgets(None)
        output = self.tree / "inventory.json"

        result = self.run_inventory("--output", str(output))

        self.assertEqual(result.returncode, 1)
        self.assertIn("--output must be outside --root", result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
