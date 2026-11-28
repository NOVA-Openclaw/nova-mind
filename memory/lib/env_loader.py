"""
env_loader.py — Resolve secrets via nova-op and export them into the environment.

Design:
  - Reads a JSON item map (default: ~/.openclaw/scripts/nova-op-item-map.json).
  - load_openclaw_env(keys=[...]) resolves only the requested keys, skipping any
    that are already set and non-empty in os.environ.
  - load_openclaw_env() with no keys preserves the legacy behaviour of resolving
    every non-metadata entry in the item map.
  - Per-process cache keyed by (normalized config_path, var) avoids redundant
    nova-op subprocess calls.
  - nova-op is located via PATH, falling back to $HOME/.local/bin/nova-op.
  - Transient nova-op problems (missing binary, timeout, non-zero exit, empty
    value) warn to stderr and skip the key.
  - Map/config authoring problems (missing/unreadable map, malformed JSON,
    incomplete entry, placeholders) still raise RuntimeError.
  - Never reads .env, secrets.env, .bash_env, or openclaw.json env.vars for
    secret values.

Issue: nova-workspace#309 / nova-mind#818
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Iterable, Optional


# Per-process cache of nova-op resolved values: {(config_path, var): value}
_RESOLVED_CACHE: dict[tuple[str, str], str] = {}


def _default_config_path() -> str:
    return os.path.join(Path.home(), ".openclaw", "scripts", "nova-op-item-map.json")


def _nova_op_bin() -> Optional[str]:
    """Return the path to the nova-op binary, or None if it cannot be found.

    Resolution order:
      1. shutil.which("nova-op") on PATH.
      2. $HOME/.local/bin/nova-op if it exists and is executable.
    """
    bin_path = shutil.which("nova-op")
    if bin_path is not None:
        return bin_path
    home_fallback = os.path.join(Path.home(), ".local", "bin", "nova-op")
    if os.path.isfile(home_fallback) and os.access(home_fallback, os.X_OK):
        return home_fallback
    return None


def _load_config(config_path: str) -> dict:
    """Load and validate the item map. Raises RuntimeError on config errors."""
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

    return config


def _resolve_secret(
    var: str,
    item: str,
    field: str,
    vault: str,
    nova_op: str,
    timeout_s: float,
) -> Optional[str]:
    """Resolve a single secret via nova-op. Returns None (and warns) on failure."""
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
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired:
        print(
            f"env_loader: timeout resolving {var} via nova-op "
            f"(item={item} field={field} vault={vault})",
            file=sys.stderr,
        )
        return None
    except subprocess.CalledProcessError as exc:
        # Include stderr if present, but never the value (it is empty on failure).
        detail = exc.stderr.strip() if exc.stderr else f"exit code {exc.returncode}"
        print(
            f"env_loader: failed to resolve {var} "
            f"(item={item} field={field} vault={vault}): {detail}",
            file=sys.stderr,
        )
        return None
    except FileNotFoundError:
        print(
            f"env_loader: nova-op binary disappeared while resolving {var}",
            file=sys.stderr,
        )
        return None

    value = result.stdout.strip()
    if not value:
        print(
            f"env_loader: resolved empty value for {var} "
            f"(item={item} field={field} vault={vault})",
            file=sys.stderr,
        )
        return None
    return value


def load_openclaw_env(
    config_path: Optional[str] = None,
    keys: Optional[Iterable[str]] = None,
    timeout_s: float = 15,
) -> dict:
    """
    Load secrets from the nova-op item map and export them into os.environ.

    Args:
        config_path: Path to the item map. Defaults to
            ~/.openclaw/scripts/nova-op-item-map.json.
        keys: If provided, resolve only these variable names. A key already
            set and non-empty in os.environ is skipped. An empty list (or a
            list where every key is already present in os.environ) returns
            {} immediately without opening the item map or touching nova-op.
            If None, the legacy full-resolve behaviour is used: every
            non-metadata entry in the map is attempted.
        timeout_s: Per-key subprocess timeout in seconds (default 15).

    Returns:
        A dict of var -> value for everything that was set or kept.

    Raises:
        RuntimeError on map/config authoring problems (missing/unreadable map,
        malformed JSON, incomplete entry, placeholders). Transient nova-op
        failures (missing binary, timeout, non-zero exit, empty value) warn
        to stderr and skip the affected key.
    """
    if config_path is None:
        config_path = _default_config_path()
    config_path = os.path.abspath(config_path)

    # Determine the set of variables we need to resolve.
    result: dict[str, str] = {}
    if keys is None:
        # Legacy mode: load the map up front so we know every key to attempt.
        config = _load_config(config_path)
        target_vars = [
            var for var, entry in config.items()
            if not var.startswith("_") and isinstance(entry, dict)
        ]
        if not target_vars:
            raise RuntimeError(
                f"env_loader: no secret entries found in item map: {config_path}"
            )
    else:
        target_vars = [var for var in keys if not var.startswith("_")]
        if not target_vars:
            return {}
        # We don't need the map yet; short-circuit if everything is already set.
        still_needed = []
        for var in target_vars:
            existing = os.environ.get(var, "").strip()
            if existing:
                result[var] = existing
            else:
                still_needed.append(var)
        if not still_needed:
            return result
        target_vars = still_needed
        config = _load_config(config_path)

    # In legacy mode, separate already-set keys from keys that need resolving.
    if keys is None:
        still_needed = []
        for var in target_vars:
            existing = os.environ.get(var, "").strip()
            if existing:
                result[var] = existing
            else:
                still_needed.append(var)
        target_vars = still_needed
        if not target_vars:
            return result

    nova_op = _nova_op_bin()
    if nova_op is None:
        print(
            "env_loader: nova-op not found in PATH or $HOME/.local/bin/nova-op",
            file=sys.stderr,
        )
        for var in target_vars:
            print(
                f"env_loader: could not resolve {var} (nova-op unavailable)",
                file=sys.stderr,
            )
        return result

    errors: list[str] = []

    for var in target_vars:
        # In legacy mode metadata keys were already filtered. In targeted mode
        # an explicitly requested metadata key is silently ignored.
        if var.startswith("_"):
            continue

        entry = config.get(var)
        if entry is None:
            print(
                f"env_loader: requested key {var} not found in item map",
                file=sys.stderr,
            )
            continue
        if not isinstance(entry, dict):
            errors.append(f"incomplete map entry for {var}")
            continue

        item = str(entry.get("item") or "").strip()
        field = str(entry.get("field") or "").strip()
        vault = str(entry.get("vault") or "").strip()

        if not item or not field or not vault:
            errors.append(f"incomplete map entry for {var}")
            continue

        # Reject placeholder values that have not been replaced.
        if item == "REPLACE_WITH_ITEM_ID" or vault == "REPLACE_WITH_VAULT_ID":
            errors.append(
                f"{var} still contains placeholder values in {config_path}; "
                "replace them with real vault/item IDs"
            )
            continue

        cache_key = (config_path, var)
        if cache_key in _RESOLVED_CACHE:
            value = _RESOLVED_CACHE[cache_key]
            os.environ[var] = value
            result[var] = value
            continue

        value = _resolve_secret(var, item, field, vault, nova_op, timeout_s)
        if value is None:
            continue

        _RESOLVED_CACHE[cache_key] = value
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
