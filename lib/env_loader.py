"""
env_loader.py — Load env.vars from ~/.openclaw/openclaw.json for Python.

Resolution order: ENV vars already set take precedence → openclaw.json env.vars
Issue: nova-memory #98
"""

import json
import os
import sys
from pathlib import Path
from typing import Optional


def load_openclaw_env(config_path: Optional[str] = None) -> dict:
    """
    Load env vars from openclaw.json's env.vars section.

    Sets os.environ for each var and returns the resulting dict.
    ENV vars already set (non-empty) take precedence over config values.
    Null values in JSON are treated as absent.
    Malformed JSON is caught and warned about.
    """
    if config_path is None:
        config_path = os.path.join(Path.home(), ".openclaw", "openclaw.json")

    # Try to read config file
    config = {}
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
        if not isinstance(config, dict):
            print(f"WARNING: {config_path} is not a JSON object, ignoring", file=sys.stderr)
            config = {}
    except FileNotFoundError:
        return {}
    except (json.JSONDecodeError, PermissionError, IsADirectoryError, OSError) as e:
        print(f"WARNING: Failed to read {config_path}: {e}", file=sys.stderr)
        return {}

    # Extract env.vars
    env_section = config.get("env", {})
    if not isinstance(env_section, dict):
        return {}
    env_vars = env_section.get("vars", {})
    if not isinstance(env_vars, dict):
        return {}

    result = {}

    for key, value in env_vars.items():
        # ENV vars already set (non-empty) take precedence
        existing = os.environ.get(key, "")
        if existing:
            result[key] = existing
            continue

        # Set from config if value is non-null and non-empty
        if value is not None:
            str_val = str(value)
            if str_val:
                result[key] = str_val
                os.environ[key] = str_val

    return result
