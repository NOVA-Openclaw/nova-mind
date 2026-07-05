#!/usr/bin/env python3
"""Test suite for lib/pg_env.py section-key support.

Covers TC-23 through TC-51 for the canonical Python loader, including the
nova-workspace#33 section-vs-ENV precedence fix.
"""

import json
import os
import shutil
import subprocess
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


def assert_true(desc, condition):
    global PASS, FAIL
    if condition:
        print(f"  PASS: {desc}")
        PASS += 1
    else:
        print(f"  FAIL: {desc}")
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


def run_isolated(config_data, env_updates, snippet):
    """Run a Python snippet in a subprocess with isolated $HOME and PG env.

    The snippet receives `config_path` pointing at a freshly-written
    postgres.json under a temp directory that is also $HOME, so loaders using
    the default ~/.openclaw/postgres.json path pick up the fixture.
    """
    tmpdir = tempfile.mkdtemp()
    try:
        cfg_path = write_config(tmpdir, config_data)
        env = os.environ.copy()
        for v in ("PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD"):
            env.pop(v, None)
        if env_updates:
            env.update(env_updates)
        env["HOME"] = tmpdir
        env["PYTHONPATH"] = str(Path(__file__).parent.parent) + os.pathsep + env.get("PYTHONPATH", "")
        script = f"""import os, sys
config_path = {repr(cfg_path)}
os.environ['TEST_CONFIG_PATH'] = config_path
{snippet}"""
        result = subprocess.run(
            [sys.executable, "-c", script],
            capture_output=True,
            text=True,
            env=env,
        )
        return result
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


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

    # TC-29 (rewritten): section field wins over ENV when section defines the field
    print("TC-29: section field wins over ENV when section defines the field")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    cfg_path = write_config(tmpdir + "/tc29", {
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))
    assert_env_eq("os.environ PGDATABASE", "PGDATABASE", "agent_chat")

    # TC-30: section field present + ENV set for same field → section wins
    print("TC-30: section field present + ENV set for same field -> section wins")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "nova_memory"
    cfg_path = write_config(tmpdir + "/tc30", {
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))
    assert_env_eq("os.environ PGDATABASE", "PGDATABASE", "agent_chat")

    # TC-31: section field present + ENV unset → section wins
    print("TC-31: section field present + ENV unset -> section wins")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc31", {
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))

    # TC-32: section=None + ENV set → ENV wins (unchanged legacy behavior)
    print("TC-32: section=None + ENV set -> ENV wins (legacy behavior)")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    cfg_path = write_config(tmpdir + "/tc32", {
        "database": "nova_memory",
    })
    result = pg_env.load_pg_env(cfg_path, section=None)
    assert_eq("PGDATABASE", "env_db", result.get("PGDATABASE"))

    # TC-33: field present in ENV but absent from section → ENV still wins for that field
    print("TC-33: ENV wins for fields omitted from section")
    pg_env = reload_pg_env()
    os.environ["PGUSER"] = "env_user"
    cfg_path = write_config(tmpdir + "/tc33", {
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE (section wins)", "agent_chat", result.get("PGDATABASE"))
    assert_eq("PGUSER (ENV wins)", "env_user", result.get("PGUSER"))

    # TC-34: empty-string value in section vs non-empty ENV
    print("TC-34: empty-string section value falls back to ENV")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    cfg_path = write_config(tmpdir + "/tc34", {
        "database": "nova_memory",
        "agent_chat": {"database": ""},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "env_db", result.get("PGDATABASE"))

    # TC-35: empty-string value in ENV vs present section field
    print("TC-35: empty-string ENV treated as unset, section wins")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = ""
    cfg_path = write_config(tmpdir + "/tc35", {
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))

    # TC-36: section name doesn't exist in config at all
    print("TC-36: missing section name falls through to ENV/flat/default chain")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    cfg_path = write_config(tmpdir + "/tc36", {
        "host": "flat-host",
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE", "env_db", result.get("PGDATABASE"))

    # TC-37: flat-key fallback interaction
    print("TC-37: section defines DB but not host; ENV defines host")
    pg_env = reload_pg_env()
    os.environ["PGHOST"] = "env-host"
    cfg_path = write_config(tmpdir + "/tc37", {
        "host": "flat-host",
        "database": "nova_memory",
        "agent_chat": {"database": "agent_chat"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGHOST (ENV wins)", "env-host", result.get("PGHOST"))
    assert_eq("PGDATABASE (section wins)", "agent_chat", result.get("PGDATABASE"))

    # TC-38: PGPASSWORD — section does NOT define password (real-world shape)
    print("TC-38: section silent on password preserves flat-config/.pgpass behavior")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc38", {
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {"database": "agent_chat", "user": "chat-user"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGPASSWORD", "flat-pass", result.get("PGPASSWORD"))

    # TC-39: PGPASSWORD — section DOES define password, ENV also set
    print("TC-39: section password wins over ENV (symmetry, not promoted usage)")
    pg_env = reload_pg_env()
    os.environ["PGPASSWORD"] = "env-pass"
    cfg_path = write_config(tmpdir + "/tc39", {
        "database": "nova_memory",
        "password": "flat-pass",
        "agent_chat": {"password": "chat-pass"},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    # Intentional symmetry with the per-field rule: a section-defined password
    # wins over ENV. This does NOT promote storing passwords in postgres.json;
    # it documents expected behavior if a section ever does define one.
    assert_eq("PGPASSWORD", "chat-pass", result.get("PGPASSWORD"))

    # TC-40: all 5 fields present in section simultaneously, ENV set for all 5
    print("TC-40: all 5 fields in section, all 5 in ENV -> section wins all")
    pg_env = reload_pg_env()
    os.environ.update({
        "PGHOST": "env-host",
        "PGPORT": "9999",
        "PGDATABASE": "env_db",
        "PGUSER": "env_user",
        "PGPASSWORD": "env-pass",
    })
    cfg_path = write_config(tmpdir + "/tc40", {
        "host": "flat-host",
        "port": 5432,
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {
            "host": "sect-host",
            "port": 5433,
            "database": "agent_chat",
            "user": "sect-user",
            "password": "sect-pass",
        },
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGHOST", "sect-host", result.get("PGHOST"))
    assert_eq("PGPORT", "5433", result.get("PGPORT"))
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))
    assert_eq("PGUSER", "sect-user", result.get("PGUSER"))
    assert_eq("PGPASSWORD", "sect-pass", result.get("PGPASSWORD"))

    # TC-41: all 5 fields present in section, ENV entirely unset
    print("TC-41: all 5 fields in section, ENV unset -> section wins all")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc41", {
        "host": "flat-host",
        "port": 5432,
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {
            "host": "sect-host",
            "port": 5433,
            "database": "agent_chat",
            "user": "sect-user",
            "password": "sect-pass",
        },
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGHOST", "sect-host", result.get("PGHOST"))
    assert_eq("PGPORT", "5433", result.get("PGPORT"))
    assert_eq("PGDATABASE", "agent_chat", result.get("PGDATABASE"))
    assert_eq("PGUSER", "sect-user", result.get("PGUSER"))
    assert_eq("PGPASSWORD", "sect-pass", result.get("PGPASSWORD"))

    # TC-42: section defines 0 of 5 fields (empty dict)
    print("TC-42: empty section dict behaves like no section")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    cfg_path = write_config(tmpdir + "/tc42", {
        "host": "flat-host",
        "port": 5432,
        "database": "nova_memory",
        "user": "flat-user",
        "password": "flat-pass",
        "agent_chat": {},
    })
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGDATABASE (ENV wins)", "env_db", result.get("PGDATABASE"))
    assert_eq("PGHOST (flat wins)", "flat-host", result.get("PGHOST"))
    assert_eq("PGUSER (flat wins)", "flat-user", result.get("PGUSER"))
    assert_eq("PGPASSWORD (flat wins)", "flat-pass", result.get("PGPASSWORD"))

    # TC-43: individually test each of the 5 fields in isolation
    print("TC-43: per-field independence (parametrized over 5 fields)")
    field_specs = [
        ("host", "PGHOST", "env-host", "sect-host"),
        ("port", "PGPORT", "9999", "5433"),
        ("database", "PGDATABASE", "env_db", "agent_chat"),
        ("user", "PGUSER", "env_user", "sect-user"),
        ("password", "PGPASSWORD", "env_pass", "sect-pass"),
    ]
    for json_key, env_var, env_val, sect_val in field_specs:
        pg_env = reload_pg_env()
        os.environ[env_var] = env_val
        cfg_path = write_config(tmpdir + f"/tc43_{json_key}", {
            json_key: "flat-val",
            "agent_chat": {json_key: sect_val},
        })
        result = pg_env.load_pg_env(cfg_path, section="agent_chat")
        assert_eq(f"{env_var} section wins", sect_val, result.get(env_var))

    # TC-44: malformed postgres.json unaffected by new precedence
    print("TC-44: malformed JSON with section falls through to defaults")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc44", "{not valid json")
    result = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("PGHOST", "localhost", result.get("PGHOST"))
    assert_eq("PGPORT", "5432", result.get("PGPORT"))
    assert_eq("PGUSER", getpass.getuser(), result.get("PGUSER"))
    assert_eq("PGDATABASE unset", None, result.get("PGDATABASE"))

    # TC-45: missing config file, section requested, ENV set
    print("TC-45: missing config file, section requested, ENV set -> ENV wins")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "env_db"
    result = pg_env.load_pg_env("/nonexistent/path/postgres.json", section="agent_chat")
    assert_eq("PGDATABASE", "env_db", result.get("PGDATABASE"))

    # TC-46: section present but not an object (regression guard)
    print("TC-46: section present but not an object (regression guard)")
    pg_env = reload_pg_env()
    cfg_path = write_config(tmpdir + "/tc46", {
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

    # TC-47: second call with different section overwrites stale env vars
    #         with a true external ENV baseline present
    print("TC-47: second call restores true external ENV baseline")
    pg_env = reload_pg_env()
    os.environ["PGDATABASE"] = "preexisting"
    cfg_path = write_config(tmpdir + "/tc47", {
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
    assert_eq("first call PGDATABASE", "preexisting", result1.get("PGDATABASE"))
    assert_env_eq("first call os.environ PGDATABASE", "PGDATABASE", "preexisting")

    result2 = pg_env.load_pg_env(cfg_path, section="agent_chat")
    assert_eq("second call PGDATABASE", "agent_chat", result2.get("PGDATABASE"))
    assert_eq("second call PGUSER", "chat-user", result2.get("PGUSER"))
    assert_env_eq("second call os.environ PGDATABASE", "PGDATABASE", "agent_chat")
    assert_env_eq("second call os.environ PGUSER", "PGUSER", "chat-user")

    # TC-48: domain integration — proactive-gate-check agent_chat DSN with gateway ENV export
    print("TC-48: proactive-gate-check agent_chat DSN ignores gateway PGDATABASE")
    repo_root = Path(__file__).parent.parent.parent.resolve()
    gate_script = repo_root / "motivation" / "scripts" / "proactive-gate-check.py"
    result = run_isolated(
        {
            "database": "nova_memory",
            "agent_chat": {"database": "agent_chat"},
        },
        {"PGDATABASE": "nova_memory"},
        f"""import importlib.util
spec = importlib.util.spec_from_file_location("proactive_gate_check", {str(gate_script)!r})
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod._dsn_from_pg_env(section="agent_chat"))""",
    )
    if result.returncode != 0:
        print(f"  FAIL: subprocess error: {result.stderr.strip()}")
        FAIL += 1
    else:
        dsn = result.stdout.strip()
        assert_true("DSN contains dbname=agent_chat", "dbname=agent_chat" in dsn)
        assert_true("DSN does not contain dbname=nova_memory", "dbname=nova_memory" not in dsn)

    # TC-49: domain integration — proactive-gate-check memory DSN still uses ENV
    print("TC-49: proactive-gate-check memory DSN still uses ENV")
    result = run_isolated(
        {
            "database": "nova_memory",
            "agent_chat": {"database": "agent_chat"},
        },
        {"PGDATABASE": "nova_memory"},
        f"""import importlib.util
spec = importlib.util.spec_from_file_location("proactive_gate_check", {str(gate_script)!r})
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod._dsn_from_pg_env(section=None))""",
    )
    if result.returncode != 0:
        print(f"  FAIL: subprocess error: {result.stderr.strip()}")
        FAIL += 1
    else:
        dsn = result.stdout.strip()
        assert_true("DSN contains dbname=nova_memory", "dbname=nova_memory" in dsn)

    # TC-50: domain integration — pg-notify-listener clean env
    print("TC-50: pg-notify-listener resolves both sections in clean env")
    notify_script = repo_root / "cognition" / "scripts" / "pg-notify-listener.py"
    result = run_isolated(
        {
            "host": "flat-host",
            "database": "nova_memory",
            "agent_chat": {"database": "agent_chat"},
        },
        {},
        f"""import importlib.util
spec = importlib.util.spec_from_file_location("pg_notify_listener", {str(notify_script)!r})
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod._pg_env.get("PGDATABASE"))
print(mod._agent_chat_env.get("PGDATABASE"))""",
    )
    if result.returncode != 0:
        print(f"  FAIL: subprocess error: {result.stderr.strip()}")
        FAIL += 1
    else:
        lines = [ln for ln in result.stdout.strip().splitlines() if ln]
        assert_eq("_pg_env PGDATABASE", "nova_memory", lines[0] if lines else None)
        assert_eq("_agent_chat_env PGDATABASE", "agent_chat", lines[1] if len(lines) > 1 else None)

    # TC-51: domain integration — pg-notify-listener with gateway ENV export
    print("TC-51: pg-notify-listener agent_chat ignores gateway PGDATABASE")
    result = run_isolated(
        {
            "host": "flat-host",
            "database": "nova_memory",
            "agent_chat": {"database": "agent_chat"},
        },
        {"PGDATABASE": "nova_memory"},
        f"""import importlib.util
spec = importlib.util.spec_from_file_location("pg_notify_listener", {str(notify_script)!r})
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod._pg_env.get("PGDATABASE"))
print(mod._agent_chat_env.get("PGDATABASE"))""",
    )
    if result.returncode != 0:
        print(f"  FAIL: subprocess error: {result.stderr.strip()}")
        FAIL += 1
    else:
        lines = [ln for ln in result.stdout.strip().splitlines() if ln]
        assert_eq("_pg_env PGDATABASE", "nova_memory", lines[0] if lines else None)
        assert_eq("_agent_chat_env PGDATABASE", "agent_chat", lines[1] if len(lines) > 1 else None)

print()
print("═══════════════════════════════════════════")
print(f"  Python section tests: {PASS} passed, {FAIL} failed")
print("═══════════════════════════════════════════")
sys.exit(0 if FAIL == 0 else 1)
