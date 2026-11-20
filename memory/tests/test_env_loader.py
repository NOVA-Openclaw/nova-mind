#!/usr/bin/env python3
"""
test_env_loader.py — Test runner for lib/env_loader.py
Issue: nova-workspace#309 — env_loader now resolves secrets via nova-op.
"""

import io
import json
import os
import stat
import sys
import tempfile

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


def write_map(data, tmpdir=None):
    """Write an item map file and return its path."""
    if tmpdir is None:
        tmpdir = tempfile.mkdtemp()
    path = os.path.join(tmpdir, "nova-op-item-map.json")
    if isinstance(data, str):
        with open(path, "w") as f:
            f.write(data)
    else:
        with open(path, "w") as f:
            json.dump(data, f)
    return path


def make_nova_op(tmpdir, mapping):
    """Create a stub nova-op binary that returns fake values."""
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/env python3\n")
        f.write("import sys\n")
        f.write("item = ''\n")
        f.write("skip_next = False\n")
        f.write("for arg in sys.argv[1:]:\n")
        f.write("    if skip_next:\n")
        f.write("        skip_next = False\n")
        f.write("        continue\n")
        f.write("    if arg in ('item', 'get'):\n")
        f.write("        continue\n")
        f.write("    if arg.startswith('--'):\n")
        f.write("        if arg in ('--vault', '--field', '--reveal'):\n")
        f.write("            skip_next = True\n")
        f.write("        continue\n")
        f.write("    if not item:\n")
        f.write("        item = arg\n")
        f.write("mapping = " + repr(mapping) + "\n")
        f.write("if item in mapping:\n")
        f.write("    print(mapping[item])\n")
        f.write("else:\n")
        f.write("    print(f'nova-op: item not found: {item}', file=sys.stderr)\n")
        f.write("    sys.exit(1)\n")
    os.chmod(script, stat.S_IRWXU)
    return bin_dir


def clean_env(*keys):
    for k in keys:
        os.environ.pop(k, None)


def run_with_path(bin_dir, func):
    """Run func with bin_dir prepended to PATH, then restore PATH."""
    old_path = os.environ.get("PATH", "")
    os.environ["PATH"] = f"{bin_dir}:{old_path}"
    try:
        return func()
    finally:
        os.environ["PATH"] = old_path


# ── TEST 1.2: loads vars from valid map via nova-op ──
def test_python_loads_vars_from_valid_map():
    name = "TEST-1.2: loads vars from valid map via nova-op"
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "V", "item": "eefc3r3hh4lzb7dasihufmqmoy", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {
        "w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key",
        "eefc3r3hh4lzb7dasihufmqmoy": "fake-anthropic-key",
    })

    def _run():
        result = load_openclaw_env(config_path=cfg)
        ok = (
            result == {
                "OPENROUTER_API_KEY": "fake-openrouter-key",
                "ANTHROPIC_API_KEY": "fake-anthropic-key",
            }
            and os.environ.get("OPENROUTER_API_KEY") == "fake-openrouter-key"
            and os.environ.get("ANTHROPIC_API_KEY") == "fake-anthropic-key"
        )
        return ok, result

    ok, result = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")


# ── TEST 2.2: existing env var NOT overwritten ──
def test_python_existing_env_not_overwritten():
    name = "TEST-2.2: existing env var NOT overwritten"
    os.environ["OPENROUTER_API_KEY"] = "original"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {"w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key"})

    def _run():
        result = load_openclaw_env(config_path=cfg)
        return os.environ["OPENROUTER_API_KEY"] == "original" and result.get("OPENROUTER_API_KEY") == "original"

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"OPENROUTER_API_KEY={os.environ.get('OPENROUTER_API_KEY')}")
    clean_env("OPENROUTER_API_KEY")


# ── TEST 2.3: empty env var IS overwritten ──
def test_python_empty_env_overwritten():
    name = "TEST-2.3: empty env var IS overwritten"
    os.environ["OPENROUTER_API_KEY"] = ""
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {"w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key"})

    def _run():
        load_openclaw_env(config_path=cfg)
        return os.environ["OPENROUTER_API_KEY"] == "fake-openrouter-key"

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"OPENROUTER_API_KEY={os.environ.get('OPENROUTER_API_KEY')}")
    clean_env("OPENROUTER_API_KEY")


# ── TEST 3.2: metadata keys skipped ──
def test_python_metadata_key_skipped():
    name = "TEST-3.2: metadata keys skipped"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "_description": "ignored",
        "OPENROUTER_API_KEY": {"vault": "V", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {"w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key"})

    def _run():
        result = load_openclaw_env(config_path=cfg)
        return result == {"OPENROUTER_API_KEY": "fake-openrouter-key"}

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("OPENROUTER_API_KEY")


# ── TEST 5.2: malformed JSON raises RuntimeError ──
def test_python_malformed_json_raises():
    name = "TEST-5.2: malformed JSON raises RuntimeError"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map("{not valid json", tmpdir)
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path=cfg)
            return False
        except RuntimeError as exc:
            return "item map is not valid JSON" in str(exc)

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")


# ── TEST 5.3: non-dict top-level JSON raises RuntimeError ──
def test_python_non_dict_json_raises():
    name = "TEST-5.3: non-dict top-level JSON raises RuntimeError"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map([1, 2, 3], tmpdir)
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path=cfg)
            return False
        except RuntimeError as exc:
            return "item map must be a JSON object" in str(exc)

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")


# ── TEST 6.2: missing config raises RuntimeError ──
def test_python_missing_config_raises():
    name = "TEST-6.2: missing config raises RuntimeError"
    tmpdir = tempfile.mkdtemp()
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path="/tmp/nonexistent_309_test.json")
            return False
        except RuntimeError as exc:
            return "item map not found" in str(exc)

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")


# ── TEST 7.2: unreadable config raises RuntimeError ──
def test_python_unreadable_config_raises():
    name = "TEST-7.2: unreadable config raises RuntimeError"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "i", "field": "f"},
    }, tmpdir)
    os.chmod(cfg, 0o000)
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path=cfg)
            return False
        except RuntimeError:
            return True
        finally:
            os.chmod(cfg, 0o644)

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")


# ── TEST 8.3: empty map raises RuntimeError ──
def test_python_empty_map_raises():
    name = "TEST-8.3: empty map raises RuntimeError"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({}, tmpdir)
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path=cfg)
            return False
        except RuntimeError as exc:
            return "no secret entries found" in str(exc)

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")


# ── TEST 10.5: idempotent double call ──
def test_python_idempotent_double_call():
    name = "TEST-10.5: idempotent double call"
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "V", "item": "eefc3r3hh4lzb7dasihufmqmoy", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {
        "w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key",
        "eefc3r3hh4lzb7dasihufmqmoy": "fake-anthropic-key",
    })

    def _run():
        r1 = load_openclaw_env(config_path=cfg)
        r2 = load_openclaw_env(config_path=cfg)
        return (
            r1 == r2 == {
                "OPENROUTER_API_KEY": "fake-openrouter-key",
                "ANTHROPIC_API_KEY": "fake-anthropic-key",
            }
            and os.environ.get("OPENROUTER_API_KEY") == "fake-openrouter-key"
        )

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"env={dict(os.environ)}")
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")


# ── TEST 10.6: wrong item ID fails loudly and names item ID ──
def test_python_wrong_item_id_fails():
    name = "TEST-10.6: wrong item ID fails loudly and names item ID"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "wrong-item-id", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            load_openclaw_env(config_path=cfg)
            return False
        except RuntimeError as exc:
            return "wrong-item-id" in str(exc)
        finally:
            sys.stderr = old_stderr

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")
    clean_env("OPENROUTER_API_KEY")


# ── TEST 10.7: custom config_path ──
def test_python_custom_config_path():
    name = "TEST-10.7: custom config_path"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "V", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {"w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key"})

    def _run():
        result = load_openclaw_env(config_path=cfg)
        return result.get("OPENROUTER_API_KEY") == "fake-openrouter-key"

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("OPENROUTER_API_KEY")


if __name__ == "__main__":
    test_python_loads_vars_from_valid_map()
    test_python_existing_env_not_overwritten()
    test_python_empty_env_overwritten()
    test_python_metadata_key_skipped()
    test_python_malformed_json_raises()
    test_python_non_dict_json_raises()
    test_python_missing_config_raises()
    test_python_unreadable_config_raises()
    test_python_empty_map_raises()
    test_python_idempotent_double_call()
    test_python_wrong_item_id_fails()
    test_python_custom_config_path()

    print()
    print("================================")
    print(f"Results: {PASS} passed, {FAIL} failed (total {PASS + FAIL})")
    print("================================")
    sys.exit(1 if FAIL > 0 else 0)
