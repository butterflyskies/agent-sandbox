#!/usr/bin/env python3
"""Produce a deterministic ownership and size inventory for a directory tree."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class Rule:
    path: str
    owner: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--ownership-map", required=True, type=Path)
    parser.add_argument("--budgets", required=True, type=Path)
    parser.add_argument("--budget-key", default="home_template_apparent_bytes")
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: expected a JSON object")
    return value


def load_rules(config: dict[str, Any]) -> tuple[list[Rule], str]:
    if config.get("schema_version") != 1:
        raise ValueError("ownership map: unsupported schema_version")

    default_owner = config.get("default_owner")
    if not isinstance(default_owner, str) or not default_owner:
        raise ValueError("ownership map: default_owner must be a non-empty string")

    raw_rules = config.get("rules")
    if not isinstance(raw_rules, list):
        raise ValueError("ownership map: rules must be an array")

    rules: list[Rule] = []
    seen: set[str] = set()
    for item in raw_rules:
        if not isinstance(item, dict):
            raise ValueError("ownership map: every rule must be an object")
        rule_path = item.get("path")
        owner = item.get("owner")
        if (
            not isinstance(rule_path, str)
            or not rule_path
            or rule_path.startswith("/")
            or rule_path == "."
            or ".." in Path(rule_path).parts
        ):
            raise ValueError(f"ownership map: invalid relative path {rule_path!r}")
        if not isinstance(owner, str) or not owner:
            raise ValueError(f"ownership map: invalid owner for {rule_path!r}")
        normalized = Path(rule_path).as_posix().rstrip("/")
        if normalized in seen:
            raise ValueError(f"ownership map: duplicate path {normalized!r}")
        seen.add(normalized)
        rules.append(Rule(normalized, owner))

    rules.sort(key=lambda rule: (-len(Path(rule.path).parts), rule.path))
    return rules, default_owner


def classify(relative_path: str, rules: list[Rule], default_owner: str) -> tuple[str, str]:
    for rule in rules:
        if relative_path == rule.path or relative_path.startswith(f"{rule.path}/"):
            return rule.owner, rule.path
    return default_owner, "<unclassified>"


def empty_metrics(owner: str, rule_path: str) -> dict[str, Any]:
    return {
        "path": rule_path,
        "owner": owner,
        "apparent_bytes": 0,
        "allocated_bytes": 0,
        "regular_files": 0,
        "directories": 0,
        "symlinks": 0,
        "other_entries": 0,
    }


def add_entry(metrics: dict[str, Any], entry_stat: os.stat_result) -> None:
    metrics["allocated_bytes"] += entry_stat.st_blocks * 512
    mode = entry_stat.st_mode
    if stat.S_ISREG(mode):
        metrics["regular_files"] += 1
        metrics["apparent_bytes"] += entry_stat.st_size
    elif stat.S_ISDIR(mode):
        metrics["directories"] += 1
    elif stat.S_ISLNK(mode):
        metrics["symlinks"] += 1
        metrics["apparent_bytes"] += entry_stat.st_size
    else:
        metrics["other_entries"] += 1
        metrics["apparent_bytes"] += entry_stat.st_size


def inventory(root: Path, rules: list[Rule], default_owner: str) -> dict[str, Any]:
    if not root.is_dir():
        raise ValueError(f"{root}: root must be an existing directory")

    by_rule: dict[str, dict[str, Any]] = {
        rule.path: empty_metrics(rule.owner, rule.path) for rule in rules
    }
    by_rule["<unclassified>"] = empty_metrics(default_owner, "<unclassified>")

    def visit(directory: Path, relative_directory: Path) -> None:
        with os.scandir(directory) as entries:
            for entry in sorted(entries, key=lambda item: os.fsencode(item.name)):
                relative = (relative_directory / entry.name).as_posix()
                owner, rule_path = classify(relative, rules, default_owner)
                entry_metrics = by_rule[rule_path]
                entry_stat = entry.stat(follow_symlinks=False)
                add_entry(entry_metrics, entry_stat)
                if stat.S_ISDIR(entry_stat.st_mode) and not stat.S_ISLNK(entry_stat.st_mode):
                    visit(Path(entry.path), relative_directory / entry.name)

    visit(root, Path())

    paths = sorted(by_rule.values(), key=lambda item: item["path"])
    totals = empty_metrics("all", "<total>")
    for path_metrics in paths:
        for key in (
            "apparent_bytes",
            "allocated_bytes",
            "regular_files",
            "directories",
            "symlinks",
            "other_entries",
        ):
            totals[key] += path_metrics[key]

    by_owner: dict[str, dict[str, Any]] = {}
    for path_metrics in paths:
        owner = path_metrics["owner"]
        owner_metrics = by_owner.setdefault(owner, empty_metrics(owner, "<owner-total>"))
        for key in (
            "apparent_bytes",
            "allocated_bytes",
            "regular_files",
            "directories",
            "symlinks",
            "other_entries",
        ):
            owner_metrics[key] += path_metrics[key]

    return {
        "schema_version": 1,
        "totals": totals,
        "owners": [by_owner[key] for key in sorted(by_owner)],
        "paths": paths,
    }


def apply_budget(
    report: dict[str, Any], budgets: dict[str, Any], budget_key: str
) -> bool:
    if budgets.get("schema_version") != 1:
        raise ValueError("budgets: unsupported schema_version")
    measurements = budgets.get("measurements")
    if not isinstance(measurements, dict) or budget_key not in measurements:
        raise ValueError(f"budgets: missing measurement {budget_key!r}")
    measurement = measurements[budget_key]
    if not isinstance(measurement, dict):
        raise ValueError(f"budgets: measurement {budget_key!r} must be an object")

    limit = measurement.get("max_bytes")
    if limit is not None and (not isinstance(limit, int) or isinstance(limit, bool) or limit < 0):
        raise ValueError(f"budgets: {budget_key}.max_bytes must be null or a non-negative integer")

    observed = report["totals"]["apparent_bytes"]
    status = "unconfigured" if limit is None else ("pass" if observed <= limit else "exceeded")
    report["budget"] = {
        "key": budget_key,
        "observed_bytes": observed,
        "max_bytes": limit,
        "status": status,
    }
    return status != "exceeded"


def main() -> int:
    args = parse_args()
    try:
        if args.output:
            resolved_root = args.root.resolve()
            resolved_output = args.output.resolve()
            if resolved_output == resolved_root or resolved_root in resolved_output.parents:
                raise ValueError("--output must be outside --root")
        ownership_map = load_json(args.ownership_map)
        budgets = load_json(args.budgets)
        rules, default_owner = load_rules(ownership_map)
        report = inventory(args.root, rules, default_owner)
        within_budget = apply_budget(report, budgets, args.budget_key)
        rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8")
        else:
            sys.stdout.write(rendered)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"storage-inventory: {error}", file=sys.stderr)
        return 1

    return 0 if within_budget else 2


if __name__ == "__main__":
    raise SystemExit(main())
