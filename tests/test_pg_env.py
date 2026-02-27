#!/usr/bin/env python3
"""Test suite for lib/pg_env.py"""

import json
import os
import sys
import tempfile
import getpass
from pathlib import Path

# Add lib to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

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


def assert_unset(desc, var):
    global PASS, FAIL
    if var not in os.environ:
        print(f"  PASS: {desc} ({var} unset)")
        PASS += 1
    else:
        print(f"  FAIL: {desc} ({var} should be unset, got='{os.environ[var]}')")
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


with tempfile.TemporaryDirectory() as tmpdir:
    # Must re-import fresh each test since it modifies os.environ
    import importlib
    import pg_env

    # TC-1.1: Config with all fields, no ENV
    print("TC-1.1: Config file with all fields, no ENV")
    clear_pg_vars()
    cfg_path = write_config(tmpdir + "/tc1", {
        "host": "dbhost", "port": 5433, "database": "testdb",
        "user": "testuser", "password": "secret123"
    })
    result = pg_env.load_pg_env(cfg_path)
    assert_eq("PGHOST", "dbhost", result.get("PGHOST"))
    assert_eq("PGPORT", "5433", result.get("PGPORT"))
    assert_eq("PGDATABASE", "testdb", result.get("PGDATABASE"))
    assert_eq("PGUSER", "testuser", result.get("PGUSER"))
    assert_eq("PGPASSWORD", "secret123", result.get("PGPASSWORD"))

    # TC-1.2: All ENV set
    print("TC-1.2: All ENV vars set, config exists")
    clear_pg_vars()
    os.environ.update({"PGHOST": "envhost", "PGPORT": "9999", "PGDATABASE": "envdb",
                        "PGUSER": "envuser", "PGPASSWORD": "envpass"})
    result = pg_env.load_pg_env(cfg_path)
    assert_eq("PGHOST", "envhost", result.get("PGHOST"))
    assert_eq("PGPORT", "9999", result.get("PGPORT"))
    assert_eq("PGDATABASE", "envdb", result.get("PGDATABASE"))

    # TC-1.4: Mixed
    print("TC-1.4: Mixed ENV + config")
    clear_pg_vars()
    os.environ["PGHOST"] = "remotehost"
    os.environ["PGPORT"] = "9999"
    result = pg_env.load_pg_env(cfg_path)
    assert_eq("PGHOST", "remotehost", result.get("PGHOST"))
    assert_eq("PGPORT", "9999", result.get("PGPORT"))
    assert_eq("PGDATABASE", "testdb", result.get("PGDATABASE"))
    assert_eq("PGUSER", "testuser", result.get("PGUSER"))

    # TC-2.1: No ENV, no config
    print("TC-2.1: No ENV, no config — defaults")
    clear_pg_vars()
    result = pg_env.load_pg_env("/nonexistent/path/postgres.json")
    assert_eq("PGHOST", "localhost", result.get("PGHOST"))
    assert_eq("PGPORT", "5432", result.get("PGPORT"))
    assert_eq("PGUSER", getpass.getuser(), result.get("PGUSER"))
    assert_eq("PGDATABASE unset", None, result.get("PGDATABASE"))
    assert_eq("PGPASSWORD unset", None, result.get("PGPASSWORD"))

    # TC-2.3: Empty string values
    print("TC-2.3: Config with empty strings")
    clear_pg_vars()
    cfg_path2 = write_config(tmpdir + "/tc2_3", {"host": "", "port": 5432, "user": ""})
    result = pg_env.load_pg_env(cfg_path2)
    assert_eq("PGHOST defaults", "localhost", result.get("PGHOST"))
    assert_eq("PGUSER defaults", getpass.getuser(), result.get("PGUSER"))

    # TC-3.4: Null values
    print("TC-3.4: Null values in JSON")
    clear_pg_vars()
    cfg_path3 = write_config(tmpdir + "/tc3_4", {"host": None, "port": 5432})
    result = pg_env.load_pg_env(cfg_path3)
    assert_eq("PGHOST null->default", "localhost", result.get("PGHOST"))
    assert_eq("PGPORT", "5432", result.get("PGPORT"))

    # TC-3.5: Empty ENV string
    print("TC-3.5: ENV set to empty string")
    clear_pg_vars()
    os.environ["PGHOST"] = ""
    result = pg_env.load_pg_env(cfg_path)  # config has host=dbhost
    assert_eq("PGHOST empty->config", "dbhost", result.get("PGHOST"))

    # TC-4.1: Malformed JSON
    print("TC-4.1: Malformed JSON")
    clear_pg_vars()
    cfg_bad = write_config(tmpdir + "/tc4_1", "{invalid json")
    result = pg_env.load_pg_env(cfg_bad)
    assert_eq("PGHOST malformed->default", "localhost", result.get("PGHOST"))

    # TC-3.2: Port as string
    print("TC-3.2: Port as string in JSON")
    clear_pg_vars()
    cfg_str = write_config(tmpdir + "/tc3_2", {"port": "5433"})
    result = pg_env.load_pg_env(cfg_str)
    assert_eq("PGPORT string", "5433", result.get("PGPORT"))

    # TC-3.3: Port as integer
    print("TC-3.3: Port as integer in JSON")
    clear_pg_vars()
    cfg_int = write_config(tmpdir + "/tc3_3", {"port": 5433})
    result = pg_env.load_pg_env(cfg_int)
    assert_eq("PGPORT int", "5433", result.get("PGPORT"))

print()
print("═══════════════════════════════════════════")
print(f"  Python tests: {PASS} passed, {FAIL} failed")
print("═══════════════════════════════════════════")
sys.exit(0 if FAIL == 0 else 1)
