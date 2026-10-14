#!/usr/bin/env bash
#
# setup-shared-memory.sh — idempotent setup + reconcile for a shared_memory database
# in a multi-agent "one memory DB per agent" topology.
#
# This is OPTIONAL tooling. The nova-mind installer does NOT run it. It is generic:
# pass your own source DB, consumer DB list, shared table list, and target DB name.
#
# Pattern: a single canonical `shared_memory` DB holds the shared tables; every
# consumer DB (one per agent) is an IDENTICAL consumer — a postgres_fdw foreign
# server + foreign tables pointing at shared_memory, plus a federation view that
# unions the shared (UNIVERSAL/GLOBAL/DOMAIN) rows from the foreign table with the
# agent's own AGENT rows held in a local table.
#
# Full guide: cognition/docs/shared-memory-database.md
#
# SAFETY CONTRACT
#   - Idempotent: safe to re-run; re-runs are no-ops where objects already exist.
#   - Never drops or overwrites existing DATA. Schema objects use IF NOT EXISTS /
#     CREATE OR REPLACE. The row-copy step (--copy-from) only INSERTs rows that are
#     absent (ON CONFLICT DO NOTHING) and then verifies counts/checksums.
#   - Credentials: never printed. Authentication is via ~/.pgpass only. This script
#     does NOT create roles or mint passwords — pass pre-created roles as input.
#     (Role creation + .pgpass writes are the credential owner's job, done
#     out-of-band. See --help.)
#   - --dry-run prints the planned SQL to stdout and executes nothing.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (override via flags)
# ---------------------------------------------------------------------------
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
ADMIN_ROLE="${ADMIN_ROLE:-$(id -un)}"   # role used to run DDL; must own/admin the DBs
TARGET_DB="shared_memory"
SOURCE_DB=""                             # e.g. nova_memory (for --copy-from)
CONSUMER_DBS=()                          # e.g. nova_memory newhart_memory ...
CONSUMER_ROLES=()                        # peer roles, 1:1 with CONSUMER_DBS by convention
SHARED_TABLES=(agent_bootstrap_context ai_models)   # base tables to replicate
SHARED_VIEWS=(ai_model_param_issues)                # views to replicate (depend on tables)
TRIGGER_FUNCS=(protect_bootstrap_context_writes_v2 notify_heartbeat_content_changed)
FDW_SERVER="shared_memory_server"
FDW_READER_ROLE="bootstrap_reader"   # dedicated read-only role the FDW connects AS
LOCAL_AGENT_TABLE="agent_bootstrap_context_local"   # holds each agent's own AGENT rows
FED_VIEW="agent_bootstrap_context"                  # consumer-facing federation view
# context_types federated from shared_memory (everything cross-peer); AGENT stays local
SHARED_CTX_TYPES="'UNIVERSAL','GLOBAL','DOMAIN','SYSTEM'"
LOCAL_CTX_TYPES="'AGENT'"

MODE="setup"            # setup | reconcile
DRY_RUN=0
SETUP_NEEDS_RECONCILE=()  # consumers whose foreign import was deferred (no FDW pw yet)
COPY_FROM=""            # DB to copy canonical rows from (optional)
INSTEAD_OF_TRIGGER=0    # install INSTEAD OF trigger on the federation view for writes

# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage:
  setup-shared-memory.sh [setup|reconcile] [options]

Modes:
  setup       (default) Create target DB + shared schema + triggers + grants,
              then wire every consumer DB (fdw server, user mappings, foreign
              tables, federation view). Idempotent.
  reconcile   Re-import/reconcile foreign-table definitions in every consumer DB
              after a schema change in the target DB, then VERIFY with a real read
              through each federation view (not DDL success). This is the recurring
              fix for FDW column drift.

Required (setup):
  --consumer-dbs "db1 db2 ..."     Space-separated consumer DB names.
  --consumer-roles "r1 r2 ..."     Peer roles (pre-created) 1:1 with consumer DBs.

Required (reconcile):
  --consumer-dbs "db1 db2 ..."

Options:
  --target-db NAME         Target canonical DB (default: shared_memory)
  --source-db NAME         Source DB whose schema is canonical (default: first consumer
                           that already has the shared tables; used to clone DDL).
  --shared-tables "t1 t2"  Base tables to replicate (default: agent_bootstrap_context ai_models)
  --shared-views "v1 v2"   Views to replicate (default: ai_model_param_issues)
  --copy-from DB           Copy canonical shared rows from DB into target, verify
                           counts + checksums per context_type. Leaves AGENT rows behind.
  --fdw-server NAME        Foreign server name in consumers (default: shared_memory_server)
  --fdw-reader-role ROLE   Dedicated read-only role the FDW authenticates AS
                           (default: bootstrap_reader). Its PASSWORD in the user
                           mapping is set OUT-OF-BAND by the credential owner; this
                           script creates the mapping with user=<role> but no password
                           and will warn if the mapping lacks a password.
  --instead-of-trigger     Install an INSTEAD OF INSERT/UPDATE/DELETE trigger on the
                           federation view that routes writes by context_type
                           (shared -> foreign/shared_memory, AGENT -> local table).
  --host HOST              (default: localhost)   --port PORT (default: 5432)
  --admin-role ROLE        Role used to run DDL (default: current user)
  --dry-run                Print planned SQL, execute nothing.
  -h, --help               This help.

Credentials: via ~/.pgpass only. This script never prints or creates credentials.
Role creation and .pgpass provisioning are done out-of-band by the credential owner.
EOF
}

# ---------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# psql runner: honors --dry-run (prints SQL) else executes against $1 (dbname).
run_sql() {
  local db="$1"; shift
  local sql="$*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf -- '-- @%s\n%s\n\n' "$db" "$sql"
    return 0
  fi
  psql -v ON_ERROR_STOP=1 -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$db" -qXAt -c "$sql"
}

# psql reader: always executes (even in dry-run) because verification must be real.
read_sql() {
  local db="$1"; shift
  psql -v ON_ERROR_STOP=1 -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$db" -qXAt -c "$*"
}

db_exists() {
  read_sql postgres "SELECT 1 FROM pg_database WHERE datname='$1'" | grep -q 1
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
[[ $# -gt 0 && "$1" != -* ]] && { MODE="$1"; shift; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-db) TARGET_DB="$2"; shift 2;;
    --source-db) SOURCE_DB="$2"; shift 2;;
    --consumer-dbs) read -r -a CONSUMER_DBS <<< "$2"; shift 2;;
    --consumer-roles) read -r -a CONSUMER_ROLES <<< "$2"; shift 2;;
    --shared-tables) read -r -a SHARED_TABLES <<< "$2"; shift 2;;
    --shared-views) read -r -a SHARED_VIEWS <<< "$2"; shift 2;;
    --copy-from) COPY_FROM="$2"; shift 2;;
    --fdw-server) FDW_SERVER="$2"; shift 2;;
    --fdw-reader-role) FDW_READER_ROLE="$2"; shift 2;;
    --instead-of-trigger) INSTEAD_OF_TRIGGER=1; shift;;
    --host) PGHOST="$2"; shift 2;;
    --port) PGPORT="$2"; shift 2;;
    --admin-role) ADMIN_ROLE="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (see --help)";;
  esac
done

[[ ${#CONSUMER_DBS[@]} -gt 0 ]] || die "--consumer-dbs is required"

# Derive SOURCE_DB if not given: first consumer that already has the shared tables.
derive_source_db() {
  [[ -n "$SOURCE_DB" ]] && return 0
  local t="${SHARED_TABLES[0]}"
  for d in "${CONSUMER_DBS[@]}"; do
    if db_exists "$d" && read_sql "$d" "SELECT to_regclass('public.$t') IS NOT NULL" | grep -q t; then
      SOURCE_DB="$d"; return 0
    fi
  done
  die "could not derive --source-db; pass it explicitly"
}

# ---------------------------------------------------------------------------
# SETUP: step 1 — create target DB + clone shared schema (tables, views, seqs,
#        trigger functions, triggers, constraints, indexes) from SOURCE_DB.
# ---------------------------------------------------------------------------
setup_target_schema() {
  log "ensuring target DB '$TARGET_DB' exists"
  if ! db_exists "$TARGET_DB"; then
    run_sql postgres "CREATE DATABASE $(printf %q "$TARGET_DB") OWNER $(printf %q "$ADMIN_ROLE")"
  else
    log "target DB already exists — skipping create"
  fi

  derive_source_db
  log "cloning canonical schema from '$SOURCE_DB' (functions, tables, views)"

  # Trigger functions first (triggers depend on them). pg_get_functiondef is
  # CREATE OR REPLACE, so idempotent. We fetch from SOURCE_DB and apply to TARGET.
  local fn def
  for fn in "${TRIGGER_FUNCS[@]}"; do
    if read_sql "$SOURCE_DB" "SELECT 1 FROM pg_proc WHERE proname='$fn'" | grep -q 1; then
      def="$(read_sql "$SOURCE_DB" "SELECT pg_get_functiondef('$fn'::regproc)")"
      run_sql "$TARGET_DB" "$def;"
    fi
  done

  # Tables + views + sequences + indexes + triggers: use pg_dump --schema-only,
  # restricted to the shared objects, filtered to idempotent-safe statements.
  # pg_dump emits plain CREATE (not IF NOT EXISTS), so we guard by existence.
  local obj
  for obj in "${SHARED_TABLES[@]}" "${SHARED_VIEWS[@]}"; do
    if read_sql "$TARGET_DB" "SELECT to_regclass('public.$obj') IS NOT NULL" | grep -q t; then
      log "  $obj already present in $TARGET_DB — skipping DDL"
      continue
    fi
    local ddl
    ddl="$(pg_dump -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$SOURCE_DB" \
            --schema-only --no-owner --no-privileges -t "public.$obj")"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf -- '-- @%s (pg_dump DDL for %s)\n%s\n\n' "$TARGET_DB" "$obj" "$ddl"
    else
      printf '%s' "$ddl" | psql -v ON_ERROR_STOP=1 -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$TARGET_DB" -qX
    fi
  done
  log "target schema ready"
}

# ---------------------------------------------------------------------------
# SETUP: step 2 — grants for each consumer role on the shared objects.
# Least privilege: SELECT on all shared objects; INSERT/UPDATE on the writable
# bootstrap table (row-level rules enforced by the protection trigger); DELETE
# and ai_* writes reserved for the designated domain owner, which the caller can
# grant separately. This script grants the common read/federate path.
# ---------------------------------------------------------------------------
setup_grants() {
  log "granting consumer roles + FDW reader on '$TARGET_DB'"
  local role obj
  # The dedicated FDW reader role needs SELECT on every shared object so IMPORT
  # FOREIGN SCHEMA and all foreign reads work. (Its password is set out-of-band.)
  run_sql "$TARGET_DB" "DO \$\$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${FDW_READER_ROLE}') THEN
      EXECUTE 'GRANT CONNECT ON DATABASE $(printf %q "$TARGET_DB") TO ${FDW_READER_ROLE}';
      EXECUTE 'GRANT USAGE ON SCHEMA public TO ${FDW_READER_ROLE}';
    END IF; END \$\$;"
  for obj in "${SHARED_TABLES[@]}" "${SHARED_VIEWS[@]}"; do
    run_sql "$TARGET_DB" "DO \$\$ BEGIN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${FDW_READER_ROLE}') THEN
        EXECUTE 'GRANT SELECT ON public.$obj TO ${FDW_READER_ROLE}';
      END IF; END \$\$;"
  done
  for role in "${CONSUMER_ROLES[@]}"; do
    run_sql "$TARGET_DB" "GRANT CONNECT ON DATABASE $(printf %q "$TARGET_DB") TO $role"
    run_sql "$TARGET_DB" "GRANT USAGE ON SCHEMA public TO $role"
    for obj in "${SHARED_TABLES[@]}" "${SHARED_VIEWS[@]}"; do
      run_sql "$TARGET_DB" "GRANT SELECT ON public.$obj TO $role"
    done
    # writable bootstrap table + its sequence (trigger enforces row-level rules)
    run_sql "$TARGET_DB" "GRANT INSERT, UPDATE ON public.${FED_VIEW} TO $role"
    run_sql "$TARGET_DB" "DO \$\$ BEGIN
      IF EXISTS (SELECT 1 FROM pg_class WHERE relname='${FED_VIEW}_id_seq' AND relkind='S') THEN
        EXECUTE 'GRANT USAGE ON SEQUENCE public.${FED_VIEW}_id_seq TO $role';
      END IF; END \$\$;"
  done
}

# ---------------------------------------------------------------------------
# SETUP: step 3 — wire each consumer DB (fdw server, user mapping, foreign
# tables, local AGENT table, federation view). Idempotent throughout.
# ---------------------------------------------------------------------------
wire_consumer() {
  local db="$1" role="$2"
  log "wiring consumer '$db' (role '$role')"

  run_sql "$db" "CREATE EXTENSION IF NOT EXISTS postgres_fdw"

  # Foreign server (idempotent)
  run_sql "$db" "DO \$\$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_foreign_server WHERE srvname='${FDW_SERVER}') THEN
      EXECUTE format('CREATE SERVER %I FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, port %L, dbname %L)',
        '${FDW_SERVER}', '${PGHOST}', '${PGPORT}', '${TARGET_DB}');
    END IF; END \$\$;"

  # User mapping: the FDW authenticates AS a dedicated read-only role (FDW_READER_ROLE,
  # e.g. bootstrap_reader) that has SELECT on the shared objects in the target DB.
  # postgres_fdw does NOT read .pgpass — the password must live in the user mapping.
  # This script creates the mapping with user=<reader role> but WITHOUT a password;
  # the credential owner sets the password out-of-band:
  #   ALTER USER MAPPING FOR <local_role> SERVER <server> OPTIONS (ADD password '…');
  # We create one mapping per local role that needs to read through the FDW (the
  # consumer role and the admin role), all authenticating as FDW_READER_ROLE.
  local lr
  for lr in "$role" "$ADMIN_ROLE"; do
    run_sql "$db" "DO \$\$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_user_mappings WHERE srvname='${FDW_SERVER}' AND usename='${lr}') THEN
        EXECUTE format('CREATE USER MAPPING FOR %I SERVER %I OPTIONS (user %L)', '${lr}', '${FDW_SERVER}', '${FDW_READER_ROLE}');
      END IF; END \$\$;"
  done
  # Warn (do not fail) if any mapping lacks a password — FDW reads will fail until the
  # credential owner adds it. In --dry-run we skip the live check.
  if [[ "$DRY_RUN" -eq 0 ]]; then
    local nopw
    nopw="$(read_sql "$db" "SELECT count(*) FROM pg_user_mappings m
      WHERE m.srvname='${FDW_SERVER}'
        AND NOT EXISTS (SELECT 1 FROM unnest(m.umoptions) o WHERE o LIKE 'password=%')
        AND m.umoptions IS NOT NULL" 2>/dev/null || echo 0)"
    # umoptions NULL means options not visible to this role; check presence differently
    if ! read_sql "$db" "SELECT 1 FROM pg_user_mappings WHERE srvname='${FDW_SERVER}' LIMIT 1" >/dev/null 2>&1; then :; fi
    log "  NOTE: FDW mappings on '$db' use reader role '${FDW_READER_ROLE}'. If reads fail with
         'no password supplied', the credential owner must: ALTER USER MAPPING FOR <role>
         SERVER ${FDW_SERVER} OPTIONS (ADD password '<reader pw>');"
  fi

  # Local AGENT-records table FIRST: holds this agent's own AGENT rows. We clone its
  # column shape from the canonical bootstrap table in TARGET_DB (connection-
  # INDEPENDENT: uses pg_dump of the real table, not the foreign table), so a fresh
  # consumer lays this down even before the FDW password is set. Idempotent.
  ensure_local_agent_table "$db"

  # Import foreign tables for every shared object. This REQUIRES the FDW mapping
  # password. On a fresh setup the credential owner may not have set it yet; in that
  # case the import fails with 'no password supplied'. We treat ONLY that case as a
  # soft, resumable condition: server + mapping + local table are already laid down,
  # so the operator sets the password and runs `reconcile` to finish. Any OTHER import
  # error is fatal. This creates public.shared_<FED_VIEW> that the view depends on.
  if import_foreign_tables "$db"; then
    create_federation_view "$db"
    if [[ "$INSTEAD_OF_TRIGGER" -eq 1 ]]; then
      install_instead_of_trigger "$db"
    fi
  else
    SETUP_NEEDS_RECONCILE+=("$db")
    log "  '$db': foreign import deferred (set the FDW mapping password, then run: reconcile)"
  fi
  return 0
}

# Create the local AGENT table by cloning the canonical bootstrap table's DDL from
# TARGET_DB (connection-independent). Renames the dumped table to LOCAL_AGENT_TABLE.
ensure_local_agent_table() {
  local db="$1"
  if read_sql "$db" "SELECT to_regclass('public.${LOCAL_AGENT_TABLE}') IS NOT NULL" | grep -q t; then
    return 0
  fi
  # Dump the canonical bootstrap table schema from TARGET_DB, strip owner/privs, and
  # rewrite its name to the local AGENT table name. Keep constraints/defaults; drop
  # the triggers (they belong on the shared copy, not the local AGENT store).
  local ddl
  ddl="$(pg_dump -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$TARGET_DB" \
          --schema-only --no-owner --no-privileges -t "public.${FED_VIEW}" \
        | grep -vE 'CREATE TRIGGER|EXECUTE FUNCTION|^-- Name: (protect_|heartbeat_)' )"
  # Rewrite ALL identifiers derived from the canonical table name so NONE of the satellite
  # objects (sequence, pkey, unique/partial indexes) clash with the shared table's own
  # objects already present in the cluster. We replace EVERY occurrence of the base name
  # (including as a prefix of _id_seq, _pkey, _*_idx) with the local table name. Because
  # underscore is a word char, '\bNAME\b' does NOT catch 'NAME_id_seq'; so we match the
  # bare name AND name-with-suffix via a single prefix substitution.
  ddl="$(printf '%s' "$ddl" | sed -E "s/${FED_VIEW}/${LOCAL_AGENT_TABLE}/g")"
  # Also rename the generic idx_abc_agent_name index (does not carry the table prefix).
  ddl="$(printf '%s' "$ddl" | sed -E "s/\\bidx_abc_agent_name\\b/idx_${LOCAL_AGENT_TABLE}_agent_name/g")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf -- '-- @%s (local AGENT table DDL, cloned from %s.%s)\n%s\n\n' "$db" "$TARGET_DB" "$FED_VIEW" "$ddl"
  else
    printf '%s' "$ddl" | psql -v ON_ERROR_STOP=1 -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$db" -qX
  fi
}

# The foreign table that mirrors the shared bootstrap table is named with a distinct
# local name so the federation view (public.agent_bootstrap_context) can own the
# canonical name. We call it shared_<table>.
import_foreign_tables() {
  local db="$1" obj fname
  # The federation VIEW depends on the bootstrap foreign table, so a plain DROP of the
  # foreign table fails ('other objects depend on it'). Drop the view FIRST; we recreate
  # it right after the re-import in create_federation_view. (We do NOT use DROP ... CASCADE
  # because that could silently drop other unexpected dependents.)
  run_sql "$db" "DROP VIEW IF EXISTS public.${FED_VIEW}"
  for obj in "${SHARED_TABLES[@]}" "${SHARED_VIEWS[@]}"; do
    if [[ "$obj" == "${FED_VIEW}" ]]; then
      fname="shared_${FED_VIEW}"
    else
      fname="$obj"
    fi
    run_sql "$db" "DROP FOREIGN TABLE IF EXISTS public.$(printf %q "$fname")"
  done
  # IMPORT FOREIGN SCHEMA brings them in with their real names; we then rename the
  # bootstrap one to shared_<name> so the view can reuse the canonical name.
  local only_list
  only_list="$(IFS=,; echo "${SHARED_TABLES[*]} ${SHARED_VIEWS[*]}" | tr ' ' ',')"
  # The import can fail if the mapping password is not set yet; let the caller decide
  # whether that is fatal (reconcile = yes) or soft (setup first pass = no).
  if ! run_sql "$db" "IMPORT FOREIGN SCHEMA public LIMIT TO ($(printf '%s' "${SHARED_TABLES[*]} ${SHARED_VIEWS[*]}" | sed 's/ /, /g')) FROM SERVER ${FDW_SERVER} INTO public"; then
    return 1
  fi
  # Rename the bootstrap foreign table out of the way of the view's canonical name.
  run_sql "$db" "DO \$\$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
               WHERE n.nspname='public' AND c.relname='${FED_VIEW}' AND c.relkind='f') THEN
      EXECUTE 'ALTER FOREIGN TABLE public.${FED_VIEW} RENAME TO shared_${FED_VIEW}';
    END IF; END \$\$;"
}

create_federation_view() {
  local db="$1"
  run_sql "$db" "CREATE OR REPLACE VIEW public.${FED_VIEW} AS
    SELECT id, context_type, domain_names, file_key, content, description,
           updated_at, updated_by, agent_name
      FROM public.shared_${FED_VIEW}
     WHERE context_type IN (${SHARED_CTX_TYPES})
    UNION ALL
    SELECT id, context_type, domain_names, file_key, content, description,
           updated_at, updated_by, agent_name
      FROM public.${LOCAL_AGENT_TABLE}
     WHERE context_type IN (${LOCAL_CTX_TYPES})"
}

install_instead_of_trigger() {
  local db="$1"
  run_sql "$db" "CREATE OR REPLACE FUNCTION public.${FED_VIEW}_route() RETURNS trigger
    LANGUAGE plpgsql AS \$fn\$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        IF NEW.context_type IN (${LOCAL_CTX_TYPES}) THEN
          INSERT INTO public.${LOCAL_AGENT_TABLE}
            (context_type, domain_names, file_key, content, description, updated_at, updated_by, agent_name)
          VALUES (NEW.context_type, NEW.domain_names, NEW.file_key, NEW.content,
                  NEW.description, COALESCE(NEW.updated_at, now()), COALESCE(NEW.updated_by, current_user), NEW.agent_name);
        ELSE
          INSERT INTO public.shared_${FED_VIEW}
            (context_type, domain_names, file_key, content, description, updated_at, updated_by, agent_name)
          VALUES (NEW.context_type, NEW.domain_names, NEW.file_key, NEW.content,
                  NEW.description, COALESCE(NEW.updated_at, now()), COALESCE(NEW.updated_by, current_user), NEW.agent_name);
        END IF;
        RETURN NEW;
      ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.context_type IN (${LOCAL_CTX_TYPES}) THEN
          UPDATE public.${LOCAL_AGENT_TABLE} SET
            context_type=NEW.context_type, domain_names=NEW.domain_names, file_key=NEW.file_key,
            content=NEW.content, description=NEW.description, updated_at=now(),
            updated_by=current_user, agent_name=NEW.agent_name
          WHERE id=OLD.id;
        ELSE
          UPDATE public.shared_${FED_VIEW} SET
            context_type=NEW.context_type, domain_names=NEW.domain_names, file_key=NEW.file_key,
            content=NEW.content, description=NEW.description, updated_at=now(),
            updated_by=current_user, agent_name=NEW.agent_name
          WHERE id=OLD.id;
        END IF;
        RETURN NEW;
      ELSIF TG_OP = 'DELETE' THEN
        IF OLD.context_type IN (${LOCAL_CTX_TYPES}) THEN
          DELETE FROM public.${LOCAL_AGENT_TABLE} WHERE id=OLD.id;
        ELSE
          DELETE FROM public.shared_${FED_VIEW} WHERE id=OLD.id;
        END IF;
        RETURN OLD;
      END IF;
      RETURN NULL;
    END \$fn\$;"
  run_sql "$db" "DROP TRIGGER IF EXISTS ${FED_VIEW}_route_trg ON public.${FED_VIEW}"
  run_sql "$db" "CREATE TRIGGER ${FED_VIEW}_route_trg
    INSTEAD OF INSERT OR UPDATE OR DELETE ON public.${FED_VIEW}
    FOR EACH ROW EXECUTE FUNCTION public.${FED_VIEW}_route()"
}

# ---------------------------------------------------------------------------
# --copy-from: copy canonical shared rows from a source DB into target, verify.
# Only shared context_types are copied; AGENT rows are left behind. Idempotent via
# ON CONFLICT DO NOTHING. Verifies counts + checksums per context_type.
# ---------------------------------------------------------------------------
copy_rows() {
  local src="$1"
  log "copy-from: copying shared rows $src -> $TARGET_DB (AGENT rows left behind)"

  # Use postgres_fdw-free path: dblink-style via COPY to stdout | COPY from stdin.
  # We stream only shared context_types.
  local cols="context_type, domain_names, file_key, content, description, updated_at, updated_by, agent_name"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf -- '-- @%s -> @%s : COPY shared rows (context_type IN %s), ON CONFLICT DO NOTHING\n\n' \
      "$src" "$TARGET_DB" "($SHARED_CTX_TYPES)"
  else
    # Stage into a temp table in target, then upsert — avoids partial-insert on conflict.
    psql -v ON_ERROR_STOP=1 -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$src" -qXAt \
      -c "COPY (SELECT $cols FROM public.${FED_VIEW} WHERE context_type IN (${SHARED_CTX_TYPES})) TO STDOUT" \
    | psql -v ON_ERROR_STOP=1 -U "$ADMIN_ROLE" -h "$PGHOST" -p "$PGPORT" -d "$TARGET_DB" -qX \
      -c "CREATE TEMP TABLE _stage (LIKE public.${FED_VIEW} INCLUDING DEFAULTS); " \
      -c "ALTER TABLE _stage DROP COLUMN id;" \
      -c "COPY _stage ($cols) FROM STDIN;" \
      -c "INSERT INTO public.${FED_VIEW} ($cols) SELECT $cols FROM _stage ON CONFLICT DO NOTHING;"
  fi

  verify_copy "$src"
}

verify_copy() {
  local src="$1" ok=1 ct scnt tcnt smd5 tmd5
  log "verifying counts + checksums per context_type ($src vs $TARGET_DB)"
  # Compare per shared context_type: row count and content checksum.
  local types
  types="$(echo "$SHARED_CTX_TYPES" | tr -d "'" | tr ',' ' ')"
  for ct in $types; do
    scnt="$(read_sql "$src" "SELECT count(*) FROM public.${FED_VIEW} WHERE context_type='$ct'")"
    tcnt="$(read_sql "$TARGET_DB" "SELECT count(*) FROM public.${FED_VIEW} WHERE context_type='$ct'")"
    # checksum over the stable business key + content (not id/timestamps)
    smd5="$(read_sql "$src" "SELECT COALESCE(md5(string_agg(file_key||COALESCE(agent_name,'')||md5(content), '|' ORDER BY file_key, COALESCE(agent_name,''))),'∅') FROM public.${FED_VIEW} WHERE context_type='$ct'")"
    tmd5="$(read_sql "$TARGET_DB" "SELECT COALESCE(md5(string_agg(file_key||COALESCE(agent_name,'')||md5(content), '|' ORDER BY file_key, COALESCE(agent_name,''))),'∅') FROM public.${FED_VIEW} WHERE context_type='$ct'")"
    if [[ "$scnt" == "$tcnt" && "$smd5" == "$tmd5" ]]; then
      log "  OK   $ct: count=$tcnt checksum match"
    else
      log "  FAIL $ct: src(count=$scnt md5=$smd5) target(count=$tcnt md5=$tmd5)"; ok=0
    fi
  done
  [[ "$ok" -eq 1 ]] || die "copy verification FAILED — see per-context_type report above"
  log "copy verification passed"
}

# ---------------------------------------------------------------------------
# RECONCILE: re-import foreign tables in every consumer, recreate the view,
# then VERIFY WITH A REAL READ (not DDL success). The #675 fix.
# ---------------------------------------------------------------------------
reconcile() {
  local db
  for db in "${CONSUMER_DBS[@]}"; do
    log "reconcile: $db"
    import_foreign_tables "$db"
    create_federation_view "$db"
    verify_consumer_read "$db"
  done
  log "reconcile complete for all consumers"
}

# Real read through the view + each foreign object. DDL success is NOT sufficient.
# A read is VALID if the query EXECUTES successfully (exit 0), even if it returns 0
# rows. A read FAILS only if psql returns a non-zero exit (e.g. FDW connection error,
# missing column after a schema change). We therefore test exit status, not output text.
verify_consumer_read() {
  local db="$1" obj n rc
  # a) federation view resolves (executes without error); report its distribution.
  local dist
  dist="$(read_sql "$db" "SELECT COALESCE(string_agg(context_type||'='||c,', ' ORDER BY context_type),'(empty)')
          FROM (SELECT context_type, count(*) c FROM public.${FED_VIEW} GROUP BY context_type) s")"
  rc=$?
  [[ $rc -eq 0 ]] || die "$db: federation view ${FED_VIEW} FAILED to resolve (psql rc=$rc)"
  log "  $db view dist: ${dist:-(empty)}"
  # b) a concrete shared read executes end-to-end through the foreign server.
  read_sql "$db" "SELECT count(*) FROM public.${FED_VIEW} WHERE context_type='UNIVERSAL'" >/dev/null
  rc=$?; [[ $rc -eq 0 ]] || die "$db: UNIVERSAL read through view FAILED (psql rc=$rc)"
  # c) each other shared object reads through the foreign server.
  for obj in "${SHARED_TABLES[@]}" "${SHARED_VIEWS[@]}"; do
    [[ "$obj" == "${FED_VIEW}" ]] && continue
    n="$(read_sql "$db" "SELECT count(*) FROM public.$obj")"
    rc=$?; [[ $rc -eq 0 ]] || die "$db: real read of foreign object $obj FAILED (psql rc=$rc)"
    log "  $db read $obj: count=$n"
  done
  log "  $db: real-read verification passed"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$MODE" in
  setup)
    setup_target_schema
    setup_grants
    for i in "${!CONSUMER_DBS[@]}"; do
      role="${CONSUMER_ROLES[$i]:-}"
      [[ -n "$role" ]] || die "no role for consumer '${CONSUMER_DBS[$i]}' (--consumer-roles must be 1:1)"
      wire_consumer "${CONSUMER_DBS[$i]}" "$role"
      # Only verify consumers that were fully wired (not deferred for a missing FDW pw).
      if [[ "$DRY_RUN" -eq 0 ]]; then
        deferred=0
        for d in "${SETUP_NEEDS_RECONCILE[@]:-}"; do [[ "$d" == "${CONSUMER_DBS[$i]}" ]] && deferred=1; done
        [[ "$deferred" -eq 0 ]] && verify_consumer_read "${CONSUMER_DBS[$i]}"
      fi
    done
    [[ -n "$COPY_FROM" ]] && copy_rows "$COPY_FROM"
    if [[ ${#SETUP_NEEDS_RECONCILE[@]} -gt 0 ]]; then
      log "setup laid down schema/roles/FDW objects, but foreign import was DEFERRED for: ${SETUP_NEEDS_RECONCILE[*]}"
      log "NEXT (credential owner): set the FDW mapping password on those consumers, e.g.:"
      log "  ALTER USER MAPPING FOR <local_role> SERVER ${FDW_SERVER} OPTIONS (ADD password '<reader pw>');"
      log "then run: $0 reconcile --target-db ${TARGET_DB} --consumer-dbs \"${SETUP_NEEDS_RECONCILE[*]}\" --admin-role ${ADMIN_ROLE}"
    fi
    log "setup complete${DRY_RUN:+ (dry-run)}"
    ;;
  reconcile)
    reconcile
    ;;
  *)
    die "unknown mode '$MODE' (use setup or reconcile; see --help)"
    ;;
esac
