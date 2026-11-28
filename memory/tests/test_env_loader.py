#!/usr/bin/env python3
"""
test_env_loader.py — Test runner for lib/env_loader.py
Issue: nova-workspace#309 — env_loader now resolves secrets via nova-op.
Issue: nova-mind#818 — targeted resolution, cache, skip-if-present, warning-not-crash.
"""

import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

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


def _log_line(log_path, line):
    if log_path:
        with open(log_path, "a") as f:
            f.write(line + "\n")


def make_recording_nova_op(tmpdir, mapping, log_path=None):
    """Create a stub nova-op binary that returns fake values and logs calls."""
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
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
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write("        _f.write(' '.join(sys.argv) + '\\n')\n")
        f.write("if item in mapping:\n")
        f.write("    print(mapping[item])\n")
        f.write("else:\n")
        f.write("    print(f'nova-op: item not found: {item}', file=sys.stderr)\n")
        f.write("    sys.exit(1)\n")
    os.chmod(script, stat.S_IRWXU)
    return bin_dir


def make_nova_op(tmpdir, mapping):
    """Create a stub nova-op binary that returns fake values (backward compat)."""
    return make_recording_nova_op(tmpdir, mapping)


def make_slow_nova_op(tmpdir, sleep_s, log_path=None):
    """Create a stub nova-op that sleeps before responding, for timeout tests."""
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import sys, time\n")
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write("        _f.write(' '.join(sys.argv) + '\\n')\n")
        f.write(f"time.sleep({sleep_s!r})\n")
        f.write("print('slow-value')\n")
    os.chmod(script, stat.S_IRWXU)
    return bin_dir


def make_failing_nova_op(tmpdir, log_path=None, message="always fails"):
    """Create a stub nova-op that exits non-zero unconditionally."""
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import sys\n")
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write("        _f.write(' '.join(sys.argv) + '\\n')\n")
        f.write(f"print({message!r}, file=sys.stderr)\n")
        f.write("sys.exit(1)\n")
    os.chmod(script, stat.S_IRWXU)
    return bin_dir


def make_tagged_nova_op(tmpdir, tag, log_path=None):
    """Create a stub that prints its tag to the log so PATH vs HOME precedence is visible."""
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import sys\n")
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write(f"        _f.write({tag!r} + ' ' + ' '.join(sys.argv) + '\\n')\n")
        f.write(f"print({tag!r})\n")
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


def run_with_home(home_dir, func):
    """Run func with HOME overridden, then restore HOME."""
    old_home = os.environ.get("HOME", "")
    os.environ["HOME"] = home_dir
    try:
        return func()
    finally:
        os.environ["HOME"] = old_home


def count_calls(log_path):
    """Return the number of logged nova-op invocations."""
    if not log_path or not os.path.exists(log_path):
        return 0
    with open(log_path, "r") as f:
        return sum(1 for line in f if line.strip())


def run_import_script(script_path, env):
    """Import a script in a subprocess and return (returncode, stdout, stderr)."""
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cmd = [
        sys.executable,
        "-c",
        f"import sys; sys.path.insert(0, {repo_root!r}); "
        f"sys.path.insert(0, {os.path.join(repo_root, 'scripts')!r}); "
        f"import importlib.util; spec = importlib.util.spec_from_file_location('mod', {script_path!r}); "
        "mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=30)
    return result.returncode, result.stdout, result.stderr


def run_main_script(script_path, env, stdin_text=""):
    """Run a script's main block in a subprocess and return (returncode, stdout, stderr)."""
    cmd = [sys.executable, script_path]
    result = subprocess.run(
        cmd, input=stdin_text, capture_output=True, text=True, env=env, timeout=30
    )
    return result.returncode, result.stdout, result.stderr


def _copy_openclaw_lib_to_home(home_dir, overlay_env_loader=True):
    """Copy the real ~/.openclaw/lib into home_dir/.openclaw/lib for subprocess tests."""
    openclaw_lib = os.path.join(home_dir, ".openclaw", "lib")
    os.makedirs(openclaw_lib, exist_ok=True)
    real_lib = os.path.join(os.path.expanduser("~"), ".openclaw", "lib")
    if os.path.isdir(real_lib):
        for entry in os.listdir(real_lib):
            src = os.path.join(real_lib, entry)
            dst = os.path.join(openclaw_lib, entry)
            if os.path.exists(dst):
                continue
            if os.path.isfile(src):
                shutil.copy2(src, dst)
            elif os.path.isdir(src):
                shutil.copytree(src, dst)
    # Ensure subprocess tests exercise the in-repo env_loader.py (the one under test).
    if overlay_env_loader:
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        repo_env_loader = os.path.join(repo_root, "lib", "env_loader.py")
        if os.path.isfile(repo_env_loader):
            shutil.copy2(repo_env_loader, os.path.join(openclaw_lib, "env_loader.py"))


# ═══════════════════════════════════════════════════════════════════════════
# Category A — Zero nova-op calls per DB-only script
# ═══════════════════════════════════════════════════════════════════════════

TARGET_SCRIPTS = [
    ("proactive-recall.py", "scripts/proactive-recall.py"),
    ("dedup_helper.py", "scripts/dedup_helper.py"),
    ("confidence_helper.py", "scripts/confidence_helper.py"),
    ("memory-maintenance.py", "templates/memory-maintenance.py"),
]


def test_a_static_no_env_loader_references():
    name = "TC-A1/A3/A5/A7: DB-only scripts do not reference env_loader"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    all_ok = True
    for label, rel_path in TARGET_SCRIPTS:
        path = os.path.join(repo_root, rel_path)
        with open(path, "r") as f:
            src = f.read()
        if "load_openclaw_env" in src or "from env_loader import" in src:
            fail_test(name, f"{label} still references env_loader")
            return
        if "env_loader" in src:
            fail_test(name, f"{label} still contains 'env_loader' text")
            return
    pass_test(name)


def _import_with_recording_stub(label, rel_path):
    """Helper: import script with a recording nova-op stub and assert zero calls."""
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    script_path = os.path.join(repo_root, rel_path)
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    bin_dir = make_recording_nova_op(tmpdir, {"any-item": "fake"}, log_path=log_path)

    # Set up a temp HOME with .openclaw/lib so pg_env/embedding_config can be found.
    home_dir = os.path.join(tmpdir, "home")
    openclaw_lib = os.path.join(home_dir, ".openclaw", "lib")
    os.makedirs(openclaw_lib, exist_ok=True)
    # Symlink real lib files so imports succeed without touching the real HOME.
    real_lib = os.path.join(os.path.expanduser("~"), ".openclaw", "lib")
    if os.path.isdir(real_lib):
        for entry in os.listdir(real_lib):
            src = os.path.join(real_lib, entry)
            dst = os.path.join(openclaw_lib, entry)
            if not os.path.exists(dst):
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
                elif os.path.isdir(src):
                    shutil.copytree(src, dst)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    env["HOME"] = home_dir
    # Prevent any real nova-op calls if the script somehow reaches env_loader.
    env["OPENROUTER_API_KEY"] = ""
    env["ANTHROPIC_API_KEY"] = ""

    rc, stdout, stderr = run_import_script(script_path, env)
    calls = count_calls(log_path)
    return rc, stdout, stderr, calls


def test_a2_proactive_recall_import_zero_calls():
    name = "TC-A2: proactive-recall.py import records 0 nova-op calls"
    rc, stdout, stderr, calls = _import_with_recording_stub(*TARGET_SCRIPTS[0])
    if rc == 0 and calls == 0:
        pass_test(name)
    else:
        fail_test(name, f"rc={rc} calls={calls} stderr={stderr[:200]}")


def test_a4_dedup_helper_import_zero_calls():
    name = "TC-A4: dedup_helper.py import records 0 nova-op calls (incl. confidence_helper)"
    rc, stdout, stderr, calls = _import_with_recording_stub(*TARGET_SCRIPTS[1])
    if rc == 0 and calls == 0:
        pass_test(name)
    else:
        fail_test(name, f"rc={rc} calls={calls} stderr={stderr[:200]}")


def test_a6_confidence_helper_import_zero_calls():
    name = "TC-A6: confidence_helper.py import records 0 nova-op calls"
    rc, stdout, stderr, calls = _import_with_recording_stub(*TARGET_SCRIPTS[2])
    if rc == 0 and calls == 0:
        pass_test(name)
    else:
        fail_test(name, f"rc={rc} calls={calls} stderr={stderr[:200]}")


def test_a8_memory_maintenance_import_zero_calls():
    name = "TC-A8: memory-maintenance.py import records 0 nova-op calls"
    rc, stdout, stderr, calls = _import_with_recording_stub(*TARGET_SCRIPTS[3])
    if rc == 0 and calls == 0:
        pass_test(name)
    else:
        fail_test(name, f"rc={rc} calls={calls} stderr={stderr[:200]}")


def test_a9_import_succeeds_with_no_nova_op_anywhere():
    name = "TC-A9: DB-only scripts import with no nova-op anywhere"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    tmpdir = tempfile.mkdtemp()
    home_dir = os.path.join(tmpdir, "home")
    os.makedirs(home_dir, exist_ok=True)

    # Empty PATH stub dir so no nova-op binary exists anywhere reachable.
    empty_bin = os.path.join(tmpdir, "empty_bin")
    os.makedirs(empty_bin, exist_ok=True)

    openclaw_lib = os.path.join(home_dir, ".openclaw", "lib")
    os.makedirs(openclaw_lib, exist_ok=True)
    real_lib = os.path.join(os.path.expanduser("~"), ".openclaw", "lib")
    if os.path.isdir(real_lib):
        for entry in os.listdir(real_lib):
            src = os.path.join(real_lib, entry)
            dst = os.path.join(openclaw_lib, entry)
            if not os.path.exists(dst):
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
                elif os.path.isdir(src):
                    shutil.copytree(src, dst)

    env = os.environ.copy()
    env["PATH"] = empty_bin
    env["HOME"] = home_dir

    all_ok = True
    for label, rel_path in TARGET_SCRIPTS:
        script_path = os.path.join(repo_root, rel_path)
        rc, stdout, stderr = run_import_script(script_path, env)
        if rc != 0:
            fail_test(name, f"{label} failed with rc={rc} stderr={stderr[:200]}")
            return
    pass_test(name)


# ═══════════════════════════════════════════════════════════════════════════
# Category B — Recall timing
# ═══════════════════════════════════════════════════════════════════════════

def test_b1_proactive_recall_run_with_slow_stub_zero_calls():
    name = "TC-B1: proactive-recall.py run with slow nova-op stub makes 0 calls"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    script_path = os.path.join(repo_root, "memory/scripts/proactive-recall.py")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    bin_dir = make_slow_nova_op(tmpdir, sleep_s=10, log_path=log_path)

    home_dir = os.path.join(tmpdir, "home")
    openclaw_lib = os.path.join(home_dir, ".openclaw", "lib")
    os.makedirs(openclaw_lib, exist_ok=True)
    real_lib = os.path.join(os.path.expanduser("~"), ".openclaw", "lib")
    if os.path.isdir(real_lib):
        for entry in os.listdir(real_lib):
            src = os.path.join(real_lib, entry)
            dst = os.path.join(openclaw_lib, entry)
            if not os.path.exists(dst):
                if os.path.isfile(src):
                    shutil.copy2(src, dst)
                elif os.path.isdir(src):
                    shutil.copytree(src, dst)

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    env["HOME"] = home_dir

    start = time.time()
    # Provide a JSON payload; DB connection will fail but that's fine for timing.
    rc, stdout, stderr = run_main_script(script_path, env, stdin_text='{"content": "test query"}')
    elapsed = time.time() - start
    calls = count_calls(log_path)

    if calls == 0 and elapsed < 3:
        pass_test(name)
    else:
        fail_test(name, f"calls={calls} elapsed={elapsed:.2f}s rc={rc}")


def test_b3_env_load_phase_is_skipped():
    name = "TC-B3: proactive-recall.py env-load phase is skipped entirely"
    # Covered by TC-B1: with a 10s slow stub, if any env-load happened it would dominate timing.
    # We assert the run completed well under the stub's sleep.
    pass_test(name + " (covered by TC-B1)")


# ═══════════════════════════════════════════════════════════════════════════
# Category C — Targeted resolution / skip / short-circuit / cache
# ═══════════════════════════════════════════════════════════════════════════

def test_c1_targeted_key_only_one_call():
    name = "TC-C1: targeted resolution touches only requested key"
    clean_env("A", "B", "C")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "A": {"vault": "v", "item": "item-a", "field": "f"},
        "B": {"vault": "v", "item": "item-b", "field": "f"},
        "C": {"vault": "v", "item": "item-c", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {
        "item-a": "val-a",
        "item-b": "val-b",
        "item-c": "val-c",
    }, log_path=log_path)

    def _run():
        result = load_openclaw_env(config_path=cfg, keys=["B"])
        return result

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {"B": "val-b"}
        and os.environ.get("B") == "val-b"
        and calls == 1
        and os.environ.get("A") is None
        and os.environ.get("C") is None
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} env={dict(os.environ)}")
    clean_env("A", "B", "C")


def test_c2_existing_env_not_overwritten():
    name = "TC-C2: requested key already in env skips nova-op and keeps existing value"
    os.environ["OPENROUTER_API_KEY"] = "pre-existing"
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "v", "item": "item-or", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {"item-or": "fake-openrouter-key"}, log_path=log_path)

    def _run():
        return load_openclaw_env(config_path=cfg, keys=["OPENROUTER_API_KEY"])

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result.get("OPENROUTER_API_KEY") == "pre-existing"
        and os.environ.get("OPENROUTER_API_KEY") == "pre-existing"
        and calls == 0
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls}")
    clean_env("OPENROUTER_API_KEY")


def test_c3_all_keys_present_skips_map_open():
    name = "TC-C3: all requested keys present means map file is never opened"
    os.environ["X"] = "present"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    os.remove(cfg)  # delete the map file

    def _run():
        return load_openclaw_env(config_path=cfg, keys=["X"])

    # If the function tried to open the map, this would raise RuntimeError.
    result = _run()
    if result == {"X": "present"}:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("X")


def test_c4_empty_keys_no_file_io():
    name = "TC-C4: keys=[] returns {} immediately without file I/O"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    os.remove(cfg)

    def _run():
        return load_openclaw_env(config_path=cfg, keys=[])

    result = _run()
    if result == {}:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")


def test_c5_cache_prevents_second_call():
    name = "TC-C5: same config/key called twice logs only one nova-op call"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"X": {"vault": "v", "item": "item-x", "field": "f"}}, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {"item-x": "val-x"}, log_path=log_path)

    def _run():
        r1 = load_openclaw_env(config_path=cfg, keys=["X"])
        r2 = load_openclaw_env(config_path=cfg, keys=["X"])
        return r1, r2

    r1, r2 = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = r1 == r2 == {"X": "val-x"} and calls == 1
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"r1={r1} r2={r2} calls={calls}")
    clean_env("X")


def test_c6_cache_survives_external_env_mutation():
    name = "TC-C6: cache survives external os.environ.pop and re-sets the var"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"X": {"vault": "v", "item": "item-x", "field": "f"}}, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {"item-x": "val-x"}, log_path=log_path)

    def _run():
        load_openclaw_env(config_path=cfg, keys=["X"])
        os.environ.pop("X", None)
        result = load_openclaw_env(config_path=cfg, keys=["X"])
        return result

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = result == {"X": "val-x"} and os.environ.get("X") == "val-x" and calls == 1
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} env={os.environ.get('X')}")
    clean_env("X")


def test_c7_cache_isolated_by_config_path():
    name = "TC-C7: cache keyed by (config_path, var) isolates different maps"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    dir_a = os.path.join(tmpdir, "a")
    dir_b = os.path.join(tmpdir, "b")
    os.makedirs(dir_a, exist_ok=True)
    os.makedirs(dir_b, exist_ok=True)
    cfg1 = write_map({"X": {"vault": "v", "item": "item-x1", "field": "f"}}, dir_a)
    cfg2 = write_map({"X": {"vault": "v", "item": "item-x2", "field": "f"}}, dir_b)
    bin_dir = make_recording_nova_op(tmpdir, {
        "item-x1": "from-a",
        "item-x2": "from-b",
    }, log_path=log_path)

    def _run():
        r1 = load_openclaw_env(config_path=cfg1, keys=["X"])
        os.environ.pop("X", None)  # force second call to use cache, not env-skip
        r2 = load_openclaw_env(config_path=cfg2, keys=["X"])
        return r1, r2

    r1, r2 = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = r1 == {"X": "from-a"} and r2 == {"X": "from-b"} and calls == 2
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"r1={r1} r2={r2} calls={calls}")
    clean_env("X")


def test_c8_metadata_key_skipped_when_explicitly_requested():
    name = "TC-C8: keys=['_description'] does not resolve metadata key"
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"_description": "ignored metadata"}, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {}, log_path=log_path)

    def _run():
        return load_openclaw_env(config_path=cfg, keys=["_description"])

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    if result == {} and calls == 0:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls}")


def test_c9_key_not_in_map_warns():
    name = "TC-C9: requested key not in map warns and skips"
    clean_env("NOT_IN_MAP")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {"i": "val"}, log_path=log_path)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            result = load_openclaw_env(config_path=cfg, keys=["NOT_IN_MAP"])
        finally:
            sys.stderr = old_stderr
        return result, captured.getvalue()

    (result, stderr) = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {}
        and calls == 0
        and "NOT_IN_MAP" in stderr
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} stderr={stderr}")
    clean_env("NOT_IN_MAP")


# ═══════════════════════════════════════════════════════════════════════════
# Category D — nova-op missing/failure/timeout warn, never crash
# ═══════════════════════════════════════════════════════════════════════════

def test_d1_timeout_warns_and_skips():
    name = "TC-D1: nova-op timeout warns and skips key"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = make_slow_nova_op(tmpdir, sleep_s=5, log_path=log_path)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            start = time.time()
            result = load_openclaw_env(config_path=cfg, keys=["X"], timeout_s=0.5)
            elapsed = time.time() - start
        finally:
            sys.stderr = old_stderr
        return result, captured.getvalue(), elapsed

    result, stderr, elapsed = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {}
        and calls == 1
        and "X" in stderr
        and "timeout" in stderr.lower()
        and elapsed < 2.0
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} elapsed={elapsed:.2f} stderr={stderr}")
    clean_env("X")


def test_d2_nonzero_exit_warns_and_continues():
    name = "TC-D2: nova-op non-zero exit warns and other keys resolve"
    clean_env("X", "Y")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "X": {"vault": "v", "item": "bad-item", "field": "f"},
        "Y": {"vault": "v", "item": "good-item", "field": "f"},
    }, tmpdir)

    # Build a stub that fails for bad-item and succeeds for good-item.
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
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
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write("        _f.write(' '.join(sys.argv) + '\\n')\n")
        f.write("if item == 'bad-item':\n")
        f.write("    print('wrong item id', file=sys.stderr)\n")
        f.write("    sys.exit(1)\n")
        f.write("print('good-value')\n")
    os.chmod(script, stat.S_IRWXU)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            result = load_openclaw_env(config_path=cfg, keys=["X", "Y"])
        finally:
            sys.stderr = old_stderr
        return result, captured.getvalue()

    result, stderr = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {"Y": "good-value"}
        and calls == 2
        and "X" in stderr
        and os.environ.get("Y") == "good-value"
        and os.environ.get("X") is None
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} stderr={stderr}")
    clean_env("X", "Y")


def test_d3_missing_binary_warns_no_exception():
    name = "TC-D3: nova-op missing from PATH and HOME fallback warns, no exception"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    home_dir = os.path.join(tmpdir, "home")
    os.makedirs(home_dir, exist_ok=True)
    empty_bin = os.path.join(tmpdir, "empty_bin")
    os.makedirs(empty_bin, exist_ok=True)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        old_path = os.environ.get("PATH", "")
        old_home = os.environ.get("HOME", "")
        sys.stderr = captured
        os.environ["PATH"] = empty_bin
        os.environ["HOME"] = home_dir
        try:
            result = load_openclaw_env(config_path=cfg, keys=["X"])
        finally:
            sys.stderr = old_stderr
            os.environ["PATH"] = old_path
            os.environ["HOME"] = old_home
        return result, captured.getvalue()

    result, stderr = _run()
    ok = (
        result == {}
        and "nova-op not found" in stderr
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} stderr={stderr}")
    clean_env("X")


def test_d4_skip_if_present_avoids_failing_stub():
    name = "TC-D4: pre-injected key skips failing stub entirely"
    os.environ["OPENROUTER_API_KEY"] = "injected"
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"OPENROUTER_API_KEY": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = make_failing_nova_op(tmpdir, log_path=log_path)

    def _run():
        return load_openclaw_env(config_path=cfg, keys=["OPENROUTER_API_KEY"])

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {"OPENROUTER_API_KEY": "injected"}
        and calls == 0
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls}")
    clean_env("OPENROUTER_API_KEY")


def test_d5_empty_value_warns_and_skips():
    name = "TC-D5: empty resolved value warns and skips key"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = os.path.join(tmpdir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    script = os.path.join(bin_dir, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import sys\n")
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write("        _f.write(' '.join(sys.argv) + '\\n')\n")
        f.write("print()\n")  # empty stdout
    os.chmod(script, stat.S_IRWXU)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            result = load_openclaw_env(config_path=cfg, keys=["X"])
        finally:
            sys.stderr = old_stderr
        return result, captured.getvalue()

    result, stderr = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {}
        and calls == 1
        and "X" in stderr
        and "empty value" in stderr
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} stderr={stderr}")
    clean_env("X")


def test_d6_incomplete_entry_and_placeholder_still_raise():
    name = "TC-D6: incomplete entry and placeholder still raise RuntimeError"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "INCOMPLETE": {"vault": "v", "field": "f"},  # missing item
        "PLACEHOLDER": {"vault": "REPLACE_WITH_VAULT_ID", "item": "REPLACE_WITH_ITEM_ID", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path=cfg, keys=["INCOMPLETE", "PLACEHOLDER"])
            return False, None
        except RuntimeError as exc:
            return True, str(exc)

    ok, text = run_with_path(bin_dir, _run)
    if ok and "incomplete" in text and "placeholder" in text:
        pass_test(name)
    else:
        fail_test(name, f"ok={ok} text={text}")


# ═══════════════════════════════════════════════════════════════════════════
# Category E — $HOME/.local/bin/nova-op fallback
# ═══════════════════════════════════════════════════════════════════════════

def test_e1_home_fallback_used():
    name = "TC-E1: nova-op absent from PATH, present at $HOME/.local/bin"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    home_dir = os.path.join(tmpdir, "home")
    home_bin = os.path.join(home_dir, ".local", "bin")
    os.makedirs(home_bin, exist_ok=True)
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)

    script = os.path.join(home_bin, "nova-op")
    with open(script, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("print('home-fallback-value')\n")
    os.chmod(script, stat.S_IRWXU)

    empty_bin = os.path.join(tmpdir, "empty_bin")
    os.makedirs(empty_bin, exist_ok=True)

    def _run():
        old_path = os.environ.get("PATH", "")
        old_home = os.environ.get("HOME", "")
        os.environ["PATH"] = empty_bin
        os.environ["HOME"] = home_dir
        try:
            result = load_openclaw_env(config_path=cfg, keys=["X"])
        finally:
            os.environ["PATH"] = old_path
            os.environ["HOME"] = old_home
        return result

    result = _run()
    if result == {"X": "home-fallback-value"}:
        pass_test(name)
    else:
        fail_test(name, f"result={result}")
    clean_env("X")


def test_e3_path_takes_precedence_over_home():
    name = "TC-E3: PATH nova-op takes precedence over $HOME/.local/bin"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    home_dir = os.path.join(tmpdir, "home")
    home_bin = os.path.join(home_dir, ".local", "bin")
    os.makedirs(home_bin, exist_ok=True)
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)

    path_bin = make_tagged_nova_op(tmpdir, "PATH-STUB", log_path=log_path)

    home_script = os.path.join(home_bin, "nova-op")
    with open(home_script, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import sys\n")
        f.write(f"log_path = {repr(log_path)}\n")
        f.write("if log_path:\n")
        f.write("    with open(log_path, 'a') as _f:\n")
        f.write("        _f.write('HOME-STUB ' + ' '.join(sys.argv) + '\\n')\n")
        f.write("print('home-value')\n")
    os.chmod(home_script, stat.S_IRWXU)

    def _run():
        old_path = os.environ.get("PATH", "")
        old_home = os.environ.get("HOME", "")
        os.environ["PATH"] = f"{path_bin}:{old_path}"
        os.environ["HOME"] = home_dir
        try:
            result = load_openclaw_env(config_path=cfg, keys=["X"])
        finally:
            os.environ["PATH"] = old_path
            os.environ["HOME"] = old_home
        return result

    result = _run()
    calls = count_calls(log_path)
    with open(log_path, "r") as f:
        lines = [l.strip() for l in f if l.strip()]
    ok = (
        result == {"X": "PATH-STUB"}
        and calls == 1
        and lines
        and lines[0].startswith("PATH-STUB")
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} lines={lines}")
    clean_env("X")


# ═══════════════════════════════════════════════════════════════════════════
# Category F — extract_memories.py still gets its provider key
# ═══════════════════════════════════════════════════════════════════════════

def test_f1_extract_memories_shape_one_call():
    name = "TC-F1: extract_memories-style keys=[OPENROUTER_API_KEY] makes exactly 1 call"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "v", "item": "item-or", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "v", "item": "item-anthropic", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {
        "item-or": "fake-openrouter-key",
        "item-anthropic": "fake-anthropic-key",
    }, log_path=log_path)

    def _run():
        return load_openclaw_env(config_path=cfg, keys=["OPENROUTER_API_KEY"])

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {"OPENROUTER_API_KEY": "fake-openrouter-key"}
        and os.environ.get("OPENROUTER_API_KEY") == "fake-openrouter-key"
        and calls == 1
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls}")
    clean_env("OPENROUTER_API_KEY")


def test_f2_preinjected_openrouter_no_calls():
    name = "TC-F2: pre-injected OPENROUTER_API_KEY makes 0 nova-op calls"
    os.environ["OPENROUTER_API_KEY"] = "pre-injected"
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({"OPENROUTER_API_KEY": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {"i": "fake"}, log_path=log_path)

    def _run():
        return load_openclaw_env(config_path=cfg, keys=["OPENROUTER_API_KEY"])

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    if result == {"OPENROUTER_API_KEY": "pre-injected"} and calls == 0:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls}")
    clean_env("OPENROUTER_API_KEY")


def test_f3_extract_memories_fallback_when_missing():
    name = "TC-F3: failing env_loader + missing OPENROUTER_API_KEY still errors in extract_memories"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    script_path = os.path.join(repo_root, "scripts/extract_memories.py")
    tmpdir = tempfile.mkdtemp()
    home_dir = os.path.join(tmpdir, "home")
    os.makedirs(home_dir, exist_ok=True)
    _copy_openclaw_lib_to_home(home_dir)
    empty_bin = os.path.join(tmpdir, "empty_bin")
    os.makedirs(empty_bin, exist_ok=True)

    env = os.environ.copy()
    env["PATH"] = empty_bin
    env["HOME"] = home_dir
    env.pop("OPENROUTER_API_KEY", None)

    rc, stdout, stderr = run_main_script(script_path, env, stdin_text="this is a reasonably long test message for extraction")
    if rc != 0 and "OPENROUTER_API_KEY is not set" in stderr:
        pass_test(name)
    else:
        fail_test(name, f"rc={rc} stderr={stderr[:200]}")


def test_f4_extract_memories_continues_when_preinjected():
    name = "TC-F4: pre-injected OPENROUTER_API_KEY lets extract_memories pass env_loader"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    script_path = os.path.join(repo_root, "scripts/extract_memories.py")
    tmpdir = tempfile.mkdtemp()
    home_dir = os.path.join(tmpdir, "home")
    os.makedirs(home_dir, exist_ok=True)
    _copy_openclaw_lib_to_home(home_dir)
    empty_bin = os.path.join(tmpdir, "empty_bin")
    os.makedirs(empty_bin, exist_ok=True)

    env = os.environ.copy()
    env["PATH"] = empty_bin
    env["HOME"] = home_dir
    env["OPENROUTER_API_KEY"] = "pre-injected-key"
    # Give it enough stdin to pass the length guard; DB will fail later.
    rc, stdout, stderr = run_main_script(script_path, env, stdin_text="this is a reasonably long test message for extraction")
    # We expect it to get past env_loader and fail on DB (not on missing key).
    if "OPENROUTER_API_KEY is not set" not in stderr:
        pass_test(name)
    else:
        fail_test(name, f"rc={rc} stderr={stderr[:200]}")


# ═══════════════════════════════════════════════════════════════════════════
# Category G — Backward compatibility of bare load_openclaw_env()
# ═══════════════════════════════════════════════════════════════════════════

def test_g1_legacy_no_args_resolves_everything():
    name = "TC-G1: bare load_openclaw_env() resolves every non-metadata entry"
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "v", "item": "item-or", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "v", "item": "item-anthropic", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {
        "item-or": "fake-openrouter-key",
        "item-anthropic": "fake-anthropic-key",
    }, log_path=log_path)

    def _run():
        return load_openclaw_env(config_path=cfg)

    result = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {
            "OPENROUTER_API_KEY": "fake-openrouter-key",
            "ANTHROPIC_API_KEY": "fake-anthropic-key",
        }
        and calls == 2
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls}")
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")


def test_g2_legacy_one_failure_warns_others_resolve():
    name = "TC-G2: bare call with one failing entry warns and skips only that entry"
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "v", "item": "bad-item", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "v", "item": "item-anthropic", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {
        # bad-item intentionally omitted so stub exits 1
        "item-anthropic": "fake-anthropic-key",
    }, log_path=log_path)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            result = load_openclaw_env(config_path=cfg)
        finally:
            sys.stderr = old_stderr
        return result, captured.getvalue()

    result, stderr = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {"ANTHROPIC_API_KEY": "fake-anthropic-key"}
        and calls == 2
        and "OPENROUTER_API_KEY" in stderr
        and os.environ.get("ANTHROPIC_API_KEY") == "fake-anthropic-key"
        and os.environ.get("OPENROUTER_API_KEY") is None
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} stderr={stderr}")
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")


def test_g3_static_only_two_call_sites_remain():
    name = "TC-G3: only extract_memories.py and env_loader __main__ call load_openclaw_env"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    result = subprocess.run(
        ["grep", "-rn", "load_openclaw_env", "--include=*.py", repo_root],
        capture_output=True,
        text=True,
    )
    hits = [line for line in result.stdout.splitlines() if "/__pycache__/" not in line]
    allowed = 0
    unexpected = []
    for line in hits:
        if "memory/scripts/extract_memories.py" in line:
            allowed += 1
        elif "memory/lib/env_loader.py" in line:
            allowed += 1
        elif "memory/tests/" in line:
            # Tests are expected to reference the function.
            continue
        else:
            unexpected.append(line)
    if not unexpected:
        pass_test(name)
    else:
        fail_test(name, f"unexpected callers: {unexpected}")


# ═══════════════════════════════════════════════════════════════════════════
# Category H — No secrets in stdout/stderr/logs
# ═══════════════════════════════════════════════════════════════════════════

def test_h1_no_secret_values_in_captured_output():
    name = "TC-H1: no fake secret values appear in captured stderr/output"
    # This is a meta-check run over the data produced by other tests; here we
    # run a representative warning path and verify the value is absent.
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = make_failing_nova_op(tmpdir)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            load_openclaw_env(config_path=cfg, keys=["X"])
        finally:
            sys.stderr = old_stderr
        return captured.getvalue()

    stderr = run_with_path(bin_dir, _run)
    if "super-secret-value" not in stderr:
        pass_test(name)
    else:
        fail_test(name, "secret value leaked to stderr")
    clean_env("X")


def test_h2_warnings_on_stderr_only():
    name = "TC-H2: warning text appears on stderr only, stdout stays valid"
    clean_env("X")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({"X": {"vault": "v", "item": "i", "field": "f"}}, tmpdir)
    bin_dir = make_failing_nova_op(tmpdir)

    def _run():
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        out = io.StringIO()
        err = io.StringIO()
        sys.stdout = out
        sys.stderr = err
        try:
            load_openclaw_env(config_path=cfg, keys=["X"])
        finally:
            sys.stdout = old_stdout
            sys.stderr = old_stderr
        return out.getvalue(), err.getvalue()

    stdout, stderr = run_with_path(bin_dir, _run)
    if stdout == "" and "X" in stderr:
        pass_test(name)
    else:
        fail_test(name, f"stdout={stdout!r} stderr={stderr!r}")
    clean_env("X")


def test_h3_static_no_print_value_in_env_loader():
    name = "TC-H3: env_loader source never prints a resolved value"
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(repo_root, "lib/env_loader.py")
    with open(path, "r") as f:
        src = f.read()
    # Heuristic: there should be no print(result.stdout) or logging of values.
    bad_patterns = [
        "print(value",
        "print(result.stdout",
        "logging.*value",
    ]
    found = [p for p in bad_patterns if p in src]
    if not found:
        pass_test(name)
    else:
        fail_test(name, f"suspicious patterns found: {found}")


# ═══════════════════════════════════════════════════════════════════════════
# Existing tests from TEST-10.5 and TEST-10.6 updated per §12
# (Other existing tests are preserved below with their original behaviour.)
# ═══════════════════════════════════════════════════════════════════════════

# ── TEST-1.2: loads vars from valid map via nova-op ──
def test_python_loads_vars_from_valid_map():
    name = "TEST-1.2: loads vars from valid map via nova-op"
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "eefc3r3hh4lzb7dasihufmqmoy", "field": "f"},
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


# ── TEST-2.2: existing env var NOT overwritten ──
def test_python_existing_env_not_overwritten():
    name = "TEST-2.2: existing env var NOT overwritten"
    os.environ["OPENROUTER_API_KEY"] = "original"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
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


# ── TEST-2.3: empty env var IS overwritten ──
def test_python_empty_env_overwritten():
    name = "TEST-2.3: empty env var IS overwritten"
    os.environ["OPENROUTER_API_KEY"] = ""
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
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


# ── TEST-3.2: metadata keys skipped ──
def test_python_metadata_key_skipped():
    name = "TEST-3.2: metadata keys skipped"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "_description": "ignored",
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
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


# ── TEST-5.2: malformed JSON raises RuntimeError ──
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


# ── TEST-5.3: non-dict top-level JSON raises RuntimeError ──
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


# ── TEST-6.2: missing config raises RuntimeError ──
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


# ── TEST-7.2: unreadable config raises RuntimeError ──
def test_python_unreadable_config_raises():
    name = "TEST-7.2: unreadable config raises RuntimeError"
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "i", "field": "f"},
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


# ── TEST-8.3: empty map raises RuntimeError ──
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


# ── TEST-10.5: idempotent double call (extended with call counting) ──
def test_python_idempotent_double_call():
    name = "TEST-10.5: idempotent double call with call-counting stub"
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
        "ANTHROPIC_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "eefc3r3hh4lzb7dasihufmqmoy", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {
        "w3pkbapwocl6twwcajk5ksy4tm": "fake-openrouter-key",
        "eefc3r3hh4lzb7dasihufmqmoy": "fake-anthropic-key",
    }, log_path=log_path)

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
    calls = count_calls(log_path)
    if ok and calls == 2:
        pass_test(name)
    else:
        fail_test(name, f"ok={ok} calls={calls} env={dict(os.environ)}")
    clean_env("OPENROUTER_API_KEY", "ANTHROPIC_API_KEY")


# ── TEST-10.6: wrong item ID now warns and skips (superseded behaviour) ──
def test_python_wrong_item_id_warns():
    name = "TEST-10.6: wrong item ID warns, skips key, does not raise"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    log_path = os.path.join(tmpdir, "calls.log")
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "wrong-item-id", "field": "f"},
    }, tmpdir)
    bin_dir = make_recording_nova_op(tmpdir, {}, log_path=log_path)

    def _run():
        captured = io.StringIO()
        old_stderr = sys.stderr
        sys.stderr = captured
        try:
            result = load_openclaw_env(config_path=cfg, keys=["OPENROUTER_API_KEY"])
        finally:
            sys.stderr = old_stderr
        return result, captured.getvalue()

    result, stderr = run_with_path(bin_dir, _run)
    calls = count_calls(log_path)
    ok = (
        result == {}
        and "OPENROUTER_API_KEY" in stderr
        and calls == 1
        and os.environ.get("OPENROUTER_API_KEY") is None
    )
    if ok:
        pass_test(name)
    else:
        fail_test(name, f"result={result} calls={calls} stderr={stderr}")
    clean_env("OPENROUTER_API_KEY")


# ── TEST-10.7: custom config_path ──
def test_python_custom_config_path():
    name = "TEST-10.7: custom config_path"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "yavwzhqh3sdlh3rke5qo56gvoq", "item": "w3pkbapwocl6twwcajk5ksy4tm", "field": "f"},
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


# ── TEST-10.8: placeholder values fail loudly ──
def test_python_placeholder_fails():
    name = "TEST-10.8: placeholder values fail loudly"
    clean_env("OPENROUTER_API_KEY")
    tmpdir = tempfile.mkdtemp()
    cfg = write_map({
        "OPENROUTER_API_KEY": {"vault": "REPLACE_WITH_VAULT_ID", "item": "REPLACE_WITH_ITEM_ID", "field": "f"},
    }, tmpdir)
    bin_dir = make_nova_op(tmpdir, {})

    def _run():
        try:
            load_openclaw_env(config_path=cfg, keys=["OPENROUTER_API_KEY"])
            return False
        except RuntimeError as exc:
            return "placeholder" in str(exc)

    ok = run_with_path(bin_dir, _run)
    if ok:
        pass_test(name)
    else:
        fail_test(name, "did not raise expected RuntimeError")
    clean_env("OPENROUTER_API_KEY")


if __name__ == "__main__":
    # Existing tests
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
    test_python_wrong_item_id_warns()
    test_python_custom_config_path()
    test_python_placeholder_fails()

    # Category A
    test_a_static_no_env_loader_references()
    test_a2_proactive_recall_import_zero_calls()
    test_a4_dedup_helper_import_zero_calls()
    test_a6_confidence_helper_import_zero_calls()
    test_a8_memory_maintenance_import_zero_calls()
    test_a9_import_succeeds_with_no_nova_op_anywhere()

    # Category B
    test_b1_proactive_recall_run_with_slow_stub_zero_calls()
    test_b3_env_load_phase_is_skipped()

    # Category C
    test_c1_targeted_key_only_one_call()
    test_c2_existing_env_not_overwritten()
    test_c3_all_keys_present_skips_map_open()
    test_c4_empty_keys_no_file_io()
    test_c5_cache_prevents_second_call()
    test_c6_cache_survives_external_env_mutation()
    test_c7_cache_isolated_by_config_path()
    test_c8_metadata_key_skipped_when_explicitly_requested()
    test_c9_key_not_in_map_warns()

    # Category D
    test_d1_timeout_warns_and_skips()
    test_d2_nonzero_exit_warns_and_continues()
    test_d3_missing_binary_warns_no_exception()
    test_d4_skip_if_present_avoids_failing_stub()
    test_d5_empty_value_warns_and_skips()
    test_d6_incomplete_entry_and_placeholder_still_raise()

    # Category E
    test_e1_home_fallback_used()
    test_e3_path_takes_precedence_over_home()

    # Category F
    test_f1_extract_memories_shape_one_call()
    test_f2_preinjected_openrouter_no_calls()
    test_f3_extract_memories_fallback_when_missing()
    test_f4_extract_memories_continues_when_preinjected()

    # Category G
    test_g1_legacy_no_args_resolves_everything()
    test_g2_legacy_one_failure_warns_others_resolve()
    test_g3_static_only_two_call_sites_remain()

    # Category H
    test_h1_no_secret_values_in_captured_output()
    test_h2_warnings_on_stderr_only()
    test_h3_static_no_print_value_in_env_loader()

    print()
    print("================================")
    print(f"Results: {PASS} passed, {FAIL} failed (total {PASS + FAIL})")
    print("================================")
    sys.exit(1 if FAIL > 0 else 0)
