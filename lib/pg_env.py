"""
pg_env.py — Centralized PostgreSQL config loader for Python.

Per-field resolution order: section (when field is explicitly defined) → ENV vars → ~/.openclaw/postgres.json (flat keys) → defaults
Issue: nova-memory #94, nova-mind #320, nova-workspace #33
"""

import json
import os
import getpass
import sys
from pathlib import Path
from typing import Optional


# Mapping: JSON key → env var name
_FIELD_MAP = {
    "host": "PGHOST",
    "port": "PGPORT",
    "database": "PGDATABASE",
    "user": "PGUSER",
    "password": "PGPASSWORD",
}

# Defaults (None = no default, leave unset)
_DEFAULTS = {
    "PGHOST": "localhost",
    "PGPORT": "5432",
    "PGUSER": None,  # filled dynamically with getpass.getuser()
}

# State to make repeated calls with different sections safe.  os.environ is
# both the input (ENV overrides) and output (for child processes).  Without
# bookkeeping, a second call would see the values written by the first call
# as "external ENV overrides" and refuse to overwrite them.
#
# _PREVIOUS_ENV[var] = value before our last write (None = absent)
# _LAST_WRITTEN[var] = value we last wrote
_PREVIOUS_ENV: dict[str, Optional[str]] = {}
_LAST_WRITTEN: dict[str, str] = {}


def _restore_external_env() -> None:
    """Undo our own writes so the next read sees only external env values."""
    for env_var in _FIELD_MAP.values():
        last = _LAST_WRITTEN.get(env_var)
        if last is None:
            continue
        current = os.environ.get(env_var, "")
        if current == last:
            prev = _PREVIOUS_ENV.get(env_var)
            if prev is None:
                os.environ.pop(env_var, None)
            else:
                os.environ[env_var] = prev


def load_pg_env(config_path: Optional[str] = None, section: Optional[str] = None) -> dict:
    """
    Load PostgreSQL env vars with per-field resolution.

    Sets os.environ for each PG* var and returns the resulting dict.
    Empty ENV strings are treated as unset.
    Null values in JSON are treated as absent.
    Malformed JSON is caught and warned about (falls through to defaults).

    If `section` is provided and the config file contains a valid object for that
    key, a field defined in the section (non-null, non-empty) wins over ENV and
    top-level keys for that field only. Fields absent from the section preserve
    the existing ENV → flat-config → default chain.

    Because this function mutates os.environ, a later call with a different
    `section` fully overwrites any PG* vars set by an earlier call — no stale
    values leak to child processes.
    """
    if config_path is None:
        config_path = os.path.join(Path.home(), ".openclaw", "postgres.json")

    # Undo our own previous writes so we don't mistake them for external ENV.
    _restore_external_env()

    # Try to read config file
    config = {}
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
        if not isinstance(config, dict):
            print(f"WARNING: {config_path} is not a JSON object, ignoring", file=sys.stderr)
            config = {}
    except FileNotFoundError:
        pass
    except (json.JSONDecodeError, PermissionError, IsADirectoryError, OSError) as e:
        print(f"WARNING: Failed to read {config_path}: {e}, falling through to defaults", file=sys.stderr)
        config = {}

    # Resolve nested section if requested. A non-object section mirrors the
    # top-level object-type guard: warn and fall back to top-level keys.
    section_config = {}
    if section:
        section_value = config.get(section)
        if isinstance(section_value, dict):
            section_config = section_value
        elif section_value is not None:
            print(
                f"WARNING: {config_path}.{section} is not a JSON object, ignoring",
                file=sys.stderr,
            )

    result = {}

    for json_key, env_var in _FIELD_MAP.items():
        # 1. Check section config first when the section explicitly defines
        #    this field. Per-field precedence: a non-null, non-empty section
        #    value wins over ENV for that field. Fields absent from the section
        #    fall through to the ENV -> flat-config -> default chain below.
        section_val = section_config.get(json_key) if section_config else None
        if section_val is not None:
            str_val = str(section_val)
            if str_val:
                result[env_var] = str_val
                continue

        # 2. Check ENV (empty string = unset)
        env_val = os.environ.get(env_var, "")
        if env_val:
            result[env_var] = env_val
            continue

        # 3. Check top-level config file (None/null = absent, empty string = absent)
        cfg_val = config.get(json_key)
        if cfg_val is not None:
            str_val = str(cfg_val)
            if str_val:
                result[env_var] = str_val
                continue

        # 4. Apply default
        if env_var == "PGUSER":
            default = getpass.getuser()
        else:
            default = _DEFAULTS.get(env_var)

        if default is not None:
            result[env_var] = default

    # Update os.environ and bookkeeping.  Record the value that was present
    # before we overwrite it so the next call can restore the external baseline.
    for env_var in _FIELD_MAP.values():
        if env_var in result:
            _PREVIOUS_ENV[env_var] = os.environ.get(env_var)
            os.environ[env_var] = result[env_var]
            _LAST_WRITTEN[env_var] = result[env_var]
        else:
            if env_var in _LAST_WRITTEN:
                os.environ.pop(env_var, None)
            _PREVIOUS_ENV.pop(env_var, None)
            _LAST_WRITTEN.pop(env_var, None)

    return result
