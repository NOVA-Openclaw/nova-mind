"""
env_loader.py — Resolve secrets via nova-op and export them into the environment.

Design:
  - Reads a JSON item map (default: ~/.openclaw/scripts/nova-op-item-map.json).
  - For each variable in the map that is not already set and non-empty,
    resolves the value by calling `nova-op item get ... --reveal`.
  - Fails loudly on missing nova-op, unreadable map, or resolution failure.
  - Never reads .env, secrets.env, .bash_env, or openclaw.json env.vars for
    secret values.

Issue: nova-workspace#309
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional


def _default_config_path() -> str:
    return os.path.join(Path.home(), ".openclaw", "scripts", "nova-op-item-map.json")


def _nova_op_bin() -> str:
    bin_path = shutil.which("nova-op")
    if bin_path is None:
        raise RuntimeError("env_loader: nova-op not found in PATH")
    return bin_path


def _resolve_secret(var: str, item: str, field: str, vault: str, nova_op: str) -> str:
    """Resolve a single secret via nova-op. Never returns an empty value."""
    cmd = [
        nova_op,
        "item",
        "get",
        item,
        "--vault",
        vault,
        "--field",
        field,
        "--reveal",
    ]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as exc:
        # Include stderr if present, but never the value (it is empty on failure).
        detail = exc.stderr.strip() if exc.stderr else f"exit code {exc.returncode}"
        raise RuntimeError(
            f"env_loader: failed to resolve {var} "
            f"(item={item} field={field} vault={vault}): {detail}"
        ) from exc
    except FileNotFoundError as exc:
        raise RuntimeError(f"env_loader: nova-op not found in PATH") from exc

    value = result.stdout.strip()
    if not value:
        raise RuntimeError(
            f"env_loader: resolved empty value for {var} "
            f"(item={item} field={field} vault={vault})"
        )
    return value


def load_openclaw_env(config_path: Optional[str] = None) -> dict:
    """
    Load secrets from the nova-op item map and export them into os.environ.

    Returns a dict of var -> value for everything that was set or kept.
    Raises RuntimeError on any resolution failure so callers fail loudly.
    """
    if config_path is None:
        config_path = _default_config_path()

    nova_op = _nova_op_bin()

    if not os.path.isfile(config_path):
        raise RuntimeError(f"env_loader: item map not found: {config_path}")
    if not os.access(config_path, os.R_OK):
        raise RuntimeError(f"env_loader: item map not readable: {config_path}")

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"env_loader: item map is not valid JSON: {config_path}") from exc
    except (OSError, PermissionError) as exc:
        raise RuntimeError(f"env_loader: could not read item map: {config_path}") from exc

    if not isinstance(config, dict):
        raise RuntimeError(f"env_loader: item map must be a JSON object: {config_path}")

    secret_vars = [
        var for var, entry in config.items()
        if not var.startswith("_") and isinstance(entry, dict)
    ]
    if not secret_vars:
        raise RuntimeError(f"env_loader: no secret entries found in item map: {config_path}")

    result: dict[str, str] = {}
    errors: list[str] = []

    for var, entry in config.items():
        # Skip metadata/comment keys.
        if var.startswith("_"):
            continue
        if not isinstance(entry, dict):
            errors.append(f"incomplete map entry for {var}")
            continue

        # Already set and non-empty: keep existing value (plugin-injected keys win).
        existing = os.environ.get(var, "").strip()
        if existing:
            result[var] = existing
            continue

        item = str(entry.get("item") or "").strip()
        field = str(entry.get("field") or "").strip()
        vault = str(entry.get("vault") or "").strip()

        if not item or not field or not vault:
            errors.append(f"incomplete map entry for {var}")
            continue

        try:
            value = _resolve_secret(var, item, field, vault, nova_op)
        except RuntimeError as exc:
            errors.append(str(exc))
            continue

        os.environ[var] = value
        result[var] = value

    if errors:
        raise RuntimeError("env_loader: " + "; ".join(errors))

    return result


if __name__ == "__main__":
    # Allow ad-hoc execution for testing / cron wrappers.
    try:
        load_openclaw_env(sys.argv[1] if len(sys.argv) > 1 else None)
    except RuntimeError as exc:
        print(exc, file=sys.stderr)
        sys.exit(1)
