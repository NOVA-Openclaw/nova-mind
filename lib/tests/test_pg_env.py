#!/usr/bin/env python3
"""Test suite for lib/pg_env.py section-key support.

Covers TC-23 through TC-29 for the canonical Python loader.
"""

import json
import os
import sys
import tempfile
import importlib
import getpass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

PASS = 0
FAIL = 0


def assert_eq(desc, expected, actual):
    global PASS, FAIL
    if expected == actual:
        print(f"  PASS: {desc}")
        PASS += 1
    else:
        print(f"  FAIL: {desc} (expected='{expected}', got='{actual}')")
        FAIL += 1


def assert_env_eq(desc, env_var, expected):
    global PASS, FAIL
    actual = os.environ.get(env_var)
    if expected == actual:
        print(f"  PASS: {desc}")
        PASS += 1
    else:
        print(f"  FAIL: {desc} (expected='{expected}', got='{actual}')")
        FAIL += 1


def clear_pg_vars():
    for v in ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"):
        os.environ.pop(v, None)


def write_config(tmpdir, data):
    d = os.path.join(tmpdir, ".openclaw")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "postgres.json")
    if isinstance(data, str):
        with open(path, "w") as f:
            f.write(data)
    else:
        with open(path, "w") as f:
            json.dump(data, f)
    return path


def reload_pg_env():
    """Import a fresh copy of pg_env so module-level state is isolated."""
    clear_pg_vars()
    if "pg_env" in sys.modules:
        del sys.modules["pg_env"]
    import pg_env

    return pg_env


with tempfile.TemporaryDirectory() as tmpdir:
    # TC-23: Section present and valid uses section fields
    print("TC-23: section present and valid uses section fields")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc23", {
        "host": "flat-host",
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {
            "database": "agent_chat",
            "user": "chat-user",
            "password": "chat-pass",
        },
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))
    assert_eq("PGUSER", "chat-user", result.get("PGUSER"))
    assert_eq("PGPASSWORD", "chat-pass", result.get("PGPASSWORD"))
    assert_eq("PGHOST", "flat-host", result.get("PGHOST"))
    assert_eq("PGPORT", "5432", result.get("PGPORT"))

    # TC-24: Section absent falls back to flat keys
    print("TC-24: section absent falls back to flat keys")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc24", {
        "host": "flat-host",
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "nova_memory", result.get("PGDATABASE"))
    assert_eq("PGUSER", "flat-user", result.get("PGUSER"))
    assert_eq("PGPASSWORD", "flat-pass", result.get("PGPASSWORD"))
    assert_eq("PGHOST", "flat-host", result.get("PGHOST"))

    # TC-25: Partial section falls back per field
    print("TC-25: partial section falls back per field")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc25", {
        "host": "flat-host",
        "port": 5433,
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {
            "database": "agent_chat",
            "user": "chat-user",
        },
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))
    assert_eq("PGUSER", "chat-user", result.get("PGUSER"))
    assert_eq("PGHOST", "flat-host", result.get("PGHOST"))
    assert_eq("PGPORT", "5433", result.get("PGPORT"))
    assert_eq("PGPASSWORD", "flat-pass", result.get("PGPASSWORD"))

    # TC-26: Malformed JSON falls through to defaults
    print("TC-26: malformed JSON falls through to defaults")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc26", "{not valid json")
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGHOST", "localhost", result.get("PGHOST"))
    assert_eq("PGPORT", "5432", result.get("PGPORT"))
    assert_eq("PGUSER", getpass.getuser(), result.get("PGUSER"))
    assert_eq("PGDATABASE unset", None, result.get("PGDATABASE"))

    # TC-27: Section present but not an object
    print("TC-27: section present but not an object")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc27", {
        "host": "flat-host",
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": "oops",
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "nova_memory", result.get("PGDATABASE"))
    assert_eq("PGUSER", "flat-user", result.get("PGUSER"))
    assert_eq("PGHOST", "flat-host", result.get("PGHOST"))

    # TC-28: Second call with section overwrites previously-set PG* env vars
    print("TC-28: second call with section overwrites stale env vars")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc28", {
        "host": "flat-host",
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {
            "database": "agent_chat",
            "user": "chat-user",
            "password": "chat-pass",
        },
    })
    result1 = pg_env.load_pg_env(cfg_path)
    assert_eq("first call PGDATABASE", "nova_memory", result1.get("PGDATABASE"))
    assert_env_eq("first call os.environ PGDATABASE", "PGDATABASE", "nova_memory")

    result2 = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("second call PGDATABASE", "agent_chat", result2.get("PGDATABASE"))
    assert_eq("second call PGUSER", "chat-user", result2.get("PGUSER"))
    assert_env_eq("second call os.environ PGDATABASE", "PGDATABASE", "agent_chat")
    assert_env_eq("second call os.environ PGUSER", "PGUSER", "chat-user")

    # TC-29: ENV override still wins over section
    print("TC-29: ENV override still wins over section")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    cfg_path = write_config(tmpdir + "/tc29", {
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "env_db", result.get("PGDATABASE"))
    assert_env_eq("os.environ PGDATABASE", "PGDATABASE", "env_db")

print()
print("═══════════════════════════════════════════")
print(f"  Python section tests: {PASS} passed, {FAIL} failed")
print("═══════════════════════════════════════════")
sys.exit(0 if FAIL == 0 else 1)
