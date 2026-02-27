#!/usr/bin/env python3
"""
test_env_loader.py — Test runner for lib/env_loader.py
Issue: nova-memory #98
"""

import io
import json
import os
import sys
import tempfile
import stat

# Add lib/ to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from env_loader import load_openclaw_env

PASS = 0
FAIL = 0


def pass_test(name):
    global PASS
    print(f"PASS: {name}")
    PASS += 1


def fail_test(name, reason):
    global FAIL
    print(f"FAIL: {name} — {reason}")
    FAIL += 1


def write_config(data, tmpdir=None):
    """Write a config file and return its path."""
    if tmpdir is None:
        tmpdir = tempfile.mkdtemp()
    path = os.path.join(tmpdir, "openclaw.json")
    if isinstance(data, str):
        with open(path, "w") as f:
            f.write(data)
    else:
        with open(path, "w") as f:
            json.dump(data, f)
    return path


def clean_env(*keys):
    for k in keys:
        os.environ.pop(k, None)


# ── TEST 1.2: loads vars from valid config ──
def test_python_loads_vars_from_valid_config():
    name = "TEST-1.2: loads vars from valid config"
    clean_env("FOO", "BAZ")
    cfg = write_config({"env": {"vars": {"FOO": "bar", "BAZ": "qux"}}})
    result = load_openclaw_env(config_path=cfg)
    if result == {"FOO": "bar", "BAZ": "qux"} and os.environ.get("FOO") == "bar" and os.environ.get("BAZ") == "qux":
        pass_test(name)
    else:
        fail_test(name, f"result={result}, FOO={os.environ.get('FOO')}, BAZ={os.environ.get('BAZ')}")
    clean_env("FOO", "BAZ")


# ── TEST 2.2: existing env var NOT overwritten ──
def test_python_existing_env_not_overwritten():
    name = "TEST-2.2: existing env var NOT overwritten"
    os.environ["FOO"] = "original"
    cfg = write_config({"env": {"vars": {"FOO": "from_config"}}})
    result = load_openclaw_env(config_path=cfg)
    if os.environ["FOO"] == "original" and result.get("FOO") == "original":
        pass_test(name)
    else:
        fail_test(name, f"FOO={os.environ.get('FOO')}, result={result}")
    clean_env("FOO")


# ── TEST 3.2: null value skipped ──
def test_python_null_value_skipped():
    name = "TEST-3.2: null value skipped"
    clean_env("FOO", "BAR")
    cfg = write_config({"env": {"vars": {"FOO": None, "BAR": "hello"}}})
    result = load_openclaw_env(config_path=cfg)
    if "FOO" not in result and "FOO" not in os.environ and result.get("BAR") == "hello":
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("BAR")


# ── TEST 4.2: empty string value skipped ──
def test_python_empty_string_skipped():
    name = "TEST-4.2: empty string value skipped"
    clean_env("FOO", "BAR")
    cfg = write_config({"env": {"vars": {"FOO": "", "BAR": "hello"}}})
    result = load_openclaw_env(config_path=cfg)
    if "FOO" not in result and "FOO" not in os.environ and result.get("BAR") == "hello":
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("BAR")


# ── TEST 5.2: malformed JSON warns and returns empty ──
def test_python_malformed_json_warns():
    name = "TEST-5.2: malformed JSON warns and returns empty"
    cfg = write_config("{not valid json")
    captured = io.StringIO()
    old_stderr = sys.stderr
    sys.stderr = captured
    result = load_openclaw_env(config_path=cfg)
    sys.stderr = old_stderr
    if result == {} and "WARNING" in captured.getvalue():
        pass_test(name)
    else:
        fail_test(name, f"result={result}, stderr='{captured.getvalue()}'")


# ── TEST 5.3: non-dict top-level JSON ──
def test_python_non_dict_json_warns():
    name = "TEST-5.3: non-dict top-level JSON"
    cfg = write_config("[1, 2, 3]")
    captured = io.StringIO()
    old_stderr = sys.stderr
    sys.stderr = captured
    result = load_openclaw_env(config_path=cfg)
    sys.stderr = old_stderr
    if result == {} and "WARNING" in captured.getvalue():
        pass_test(name)
    else:
        fail_test(name, f"result={result}, stderr='{captured.getvalue()}'")


# ── TEST 6.2: missing config returns empty dict ──
def test_python_missing_config_no_error():
    name = "TEST-6.2: missing config returns empty dict"
    result = load_openclaw_env(config_path="/tmp/nonexistent_98_test.json")
    if result == {}:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")


# ── TEST 7.2: unreadable config warns ──
def test_python_unreadable_config_warns():
    name = "TEST-7.2: unreadable config warns"
    cfg = write_config({"env": {"vars": {"FOO": "bar"}}})
    os.chmod(cfg, 0o000)
    captured = io.StringIO()
    old_stderr = sys.stderr
    sys.stderr = captured
    result = load_openclaw_env(config_path=cfg)
    sys.stderr = old_stderr
    os.chmod(cfg, 0o644)  # cleanup
    if result == {} and "WARNING" in captured.getvalue():
        pass_test(name)
    else:
        fail_test(name, f"result={result}, stderr='{captured.getvalue()}'")


# ── TEST 8.3: no env section ──
def test_python_no_env_section():
    name = "TEST-8.3: no env section"
    cfg = write_config({"gateway": {"port": 3000}})
    result = load_openclaw_env(config_path=cfg)
    if result == {}:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")


# ── TEST 8.4: env.vars is not a dict ──
def test_python_env_vars_not_dict():
    name = "TEST-8.4: env.vars is not a dict"
    cfg = write_config({"env": {"vars": "not_a_dict"}})
    result = load_openclaw_env(config_path=cfg)
    if result == {}:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")


# ── TEST 10.5: idempotent double call ──
def test_python_idempotent_double_call():
    name = "TEST-10.5: idempotent double call"
    clean_env("FOO", "BAZ")
    cfg = write_config({"env": {"vars": {"FOO": "bar", "BAZ": "qux"}}})
    r1 = load_openclaw_env(config_path=cfg)
    r2 = load_openclaw_env(config_path=cfg)
    if r1 == r2 == {"FOO": "bar", "BAZ": "qux"} and os.environ.get("FOO") == "bar":
        pass_test(name)
    else:
        fail_test(name, f"r1={r1}, r2={r2}")
    clean_env("FOO", "BAZ")


# ── TEST 10.6: numeric value as string ──
def test_python_numeric_value_as_string():
    name = "TEST-10.6: numeric value as string"
    clean_env("PORT", "DEBUG")
    cfg = write_config({"env": {"vars": {"PORT": 8080, "DEBUG": True}}})
    result = load_openclaw_env(config_path=cfg)
    if os.environ.get("PORT") == "8080" and os.environ.get("DEBUG") == "True":
        pass_test(name)
    else:
        fail_test(name, f"PORT={os.environ.get('PORT')}, DEBUG={os.environ.get('DEBUG')}")
    clean_env("PORT", "DEBUG")


# ── TEST 10.7: custom config_path ──
def test_python_custom_config_path():
    name = "TEST-10.7: custom config_path"
    clean_env("FOO")
    cfg = write_config({"env": {"vars": {"FOO": "custom"}}})
    result = load_openclaw_env(config_path=cfg)
    if result.get("FOO") == "custom":
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("FOO")


if __name__ == "__main__":
    test_python_loads_vars_from_valid_config()
    test_python_existing_env_not_overwritten()
    test_python_null_value_skipped()
    test_python_empty_string_skipped()
    test_python_malformed_json_warns()
    test_python_non_dict_json_warns()
    test_python_missing_config_no_error()
    test_python_unreadable_config_warns()
    test_python_no_env_section()
    test_python_env_vars_not_dict()
    test_python_idempotent_double_call()
    test_python_numeric_value_as_string()
    test_python_custom_config_path()

    print()
    print("================================")
    print(f"Results: {PASS} passed, {FAIL} failed (total {PASS + FAIL})")
    print("================================")
    sys.exit(1 if FAIL > 0 else 0)
