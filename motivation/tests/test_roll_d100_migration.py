"""
Regression test for nova-mind#444 and #803.

Pytest's mock-based coverage of announce-d100-rolls.py cannot catch SQL-level
errors inside the SECURITY DEFINER roll_d100() function (e.g., ambiguous column
references caused by PL/pgSQL output-parameter names colliding with table
columns). This test loads roll_d100() directly from the relevant migration —
the source of truth — into the configured database and calls it end-to-end.

Area A-H tests (nova-mind#803) run against throwaway databases created and
dropped by name. Area I tests are marked skip-unless-post-deploy.
"""

import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
MIGRATION_PATH = REPO_ROOT / "memory" / "migrations" / "084_d100_motivation_refinements.sql"
MIGRATION_PATH_089 = REPO_ROOT / "memory" / "migrations" / "089_d100_weights.sql"
# Use a valid, currently empty non-reserved roll for deterministic seeding.
TEST_ROLL = 65

# Ensure the real psycopg2 driver is available before anything else can mock it.
for _psycopg2_mod in ("psycopg2", "psycopg2.extras", "psycopg2.extensions"):
    sys.modules.pop(_psycopg2_mod, None)
import psycopg2  # noqa: E402

if not hasattr(psycopg2, "connect") or psycopg2.connect is None:
    pytest.skip("psycopg2 driver not available", allow_module_level=True)


def _load_pg_env() -> None:
    """Bring pg_env values into os.environ if the loader is available."""
    try:
        from pg_env import load_pg_env  # type: ignore

        env = load_pg_env()
        if env is not None:
            for key, value in env.items():
                if value is not None:
                    os.environ[key] = str(value)
    except ImportError:
        pass


def _extract_roll_d100_block(sql: str) -> str:
    """Extract the CREATE OR REPLACE FUNCTION roll_d100() ... $$; block.

    Works for both migration 084 (which prefixes a DROP FUNCTION) and
    migration 089 (plain CREATE OR REPLACE). The returned block starts at
    the CREATE statement and ends at the function body's closing $$;.
    """
    start = sql.find("CREATE OR REPLACE FUNCTION roll_d100()")
    if start == -1:
        raise ValueError("CREATE OR REPLACE FUNCTION roll_d100() not found in migration")

    end = sql.find("$$;", start)
    if end == -1:
        raise ValueError("End of roll_d100() function body ($$;) not found in migration")

    return sql[start:end + 3]


def _connect():
    _load_pg_env()

    return psycopg2.connect(
        host=os.environ.get("PGHOST", "/var/run/postgresql"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("PGDATABASE", "nova_memory"),
        user=os.environ.get("PGUSER", "nova"),
    )


# ---------------------------------------------------------------------------
# Throwaway-database infrastructure for nova-mind#803 (Areas A-H).
# ---------------------------------------------------------------------------


def _admin_conn():
    """Connect to the postgres maintenance database as the nova user."""
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(host="localhost", user="nova", dbname="postgres")


def _connect_to_db(db_name: str):
    """Connect to a named throwaway database as the nova user."""
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(host="localhost", user="nova", dbname=db_name)


def _create_throwaway_db() -> str:
    """Create and return a uniquely-named throwaway database."""
    db_name = f"nova_memory_test_803_{uuid.uuid4().hex[:8]}"
    admin = _admin_conn()
    admin.autocommit = True
    with admin.cursor() as cur:
        cur.execute("DROP DATABASE IF EXISTS %s", (psycopg2.extensions.AsIs(db_name),))
        cur.execute("CREATE DATABASE %s", (psycopg2.extensions.AsIs(db_name),))
    admin.close()
    return db_name


def _drop_throwaway_db(db_name: str) -> None:
    """Drop a throwaway database created by _create_throwaway_db, by name."""
    try:
        admin = _admin_conn()
        admin.autocommit = True
        with admin.cursor() as cur:
            cur.execute(
                "DROP DATABASE IF EXISTS %s",
                (psycopg2.extensions.AsIs(db_name),),
            )
        admin.close()
    except Exception:
        pass


def _load_minimal_d100_schema(conn) -> None:
    """Create the minimal pre-089 schema needed to test roll_d100().

    Includes motivation_d100, d100_roll_log, and the two triggers that the
    #803 tests depend on. This avoids loading the entire database/schema.sql
    and its role/extension dependencies for fast unit tests.
    """
    with conn.cursor() as cur:
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS motivation_d100 (
                roll integer,
                task_name varchar(255),
                task_description text,
                workflow_id integer,
                skill_name varchar(255),
                tool_name varchar(255),
                difficulty varchar(20) DEFAULT 'medium',
                energy_required varchar(20) DEFAULT 'low',
                estimated_minutes integer,
                enabled boolean DEFAULT true,
                times_rolled integer DEFAULT 0,
                times_completed integer DEFAULT 0,
                last_rolled timestamp,
                last_completed timestamp,
                created_at timestamp DEFAULT now(),
                notes text,
                reserved boolean DEFAULT false NOT NULL,
                populated_at timestamptz,
                CONSTRAINT motivation_d100_pkey PRIMARY KEY (roll),
                CONSTRAINT motivation_d100_roll_check CHECK (roll >= 1 AND roll <= 100)
            );

            CREATE TABLE IF NOT EXISTS d100_roll_log (
                id SERIAL,
                roll integer NOT NULL,
                rolled_at timestamptz DEFAULT now(),
                announced_at timestamptz,
                CONSTRAINT d100_roll_log_pkey PRIMARY KEY (id),
                CONSTRAINT d100_roll_log_roll_check CHECK (roll >= 1 AND roll <= 100)
            );

            CREATE INDEX IF NOT EXISTS idx_d100_roll_log_rolled_at
                ON d100_roll_log(rolled_at DESC);

            CREATE OR REPLACE FUNCTION _trg_log_d100_roll()
            RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.last_rolled IS DISTINCT FROM OLD.last_rolled
                   AND NEW.last_rolled IS NOT NULL THEN
                    INSERT INTO d100_roll_log (roll, rolled_at)
                    VALUES (NEW.roll, NEW.last_rolled);
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            DROP TRIGGER IF EXISTS trg_log_d100_roll ON motivation_d100;
            CREATE TRIGGER trg_log_d100_roll
                AFTER UPDATE ON motivation_d100
                FOR EACH ROW
                EXECUTE FUNCTION _trg_log_d100_roll();

            CREATE OR REPLACE FUNCTION _trg_set_populated_at()
            RETURNS TRIGGER
            LANGUAGE plpgsql
            SECURITY DEFINER
            SET search_path = public
            AS $$
            BEGIN
                IF TG_OP = 'INSERT' THEN
                    IF NEW.task_name IS NOT NULL AND NEW.populated_at IS NULL THEN
                        NEW.populated_at := NOW();
                    END IF;
                ELSIF TG_OP = 'UPDATE' THEN
                    IF OLD.task_name IS NULL AND NEW.task_name IS NOT NULL
                       AND NEW.populated_at IS NULL THEN
                        NEW.populated_at := NOW();
                    END IF;
                END IF;
                RETURN NEW;
            END;
            $$;

            DROP TRIGGER IF EXISTS trg_set_populated_at ON motivation_d100;
            CREATE TRIGGER trg_set_populated_at
                BEFORE INSERT OR UPDATE ON motivation_d100
                FOR EACH ROW
                EXECUTE FUNCTION _trg_set_populated_at();
            """
        )
    conn.commit()


def _apply_migration_089(conn) -> None:
    """Apply migration 089's change SQL to an open connection."""
    migration_sql = MIGRATION_PATH_089.read_text()
    with conn.cursor() as cur:
        cur.execute(migration_sql)
    conn.commit()


# ---------------------------------------------------------------------------
# Existing nova-mind#444 tests (must remain untouched in behavior).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_deployed_roll_d100_runs_without_privilege_errors():
    """
    TC-444-PRIV-01: the live, deployed roll_d100() function can be called by
    the nova role and returns a row. This catches column-grant regressions
    (e.g. missing UPDATE on tracking columns) that migration-only tests miss
    because they recreate the function as the table owner.
    """
    conn = _connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            row = cur.fetchone()

            assert row is not None, "deployed roll_d100() returned no row"
            assert isinstance(row[0], int), f"expected integer roll, got {row[0]!r}"
            assert 1 <= row[0] <= 100, f"roll {row[0]} out of 1-100 range"
    finally:
        conn.rollback()
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_d100_from_migration_returns_row():
    """
    TC-444-ADV-09: source-of-truth migration function executes without
    ambiguity errors and returns a populated row.
    """
    migration_sql = MIGRATION_PATH.read_text()
    function_sql = _extract_roll_d100_block(migration_sql)

    conn = _connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            # Install the migration-084 roll_d100() in this transaction.
            cur.execute(function_sql)

            # Seed a single populated+enabled row and disable all empty slots so
            # the function is guaranteed to take the populated-task path.
            cur.execute(
                """
                INSERT INTO motivation_d100 (
                    roll, task_name, task_description, enabled, populated_at
                ) VALUES (
                    %s, 'Migration regression smoke test task',
                    'Temporary row for roll_d100 smoke test', true, now()
                )
                ON CONFLICT (roll) DO UPDATE SET
                    task_name = EXCLUDED.task_name,
                    task_description = EXCLUDED.task_description,
                    enabled = true,
                    populated_at = COALESCE(motivation_d100.populated_at, now());
                """,
                (TEST_ROLL,),
            )
            cur.execute("UPDATE motivation_d100 SET enabled = false WHERE task_name IS NULL;")

            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            row = cur.fetchone()

            assert row is not None, "roll_d100() returned no row"
            assert row[-1] is False, f"Expected is_populate_me=False for populated row, got {row[-1]}"
            assert 1 <= row[0] <= 100, f"roll {row[0]} out of 1-100 range"
    finally:
        conn.rollback()
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_d100_from_migration_anti_repeat_no_ambiguous_column():
    """
    #453 regression: the anti-repeat CTE must expose an aliased column
    (admitted_roll) so that `p.roll IN (SELECT admit.admitted_roll FROM admit)`
    does not collide with roll_d100()'s output column `roll`.

    This test forces the populated-slot path with a recently-rolled row so the
    admit CTE is evaluated.
    """
    migration_sql = MIGRATION_PATH.read_text()
    function_sql = _extract_roll_d100_block(migration_sql)

    conn = _connect()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            cur.execute(function_sql)

            # Seed one populated+enabled row, mark it rolled very recently, and
            # disable all empty slots so the draw must take the anti-repeat path.
            cur.execute(
                """
                INSERT INTO motivation_d100 (
                    roll, task_name, task_description, enabled, populated_at,
                    times_rolled, last_rolled
                ) VALUES (
                    %s, 'Anti-repeat ambiguity regression task',
                    'Temporary row for anti-repeat ambiguity test', true, now(),
                    1, now()
                )
                ON CONFLICT (roll) DO UPDATE SET
                    task_name = EXCLUDED.task_name,
                    task_description = EXCLUDED.task_description,
                    enabled = true,
                    populated_at = COALESCE(motivation_d100.populated_at, now()),
                    times_rolled = EXCLUDED.times_rolled,
                    last_rolled = EXCLUDED.last_rolled;
                """,
                (TEST_ROLL,),
            )
            cur.execute("UPDATE motivation_d100 SET enabled = false WHERE task_name IS NULL;")

            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            row = cur.fetchone()

            assert row is not None, "roll_d100() returned no row"
            assert isinstance(row[0], int), f"expected integer roll, got {row[0]!r}"
            assert 1 <= row[0] <= 100, f"roll {row[0]} out of 1-100 range"
    finally:
        conn.rollback()
        conn.close()


# ---------------------------------------------------------------------------
# nova-mind#803 Chunk 1 smoke test: migration applies and roll_d100() works.
# ---------------------------------------------------------------------------


@pytest.fixture
def db_803():
    """Yield a fresh throwaway DB for #803 tests and clean it up by name."""
    db_name = _create_throwaway_db()
    try:
        yield db_name
    finally:
        _drop_throwaway_db(db_name)


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_applies_cleanly_and_roll_d100_returns_row(db_803):
    """
    Chunk 1 smoke test: migration 089 applies to a minimal throwaway schema,
    the weight column has the right shape, and roll_d100() returns a row.
    """
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)

        with conn.cursor() as cur:
            # Verify weight column shape.
            cur.execute(
                """
                SELECT data_type, is_nullable, column_default
                FROM information_schema.columns
                WHERE table_name = 'motivation_d100' AND column_name = 'weight'
                """
            )
            row = cur.fetchone()
            assert row is not None, "weight column not found"
            assert row[0] == "numeric", f"expected numeric, got {row[0]}"
            assert row[1] == "NO", f"expected NOT NULL, got nullable={row[1]}"
            assert row[2] == "1", f"expected default 1, got {row[2]}"

            # Seed one populated eligible slot.
            cur.execute(
                """
                INSERT INTO motivation_d100 (roll, task_name, task_description, enabled, populated_at, weight)
                VALUES (1, 'Smoke task', 'Smoke description', true, now(), 1.5)
                """
            )

            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            result = cur.fetchone()
            assert result is not None, "roll_d100() returned no row"
            assert len(result) == 15, f"expected 15 columns, got {len(result)}"
            assert result[0] == 1, f"expected roll 1, got {result[0]}"
            assert result[-1] is False, f"expected is_populate_me=False, got {result[-1]}"
    finally:
        conn.close()
