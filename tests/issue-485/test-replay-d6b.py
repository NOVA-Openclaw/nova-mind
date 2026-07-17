#!/usr/bin/env python3
"""TC-D6b — replay body reconstruction with pipe and embedded newline.

This tests the fix for BUG-1: extraction_failures rows whose content contains
literal `|` characters or embedded newlines must replay byte-identically.
"""

import os
import subprocess
import sys
import tempfile
import time


def require_env(name):
    val = os.environ.get(name)
    if not val:
        print(f"FAIL: {name} is not set")
        sys.exit(1)
    return val


DB = require_env("TEST_PGDATABASE")
USER = require_env("TEST_PGUSER")
HOST = require_env("TEST_PGHOST")
DDL_USER = os.environ.get("TEST_PGUSER_DDL", USER)
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
REPLAY_SCRIPT = os.path.join(REPO_ROOT, "memory/scripts/extraction-replay.sh")

EXPECTED_BODY = "line one | pipe\nline two\nline three"
EXPECTED_BODY_FK = "FK body | pipe\nwith newline"

PASS = 0
FAIL = 0


def psql(sql, user=None):
    u = user or USER
    env = os.environ.copy()
    env.pop("PGPASSWORD", None)
    env["PGUSER"] = u
    env["PGDATABASE"] = DB
    env["PGHOST"] = HOST
    result = subprocess.run(
        ["psql", "-t", "-A", "-c", sql],
        env=env,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip(), result.returncode, result.stderr


def assert_eq(name, expected, actual):
    global PASS, FAIL
    if expected == actual:
        print(f"PASS: {name}")
        PASS += 1
    else:
        print(f"FAIL: {name} (expected={expected!r}, actual={actual!r})")
        FAIL += 1


def cleanup(marker):
    psql(f"DELETE FROM extraction_failures WHERE session_key LIKE '{marker}%';", DDL_USER)
    psql(f"DELETE FROM channel_transcripts WHERE external_message_id LIKE '{marker}%';", DDL_USER)
    psql(f"DELETE FROM channel_sessions WHERE session_key LIKE '{marker}%';", DDL_USER)


def run_replay(record_script):
    env = os.environ.copy()
    env.pop("PGPASSWORD", None)
    env["PGUSER"] = USER
    env["PGDATABASE"] = DB
    env["PGHOST"] = HOST
    env["EXTRACTION_SCRIPT_PATH_OVERRIDE"] = record_script
    env["EXTRACTION_REPLAY_BATCH_LIMIT"] = "10"
    result = subprocess.run(
        ["bash", REPLAY_SCRIPT],
        env=env,
        capture_output=True,
        text=True,
    )
    return result


def main():
    global PASS, FAIL

    marker = f"tc-d6b-{int(time.time() * 1000)}"
    cleanup(marker)

    # FK path: transcript holds the body, dead-letter content is NULL.
    session_key = f"{marker}-session"
    msg_id = f"{marker}-msg-fk"
    psql(
        f"""INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type)
VALUES ('{session_key}', 'main', 'openclaw', '{marker}-chat', 'direct');""",
        DDL_USER,
    )
    sess_id, _, _ = psql(f"SELECT id FROM channel_sessions WHERE session_key = '{session_key}';", DDL_USER)
    psql(
        f"""INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content)
VALUES ({sess_id}, '{msg_id}', NOW(), 'user', $BODY${EXPECTED_BODY_FK}$BODY$);""",
        DDL_USER,
    )
    tx_id, _, _ = psql(f"SELECT id FROM channel_transcripts WHERE external_message_id = '{msg_id}';", DDL_USER)
    psql(
        f"""INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
VALUES ({tx_id}, '{session_key}', 'D6bFKSender', NULL, 'pending');""",
        DDL_USER,
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        record_fk = os.path.join(tmpdir, "record_fk.py")
        recorded_fk = os.path.join(tmpdir, "recorded_fk.bin")
        with open(record_fk, "w") as f:
            f.write(
                f"""import sys
with open('{recorded_fk}', 'wb') as f:
    f.write(sys.stdin.buffer.read())
sys.exit(0)
"""
            )
        os.chmod(record_fk, 0o755)

        res = run_replay(record_fk)
        if res.returncode != 0:
            print("replay stderr:", res.stderr)

        status, _, _ = psql(
            f"SELECT status FROM extraction_failures WHERE session_key = '{session_key}';", DDL_USER
        )
        assert_eq("TC-D6b: FK row resolved on replay", "resolved", status)

        with open(recorded_fk, "rb") as f:
            recorded = f.read()
        assert_eq(
            "TC-D6b: FK body byte-identical (pipe + newline)",
            EXPECTED_BODY_FK.encode("utf-8"),
            recorded,
        )

        # Fallback path: dead-letter content holds the body.
        cleanup(marker)
        session_key_fb = f"{marker}-session-fb"
        psql(
            f"""INSERT INTO extraction_failures (channel_transcript_id, session_key, sender_name, content, status)
VALUES (NULL, '{session_key_fb}', 'D6bFallbackSender', $BODY${EXPECTED_BODY}$BODY$, 'pending');""",
            DDL_USER,
        )
        recorded_fb = os.path.join(tmpdir, "recorded_fb.bin")
        record_fb = os.path.join(tmpdir, "record_fb.py")
        with open(record_fb, "w") as f:
            f.write(
                f"""import sys
with open('{recorded_fb}', 'wb') as f:
    f.write(sys.stdin.buffer.read())
sys.exit(0)
"""
            )
        os.chmod(record_fb, 0o755)

        res = run_replay(record_fb)
        if res.returncode != 0:
            print("replay stderr:", res.stderr)

        status, _, _ = psql(
            f"SELECT status FROM extraction_failures WHERE session_key = '{session_key_fb}';", DDL_USER
        )
        assert_eq("TC-D6b: fallback row resolved on replay", "resolved", status)

        with open(recorded_fb, "rb") as f:
            recorded = f.read()
        assert_eq(
            "TC-D6b: fallback body byte-identical (pipe + newline)",
            EXPECTED_BODY.encode("utf-8"),
            recorded,
        )

    cleanup(marker)
    print(f"TC-D6b summary: PASS={PASS} FAIL={FAIL}")
    sys.exit(0 if FAIL == 0 else 1)


if __name__ == "__main__":
    main()
