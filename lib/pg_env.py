"""
pg_env.py — Centralized PostgreSQL config loader for Python.

Resolution order: ENV vars → ~/.openclaw/postgres.json → defaults
Issue: nova-memory #94
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


def load_pg_env(config_path: Optional[str] = None) -> dict:
    """
    Load PostgreSQL env vars with resolution: ENV → config file → defaults.

    Sets os.environ for each PG* var and returns the resulting dict.
    Empty ENV strings are treated as unset.
    Null values in JSON are treated as absent.
    Malformed JSON is caught and warned about (falls through to defaults).
    """
    if config_path is None:
        config_path = os.path.join(Path.home(), ".openclaw", "postgres.json")

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

    result = {}

    for json_key, env_var in _FIELD_MAP.items():
        # 1. Check ENV (empty string = unset)
        env_val = os.environ.get(env_var, "")
        if env_val:
            result[env_var] = env_val
            continue

        # 2. Check config file (None/null = absent, empty string = absent)
        cfg_val = config.get(json_key)
        if cfg_val is not None:
            str_val = str(cfg_val)
            if str_val:
                result[env_var] = str_val
                os.environ[env_var] = str_val
                continue

        # 3. Apply default
        if env_var == "PGUSER":
            default = getpass.getuser()
        else:
            default = _DEFAULTS.get(env_var)

        if default is not None:
            result[env_var] = default
            os.environ[env_var] = default

    return result
