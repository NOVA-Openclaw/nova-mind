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

import importlib.util
import os
import subprocess
import sys
import uuid
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent.parent
MIGRATION_PATH = REPO_ROOT / "memory" / "migrations" / "084_d100_motivation_refinements.sql"
MIGRATION_PATH_089 = REPO_ROOT / "memory" / "migrations" / "089_d100_weights.sql"
ANNOUNCE_SCRIPT = REPO_ROOT / "memory" / "scripts" / "announce-d100-rolls.py"
# Use a valid, currently empty non-reserved roll for deterministic seeding.
TEST_ROLL = 65

EXPECTED_ROLL_D100_SIGNATURE = (
    "TABLE(roll integer, task_name character varying, task_description text, "
    "workflow_id integer, skill_name character varying, tool_name character varying, "
    "difficulty character varying, energy_required character varying, "
    "estimated_minutes integer, times_rolled integer, times_completed integer, "
    "last_rolled timestamp without time zone, last_completed timestamp without time zone, "
    "notes text, is_populate_me boolean)"
)

# Ensure the real psycopg2 driver is available before anything else can mock it.
for _psycopg2_mod in ("psycopg2", "psycopg2.extras", "psycopg2.extensions"):
    sys.modules.pop(_psycopg2_mod, None)
import psycopg2  # noqa: E402
from psycopg2 import sql  # noqa: E402

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
        user=os.environ.get("PGUSER"),
    )


# ---------------------------------------------------------------------------
# Throwaway-database infrastructure for nova-mind#803 (Areas A-H).
# ---------------------------------------------------------------------------


def _admin_conn():
    """Connect to the postgres maintenance database using the current libpq/env user."""
    _load_pg_env()
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname="postgres",
        user=os.environ.get("PGUSER"),
    )


def _connect_to_db(db_name: str):
    """Connect to a named throwaway database using the current libpq/env user."""
    _load_pg_env()
    os.environ.pop("PGPASSWORD", None)
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=db_name,
        user=os.environ.get("PGUSER"),
    )


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
# nova-mind#803 Chunk 2: statistical/oracle helpers and Areas A-D tests.
# ---------------------------------------------------------------------------


def _run_simulation(
    conn,
    n: int,
    seed: float | None = None,
    reset_populated_last_rolled: bool = False,
    preserve_last_rolled: bool = False,
) -> dict[int, int]:
    """Run roll_d100() n times in the database and return {roll: count}.

    Options:
      reset_populated_last_rolled: set last_rolled = NULL for populated slots
        once before the loop (neutralizes anti-repeat for pure weight tests).
      preserve_last_rolled: capture and restore last_rolled before every
        iteration (keeps the anti-repeat admission set static across a long
        loop, which is required for Area C's exact exclusion assertions).
    """
    with conn.cursor() as cur:
        if seed is not None:
            cur.execute("SELECT setseed(%s)", (seed,))
        if reset_populated_last_rolled:
            cur.execute(
                "UPDATE motivation_d100 SET last_rolled = NULL WHERE task_name IS NOT NULL"
            )

        if preserve_last_rolled or reset_populated_last_rolled:
            # Capture the (possibly reset) last_rolled state and restore it
            # before every iteration. For reset_populated_last_rolled this
            # keeps populated slots at NULL so anti-repeat stays neutralized.
            restore_sql = """
                CREATE TEMP TABLE IF NOT EXISTS _lr_snapshot_803 (roll integer, last_rolled timestamp) ON COMMIT DROP;
                TRUNCATE _lr_snapshot_803;
                INSERT INTO _lr_snapshot_803 SELECT roll, last_rolled FROM motivation_d100;
            """
            loop_body = """
                UPDATE motivation_d100 m
                SET last_rolled = s.last_rolled
                FROM _lr_snapshot_803 s
                WHERE m.roll = s.roll;
                INSERT INTO _sim_results_803 (roll) SELECT roll FROM roll_d100() LIMIT 1;
            """
        else:
            restore_sql = ""
            loop_body = """
                INSERT INTO _sim_results_803 (roll) SELECT roll FROM roll_d100() LIMIT 1;
            """

        query = sql.SQL(
            """
            CREATE TEMP TABLE IF NOT EXISTS _sim_results_803 (roll integer) ON COMMIT DROP;
            TRUNCATE _sim_results_803;
            {restore_sql}
            DO $$
            BEGIN
                FOR i IN 1..{n} LOOP
                    {loop_body}
                END LOOP;
            END $$;
            SELECT roll, count(*) FROM _sim_results_803 GROUP BY roll ORDER BY roll;
            """
        ).format(
            n=sql.Literal(n),
            restore_sql=sql.SQL(restore_sql),
            loop_body=sql.SQL(loop_body),
        )
        cur.execute(query)
        return {row[0]: row[1] for row in cur.fetchall()}


def _assert_distribution(
    counts: dict[int, int],
    expected_weights: dict[int, float],
    n: int,
) -> None:
    """Binomial 4-sigma + relative-floor tolerance oracle (Section 2)."""
    total_weight = sum(expected_weights.values())
    assert total_weight > 0, "expected_weights must sum to > 0"
    for roll, weight in expected_weights.items():
        p = weight / total_weight
        mu = n * p
        sigma = (n * p * (1 - p)) ** 0.5
        observed = counts.get(roll, 0)
        band = max(4 * sigma, 0.02 * mu)
        assert abs(observed - mu) <= band, (
            f"roll {roll}: observed {observed}, expected {mu:.2f}, "
            f"band {band:.2f}, weight {weight}"
        )


def _assert_zero(counts: dict[int, int], rolls: list[int]) -> None:
    """Assert that every listed roll was never drawn."""
    for roll in rolls:
        assert counts.get(roll, 0) == 0, f"roll {roll} was drawn {counts.get(roll)} times"


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
# nova-mind#803 tests.
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
def test_roll_d100_ignores_caller_temp_table_shadow(db_803):
    """
    SECURITY: a caller-created `_roll_d100_eligible` temp table cannot
    influence the weighted draw. roll_d100() uses CTEs, not temp tables, and
    runs with search_path = public, pg_temp.
    """
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)

        with conn.cursor() as cur:
            # One real eligible populated slot.
            cur.execute(
                """
                INSERT INTO motivation_d100 (
                    roll, task_name, task_description, enabled, populated_at, weight
                ) VALUES (1, 'Real task', 'Real description', true, now(), 1)
                """
            )

            # Malicious shadow temp table with a high-weight junk roll.
            cur.execute(
                """
                CREATE TEMP TABLE _roll_d100_eligible (
                    roll integer,
                    weight numeric,
                    is_populate_me boolean
                )
                """
            )
            cur.execute(
                "INSERT INTO _roll_d100_eligible VALUES (999, 1000000, false)"
            )

            cur.execute("SELECT * FROM roll_d100() LIMIT 1;")
            row = cur.fetchone()

            assert row is not None, "roll_d100() returned no row"
            assert row[0] == 1, (
                f"caller-created temp table shadowed the draw: got roll {row[0]}"
            )
            assert row[-1] is False, f"expected populated slot, got is_populate_me={row[-1]}"
    finally:
        conn.close()


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


# ---------------------------------------------------------------------------
# Area A: Migration tests (M1-M9).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_applies_cleanly_and_defaults_weight_to_one(db_803):
    """M1: change SQL applies cleanly; pre-existing rows read weight=1."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        # Pre-seed a few rows before migration.
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO motivation_d100 (roll, task_name, enabled)
                VALUES (1, 'Pre-existing populated', true),
                       (2, NULL, true)
                """
            )
        _apply_migration_089(conn)

        with conn.cursor() as cur:
            cur.execute("SELECT roll, weight FROM motivation_d100 ORDER BY roll")
            rows = cur.fetchall()
            assert rows == [(1, 1), (2, 1)], f"unexpected rows/weights: {rows}"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_is_idempotent(db_803):
    """M2: applying migration 089 twice is a safe no-op."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        _apply_migration_089(conn)  # second run must not error

        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM information_schema.columns "
                        "WHERE table_name='motivation_d100' AND column_name='weight'")
            assert cur.fetchone()[0] == 1, "weight column missing after second apply"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_preserves_custom_weight(db_803):
    """M3: idempotent re-run preserves customized weights."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, enabled) VALUES (71, true)")
            cur.execute("UPDATE motivation_d100 SET weight = 3 WHERE roll = 71")
        _apply_migration_089(conn)

        with conn.cursor() as cur:
            cur.execute("SELECT weight FROM motivation_d100 WHERE roll = 71")
            assert cur.fetchone()[0] == 3, "custom weight was reset by second apply"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_rejects_negative_weight(db_803):
    """M4: CHECK (weight >= 0) rejects negative values."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, enabled) VALUES (1, true)")
        conn.commit()
        with pytest.raises(psycopg2.errors.CheckViolation):
            with conn.cursor() as cur:
                cur.execute("UPDATE motivation_d100 SET weight = -1 WHERE roll = 1")
            conn.commit()
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_enforces_not_null_weight(db_803):
    """M5: weight NOT NULL rejects NULL."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, enabled) VALUES (1, true)")
        conn.commit()
        with pytest.raises(psycopg2.errors.NotNullViolation):
            with conn.cursor() as cur:
                cur.execute("UPDATE motivation_d100 SET weight = NULL WHERE roll = 1")
            conn.commit()
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_accepts_zero_and_fractional_weights(db_803):
    """M6: numeric column accepts 0 and fractional weights."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, enabled) VALUES (1, true)")
            for value in (0, 0.5, 2.5):
                cur.execute("UPDATE motivation_d100 SET weight = %s WHERE roll = 1", (value,))
            cur.execute(
                "SELECT data_type FROM information_schema.columns "
                "WHERE table_name='motivation_d100' AND column_name='weight'"
            )
            assert cur.fetchone()[0] == "numeric", "weight column is not numeric"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_grants_update_weight_to_nova(db_803):
    """M7: nova can directly UPDATE the weight content column."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                DO $$
                BEGIN
                    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nova') THEN
                        CREATE ROLE nova NOLOGIN;
                    END IF;
                END $$;
                """
            )
            cur.execute("GRANT ALL ON TABLE motivation_d100 TO nova")
        _apply_migration_089(conn)

        nova_conn = psycopg2.connect(
            host=os.environ.get("PGHOST", "localhost"),
            port=os.environ.get("PGPORT", "5432"),
            dbname=db_803,
            user=os.environ.get("PGUSER"),
        )
        try:
            with nova_conn.cursor() as cur:
                cur.execute("INSERT INTO motivation_d100 (roll, enabled) VALUES (1, true)")
                cur.execute("UPDATE motivation_d100 SET weight = 2 WHERE roll = 1")
                cur.execute("SELECT weight FROM motivation_d100 WHERE roll = 1")
                assert cur.fetchone()[0] == 2
        finally:
            nova_conn.close()
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_roll_d100_signature_unchanged(db_803):
    """M8: roll_d100() keeps the 15-column return signature."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT pg_get_function_result('roll_d100'::regproc),
                       pg_get_function_arguments('roll_d100'::regproc)
                """
            )
            result, arguments = cur.fetchone()
            assert arguments == "", f"expected no arguments, got {arguments}"
            assert result == EXPECTED_ROLL_D100_SIGNATURE, f"unexpected signature: {result}"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_migration_089_extraction_executes_standalone(db_803):
    """M9: the roll_d100() block extracted from 089 runs without the rest of the file."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        # Apply only the column/constraint/grant parts first so the function has a home.
        with conn.cursor() as cur:
            cur.execute("ALTER TABLE motivation_d100 ADD COLUMN IF NOT EXISTS weight numeric NOT NULL DEFAULT 1")
        conn.commit()

        function_sql = _extract_roll_d100_block(MIGRATION_PATH_089.read_text())
        with conn.cursor() as cur:
            cur.execute(function_sql)
            cur.execute("INSERT INTO motivation_d100 (roll, task_name, enabled) VALUES (1, 'x', true)")
            cur.execute("SELECT * FROM roll_d100() LIMIT 1")
            row = cur.fetchone()
            assert row is not None
            assert len(row) == 15
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Area B: Statistical / weighted-distribution tests (S1-S7).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_uniform_baseline_empty_slots(db_803):
    """S1: all-weight-1 uniform baseline for empty slots."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            for roll in (1, 2, 3, 4):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, reserved, enabled) VALUES (%s, false, true)",
                    (roll,),
                )
        counts = _run_simulation(conn, n=1000, seed=0.42)
        expected = {1: 1, 2: 1, 3: 1, 4: 1}
        _assert_distribution(counts, expected, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_uniform_baseline_populated_slots(db_803):
    """S2: all-weight-1 uniform baseline for populated slots, anti-repeat neutralized."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            for roll in (1, 2, 3, 4, 5):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled) VALUES (%s, %s, true)",
                    (roll, f"Task {roll}"),
                )
        counts = _run_simulation(conn, n=1000, seed=0.42, reset_populated_last_rolled=True)
        expected = {r: 1 for r in range(1, 6)}
        _assert_distribution(counts, expected, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_weight_three_empty_slots(db_803):
    """S3: weight-3 slot drawn ~3x as often as weight-1 empty slots."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (1, false, true, 1)")
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (2, false, true, 1)")
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (3, false, true, 3)")
        counts = _run_simulation(conn, n=1000, seed=0.42)
        expected = {1: 1, 2: 1, 3: 3}
        _assert_distribution(counts, expected, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_weight_three_populated_slots(db_803):
    """S4: weight-3 slot drawn ~3x as often as weight-1 populated slots."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            for roll, weight in ((1, 1), (2, 1), (3, 3)):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (%s, %s, true, %s)",
                    (roll, f"Task {roll}", weight),
                )
        counts = _run_simulation(conn, n=1000, seed=0.42, reset_populated_last_rolled=True)
        expected = {1: 1, 2: 1, 3: 3}
        _assert_distribution(counts, expected, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_weight_zero_never_drawn(db_803):
    """S5: weight-0 slots are never drawn."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (1, false, true, 0)")
            cur.execute("INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (2, 'Task 2', true, 1)")
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (3, false, true, 1)")
        counts = _run_simulation(conn, n=1000, seed=0.42)
        _assert_zero(counts, [1])
        _assert_distribution(counts, {2: 1, 3: 1}, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_unified_empty_and_populated_pool(db_803):
    """S6: empty and populated slots compete in one weighted lottery."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (1, false, true, 1)")
            cur.execute("INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (2, 'Task 2', true, 1)")
        counts = _run_simulation(conn, n=1000, seed=0.42)
        _assert_distribution(counts, {1: 1, 2: 1}, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_statistical_fractional_weights_proportional(db_803):
    """S7: fractional weights 0.5 and 1.5 produce a 1:3 ratio (REQUIRED)."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (1, false, true, 0.5)")
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (2, false, true, 1.5)")
        counts = _run_simulation(conn, n=1000, seed=0.42)
        _assert_distribution(counts, {1: 0.5, 2: 1.5}, n=1000)
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Area C: Anti-repeat regression tests (A1-A7).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_recently_rolled_excluded_cap_not_triggered(db_803):
    """A1: a slot rolled 1 day ago is excluded when cap is not triggered."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            for roll in range(1, 11):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled) VALUES (%s, %s, true)",
                    (roll, f"Task {roll}"),
                )
            # Roll 1 is the only recent roll; rolls 2-10 are never-rolled (NULL).
            cur.execute("UPDATE motivation_d100 SET last_rolled = CURRENT_TIMESTAMP WHERE roll = 1")
        counts = _run_simulation(conn, n=1000, seed=0.42, preserve_last_rolled=True)
        _assert_zero(counts, [1])
        _assert_distribution(counts, {r: 1 for r in range(2, 11)}, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_seven_day_boundary_outside_window(db_803):
    """A2: just past the 7-day boundary is eligible."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) "
                "VALUES (1, 'Boundary task', true, CURRENT_TIMESTAMP - interval '7 days' - interval '1 second')"
            )
        seen = set()
        for _ in range(100):
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100()")
                seen.add(cur.fetchone()[0])
        assert seen == {1}, f"expected only roll 1, got {seen}"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_seven_day_boundary_inside_window(db_803):
    """A2b: just inside the 7-day window is excluded when cap does not admit it."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            # One boundary recent slot plus two never-rolled slots.
            # total_pop=3, recent_pop=1, cap=floor(3*0.5)=1 -> admit=0, so boundary is excluded.
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) "
                "VALUES (1, 'Boundary task', true, CURRENT_TIMESTAMP - interval '7 days' + interval '1 second')"
            )
            for roll in (2, 3):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled) VALUES (%s, %s, true)",
                    (roll, f"Task {roll}"),
                )
        counts = _run_simulation(conn, n=500, seed=0.42, preserve_last_rolled=True)
        _assert_zero(counts, [1])
        _assert_distribution(counts, {2: 1, 3: 1}, n=500)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_cap_forces_oldest_readmission(db_803):
    """A3: 50% cap forces oldest recently-rolled slots back in."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            # 10 populated slots: 2 never-rolled, 8 recent at staggered ages.
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) "
                "VALUES (1, 'Never 1', true, NULL), (2, 'Never 2', true, NULL)"
            )
            for i, roll in enumerate(range(3, 11), start=1):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) "
                    "VALUES (%s, %s, true, CURRENT_TIMESTAMP - interval '%s hours')",
                    (roll, f"Recent {roll}", i),
                )
        # total_pop=10, recent_pop=8 -> admit = max(8-5,0) = 3 oldest (rolls 8,9,10 by age).
        counts = _run_simulation(conn, n=1000, seed=0.42, preserve_last_rolled=True)
        excluded = [3, 4, 5, 6, 7]
        admitted = [1, 2, 8, 9, 10]
        _assert_zero(counts, excluded)
        _assert_distribution(counts, {r: 1 for r in admitted}, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_admission_is_weight_blind(db_803):
    """A4: recency admission ignores weight; high-weight excluded slots stay out."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled, weight) "
                "VALUES (1, 'Never 1', true, NULL, 0.1), (2, 'Never 2', true, NULL, 0.1)"
            )
            for i, roll in enumerate(range(3, 11), start=1):
                # Three oldest get tiny weights; five excluded get huge weights.
                w = 0.1 if roll >= 8 else 100
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled, weight) "
                    "VALUES (%s, %s, true, CURRENT_TIMESTAMP - interval '%s hours', %s)",
                    (roll, f"Recent {roll}", i, w),
                )
        counts = _run_simulation(conn, n=1000, seed=0.42, preserve_last_rolled=True)
        excluded = [3, 4, 5, 6, 7]
        admitted = [1, 2, 8, 9, 10]
        _assert_zero(counts, excluded)
        _assert_distribution(counts, {r: 1 for r in admitted}, n=1000)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_null_last_rolled_always_eligible(db_803):
    """A5: last_rolled IS NULL slots are always eligible."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) VALUES (1, 'Always', true, NULL)")
            for roll in range(2, 12):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) VALUES (%s, %s, true, CURRENT_TIMESTAMP)",
                    (roll, f"Recent {roll}"),
                )
        counts = _run_simulation(conn, n=1000, seed=0.42, preserve_last_rolled=True)
        assert counts.get(1, 0) > 0, "never-rolled slot was never drawn"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_weight_zero_admitted_slot_never_drawn(db_803):
    """A6: a recency-admitted slot with weight=0 is still never drawn."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) VALUES (1, 'Never', true, NULL)")
            for i, roll in enumerate(range(2, 11), start=1):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) "
                    "VALUES (%s, %s, true, CURRENT_TIMESTAMP - interval '%s hours')",
                    (roll, f"Recent {roll}", i),
                )
            # Roll 10 would be admitted by recency; zero its weight.
            cur.execute("UPDATE motivation_d100 SET weight = 0 WHERE roll = 10")
        counts = _run_simulation(conn, n=1000, seed=0.42, preserve_last_rolled=True)
        _assert_zero(counts, [10])
        # With roll 10 excluded from cap denominators, the cap math admits the
        # four oldest remaining recent slots (rolls 6-9) plus the never-rolled
        # slot (roll 1). Just assert roll 10 is never drawn and the total is right.
        assert sum(counts.values()) == 1000, f"expected 1000 draws, got {sum(counts.values())}"
        assert counts.get(10, 0) == 0, "weight-0 admitted slot was drawn"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_anti_repeat_weight_zero_excluded_from_cap_denominators(db_803):
    """A7: weight-0 rows are excluded from total_pop/recent_pop cap math."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            # 10 populated: 2 weight-0 (not counted), 8 weight-1 recent.
            # Effective total_pop=8, recent_pop=8 -> admit = max(8-4,0) = 4 oldest.
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled, weight) "
                "VALUES (1, 'Zero A', true, CURRENT_TIMESTAMP, 0), (2, 'Zero B', true, CURRENT_TIMESTAMP, 0)"
            )
            for i, roll in enumerate(range(3, 11), start=1):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled) "
                    "VALUES (%s, %s, true, CURRENT_TIMESTAMP - interval '%s hours')",
                    (roll, f"Recent {roll}", i),
                )
        counts = _run_simulation(conn, n=1000, seed=0.42, preserve_last_rolled=True)
        excluded = [1, 2, 3, 4, 5, 6]
        admitted = [7, 8, 9, 10]
        _assert_zero(counts, excluded)
        _assert_distribution(counts, {r: 1 for r in admitted}, n=1000)
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Area D: Populate-me path tests (P1-P4).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_populate_me_path_returns_slot(db_803):
    """P1: unreserved empty enabled slot -> populate-me."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (5, false, true, 2)"
            )
            cur.execute("SELECT * FROM roll_d100() LIMIT 1")
            row = cur.fetchone()
            assert row is not None
            assert row[0] == 5
            assert row[1] is None, "task_name should be NULL for populate-me"
            assert row[-1] is True, "is_populate_me should be true"
            cur.execute("SELECT times_rolled, last_rolled FROM motivation_d100 WHERE roll = 5")
            times, last = cur.fetchone()
            assert times == 1
            assert last is not None
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_reserved_empty_slot_never_returned(db_803):
    """P2: reserved empty slot is never returned regardless of weight."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (5, true, true, 5)"
            )
        with pytest.raises(psycopg2.errors.RaiseException):
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_disabled_empty_slot_excluded(db_803):
    """P3: disabled empty slot is excluded."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (5, false, false, 5)"
            )
        with pytest.raises(psycopg2.errors.RaiseException):
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_weight_zero_empty_slot_excluded(db_803):
    """P4: weight-0 empty slot is excluded even as the last candidate."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (5, false, true, 0)"
            )
        with pytest.raises(psycopg2.errors.RaiseException):
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Helpers for Areas E-H.
# ---------------------------------------------------------------------------

_ERROR_TEXT = "roll_d100: no populated+enabled tasks found after 20 attempts"


def _assert_all_ineligible_error(exc):
    """Assert that exc carries the exact, byte-for-byte existing error text."""
    assert isinstance(exc, psycopg2.errors.RaiseException)
    primary = getattr(exc, "diag", None) and exc.diag.message_primary
    assert primary == _ERROR_TEXT, f"unexpected error text: {primary!r}"


def _announce_env(db_name: str) -> dict:
    """Return an environment dict that points announce-d100-rolls.py at a throwaway DB."""
    env = os.environ.copy()
    env["PGHOST"] = os.environ.get("PGHOST", "localhost")
    env["PGPORT"] = os.environ.get("PGPORT", "5432")
    env["PGDATABASE"] = db_name
    env.pop("PGPASSWORD", None)
    return env


def _run_announce_dry_run(db_name: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(ANNOUNCE_SCRIPT), "--dry-run"],
        env=_announce_env(db_name),
        capture_output=True,
        text=True,
        cwd=str(REPO_ROOT),
    )


# ---------------------------------------------------------------------------
# Area E: All-ineligible error path (E1-E4).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_all_ineligible_all_weights_zero(db_803):
    """E1: all weights are 0 raises the exact existing error text."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute("INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (1, 'Task 1', true, 0)")
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (2, false, true, 0)")
        with pytest.raises(psycopg2.errors.RaiseException) as excinfo:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
        _assert_all_ineligible_error(excinfo.value)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_all_ineligible_weight_zero_trumps_recency_admission(db_803):
    """E2: weight-0 on every populated row trumps the 50% cap re-admission."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            # 10 populated recent slots, all weight 0.
            for i, roll in enumerate(range(1, 11), start=1):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, last_rolled, weight) "
                    "VALUES (%s, %s, true, CURRENT_TIMESTAMP - interval '%s hours', 0)",
                    (roll, f"Recent {roll}", i),
                )
            # Only empty candidates are reserved/disabled/weight-0.
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (11, true, true, 0)")
            cur.execute("INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (12, false, false, 0)")
        with pytest.raises(psycopg2.errors.RaiseException) as excinfo:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
        _assert_all_ineligible_error(excinfo.value)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_all_ineligible_empty_table(db_803):
    """E3: empty motivation_d100 raises the exact existing error text."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with pytest.raises(psycopg2.errors.RaiseException) as excinfo:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
        _assert_all_ineligible_error(excinfo.value)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_all_ineligible_no_side_effects(db_803):
    """E4: ineligible failure does not touch times_rolled or last_rolled."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, weight, times_rolled, last_rolled) "
                "VALUES (1, 'Task 1', true, 0, 7, '2024-01-01 00:00:00')"
            )
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight, times_rolled, last_rolled) "
                "VALUES (2, false, true, 0, 3, '2024-01-02 00:00:00')"
            )
            cur.execute("SELECT roll, times_rolled, last_rolled FROM motivation_d100 ORDER BY roll")
            before = {row[0]: (row[1], row[2]) for row in cur.fetchall()}
        conn.commit()

        with pytest.raises(psycopg2.errors.RaiseException) as excinfo:
            with conn.cursor() as cur:
                cur.execute("SELECT * FROM roll_d100() LIMIT 1")
        _assert_all_ineligible_error(excinfo.value)

        # The failed call aborts the transaction; roll back and verify nothing changed.
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute("SELECT roll, times_rolled, last_rolled FROM motivation_d100 ORDER BY roll")
            after = {row[0]: (row[1], row[2]) for row in cur.fetchall()}
        assert after == before, f"side effects detected: before={before} after={after}"
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Area F: Trigger & roll-history tests (T1-T5).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_log_exactly_one_row_per_roll(db_803):
    """T1: a successful roll inserts exactly one d100_roll_log row."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (1, 'Task 1', true, 1)"
            )
            cur.execute("SELECT count(*) FROM d100_roll_log")
            before = cur.fetchone()[0]
            cur.execute("SELECT * FROM roll_d100() LIMIT 1")
            row = cur.fetchone()
            cur.execute("SELECT count(*) FROM d100_roll_log")
            after = cur.fetchone()[0]
            assert after == before + 1, f"expected one new log row, got {after - before}"
            cur.execute("SELECT roll FROM d100_roll_log ORDER BY id DESC LIMIT 1")
            assert cur.fetchone()[0] == row[0]
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_log_no_duplicate_on_no_op_update(db_803):
    """T2: updating last_rolled to itself does not insert a log row."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, weight, last_rolled) "
                "VALUES (1, 'Task 1', true, 1, '2024-01-01 00:00:00')"
            )
            cur.execute("SELECT count(*) FROM d100_roll_log")
            before = cur.fetchone()[0]
            cur.execute("UPDATE motivation_d100 SET last_rolled = last_rolled WHERE roll = 1")
            cur.execute("SELECT count(*) FROM d100_roll_log")
            after = cur.fetchone()[0]
            assert after == before, "no-op update created a log row"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_log_populate_me_row(db_803):
    """T3: populate-me path also logs one row."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (5, false, true, 1)"
            )
            cur.execute("SELECT count(*) FROM d100_roll_log")
            before = cur.fetchone()[0]
            cur.execute("SELECT * FROM roll_d100() LIMIT 1")
            row = cur.fetchone()
            assert row[-1] is True
            cur.execute("SELECT count(*) FROM d100_roll_log")
            after = cur.fetchone()[0]
            assert after == before + 1
            cur.execute("SELECT roll FROM d100_roll_log ORDER BY id DESC LIMIT 1")
            assert cur.fetchone()[0] == 5
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_log_weight_only_update_no_row(db_803):
    """T4: changing weight without touching last_rolled does not log."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, weight, last_rolled) "
                "VALUES (1, 'Task 1', true, 1, '2024-01-01 00:00:00')"
            )
            cur.execute("SELECT count(*) FROM d100_roll_log")
            before = cur.fetchone()[0]
            cur.execute("UPDATE motivation_d100 SET weight = 5 WHERE roll = 1")
            cur.execute("SELECT count(*) FROM d100_roll_log")
            after = cur.fetchone()[0]
            assert after == before, "weight-only update created a log row"
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_populated_at_trigger_still_fires(db_803):
    """T5: _trg_set_populated_at still stamps populated_at post-migration."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (5, false, true, 1)"
            )
            cur.execute("SELECT * FROM roll_d100() LIMIT 1")
            row = cur.fetchone()
            assert row[-1] is True
            cur.execute("SELECT populated_at FROM motivation_d100 WHERE roll = 5")
            assert cur.fetchone()[0] is None
            cur.execute(
                "UPDATE motivation_d100 SET task_name = 'x', task_description = 'y', weight = 2.5 WHERE roll = 5"
            )
            cur.execute("SELECT populated_at, task_name FROM motivation_d100 WHERE roll = 5")
            populated_at, task_name = cur.fetchone()
            assert task_name == "x"
            assert populated_at is not None, "populated_at trigger did not fire"
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Area G: Caller compatibility — announce script & return signature (G1-G4).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_announce_script_dry_run_reads_existing_columns(db_803):
    """G1: announce-d100-rolls.py runs unchanged against the post-migration DB."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        result = _run_announce_dry_run(db_803)
        assert result.returncode == 0, (
            f"announce script failed:\nstdout={result.stdout}\nstderr={result.stderr}"
        )
        assert "0 rolls to announce" in result.stdout or "would send" in result.stdout
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_announce_script_end_to_end_roll_trigger_announce(db_803):
    """G2: roll -> trigger -> announce dry-run sees the new log row."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (1, 'Task 1', true, 1)"
            )
            cur.execute("SELECT * FROM roll_d100() LIMIT 1")
            row = cur.fetchone()
            assert row is not None
        conn.commit()  # make the logged roll visible to the separate announce process
        result = _run_announce_dry_run(db_803)
        assert result.returncode == 0, (
            f"announce script failed:\nstdout={result.stdout}\nstderr={result.stderr}"
        )
        assert "[DRY-RUN] would send:" in result.stdout, (
            f"expected dry-run announcement, got:\n{result.stdout}"
        )
        assert str(row[0]) in result.stdout
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_format_roll_unit_no_weight_key():
    """G3: _format_roll() works with the pre-weight dict shape and needs no weight key."""
    spec = importlib.util.spec_from_file_location("announce_d100_rolls", ANNOUNCE_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    populated = {
        "roll": 42,
        "task_name": "Test task",
        "estimated_minutes": 30,
        "difficulty": "hard",
        "last_rolled": None,
        "last_completed": None,
        "reserved": False,
    }
    text = module._format_roll(populated)
    assert '42' in text
    assert "Test task" in text
    assert "30m" in text
    assert "difficulty hard" in text

    populate_me = {
        "roll": 7,
        "task_name": None,
        "estimated_minutes": None,
        "difficulty": None,
        "last_rolled": None,
        "last_completed": None,
        "reserved": False,
    }
    text = module._format_roll(populate_me)
    assert "[ORIGINATION SLOT" in text
    assert "populate & execute" in text


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_roll_d100_return_signature_byte_for_byte(db_803):
    """G4: post-migration roll_d100() returns the exact same 15-column signature."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT pg_get_function_result('roll_d100'::regproc), "
                "       pg_get_function_arguments('roll_d100'::regproc)"
            )
            result, arguments = cur.fetchone()
            assert arguments == "", f"expected no arguments, got {arguments}"
            assert result == EXPECTED_ROLL_D100_SIGNATURE, f"signature mismatch: {result}"
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Area H: Weight update takes effect immediately (W1-W2).
# ---------------------------------------------------------------------------


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_weight_bump_shifts_distribution_immediately(db_803):
    """W1: raising a slot's weight in the same session shifts the next draws."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            for roll in (1, 2, 3):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, reserved, enabled, weight) VALUES (%s, false, true, 1)",
                    (roll,),
                )
        baseline = _run_simulation(conn, n=500, seed=0.42)
        _assert_distribution(baseline, {1: 1, 2: 1, 3: 1}, n=500)

        with conn.cursor() as cur:
            cur.execute("UPDATE motivation_d100 SET weight = 5 WHERE roll = 1")

        after = _run_simulation(conn, n=500, seed=0.17)
        _assert_distribution(after, {1: 5, 2: 1, 3: 1}, n=500)
    finally:
        conn.close()


@pytest.mark.skipif(os.environ.get("SKIP_DB_TESTS"), reason="SKIP_DB_TESTS set")
def test_weight_zero_mutes_immediately(db_803):
    """W2: setting weight to 0 immediately mutes the slot in the same session."""
    conn = _connect_to_db(db_803)
    try:
        _load_minimal_d100_schema(conn)
        _apply_migration_089(conn)
        with conn.cursor() as cur:
            for roll in (1, 2, 3, 4, 5):
                cur.execute(
                    "INSERT INTO motivation_d100 (roll, task_name, enabled, weight) VALUES (%s, %s, true, 1)",
                    (roll, f"Task {roll}"),
                )
        # Warm-up: confirm roll 1 is reachable before muting.
        warmup = _run_simulation(conn, n=100, seed=0.42)
        assert warmup.get(1, 0) > 0, "roll 1 was not reachable before muting"

        with conn.cursor() as cur:
            cur.execute("UPDATE motivation_d100 SET weight = 0 WHERE roll = 1")

        after = _run_simulation(conn, n=500, seed=0.42)
        assert after.get(1, 0) == 0, "roll 1 was drawn after being muted to weight 0"
    finally:
        conn.close()
