#!/usr/bin/env bash
#
# test-shared-memory.sh — disposable-instance test harness for setup-shared-memory.sh
#
# Covers the four mandated cases:
#   TEST 1  fresh setup (+ set FDW mapping pw + reconcile + --copy-from w/ verify)
#   TEST 2  re-run is a no-op (idempotent, no data loss, no errors)
#   TEST 3  the #675 case: ADD COLUMN + ALTER TYPE on a shared table, then reconcile,
#           proving the drift is invisible before reconcile and visible after
#   TEST 4  --dry-run executes nothing (prints SQL, creates no objects)
#
# Uses throwaway databases prefixed smt_ (shared-memory-test). Safe to re-run; it
# drops and recreates its own fixtures. Requires: a cluster where the admin role can
# CREATE DATABASE and a dedicated FDW reader role (default bootstrap_reader) exists
# with a password this harness can copy from an existing mapping (see SET_PW_FROM).
#
# This harness is NOT run by any installer. It documents how the script was validated.
#
set -uo pipefail

SCRIPT="$(dirname "$0")/setup-shared-memory.sh"
ADMIN="${ADMIN_ROLE:-$(id -un)}"
PGHOST="${PGHOST:-localhost}"; PGPORT="${PGPORT:-5432}"
READER="${FDW_READER_ROLE:-bootstrap_reader}"
# How this harness sources the reader password to set on test mappings: it reads it
# from an EXISTING user mapping on another server. Override SET_PW_FROM to a
# "<db>:<server>:<localrole>" triple the admin can read. Default matches the NOVA host.
SET_PW_FROM="${SET_PW_FROM:-graybeard_memory:nova_memory_server:graybeard}"

q(){ psql -U "$ADMIN" -h "$PGHOST" -p "$PGPORT" -d "$1" -tAqXc "$2" 2>&1; }
PASS=0; FAIL=0
chk(){ if eval "$2"; then echo "  PASS: $1"; PASS=$((PASS+1)); else echo "  FAIL: $1"; FAIL=$((FAIL+1)); fi; }

# Copy the reader password from an existing mapping onto every mapping of the test
# server in $1. (Credential-owner step; value is never printed.)
set_mapping_pw(){
  local db="$1" srcdb srcsrv srcrole RPW usr
  IFS=: read -r srcdb srcsrv srcrole <<< "$SET_PW_FROM"
  RPW=$(q "$srcdb" "SELECT split_part(o,'=',2) FROM pg_user_mapping m JOIN pg_foreign_server s ON s.oid=m.umserver, unnest(m.umoptions) o WHERE s.srvname='$srcsrv' AND m.umuser::regrole::text='$srcrole' AND o LIKE 'password=%' LIMIT 1;")
  for usr in $(q "$db" "SELECT usename FROM pg_user_mappings WHERE srvname='shared_memory_server';"); do
    psql -U "$ADMIN" -h "$PGHOST" -p "$PGPORT" -d "$db" -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<SQL || true
DO \$\$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_user_mapping m JOIN pg_foreign_server s ON s.oid=m.umserver, unnest(COALESCE(m.umoptions,'{}')) o WHERE s.srvname='shared_memory_server' AND m.umuser=('"'||'$usr'||'"')::regrole AND o LIKE 'password=%') THEN
    EXECUTE format('ALTER USER MAPPING FOR %I SERVER shared_memory_server OPTIONS (SET password %L)','$usr','$RPW');
  ELSE
    EXECUTE format('ALTER USER MAPPING FOR %I SERVER shared_memory_server OPTIONS (ADD password %L)','$usr','$RPW');
  END IF; END \$\$;
SQL
  done
}

clean(){
  q postgres "DROP DATABASE IF EXISTS smt_shared;" >/dev/null
  for d in smt_c1 smt_c2 smt_c3; do
    q "$d" "DROP VIEW IF EXISTS public.agent_bootstrap_context CASCADE; DROP FOREIGN TABLE IF EXISTS public.shared_agent_bootstrap_context, public.ai_models, public.ai_model_param_issues CASCADE; DROP TABLE IF EXISTS public.agent_bootstrap_context_local CASCADE; DROP SERVER IF EXISTS shared_memory_server CASCADE;" >/dev/null 2>&1 || true
  done
}

echo "NOTE: create smt_src (with canonical schema + sample rows) and smt_c1/smt_c2 before running,"
echo "      plus .pgpass entries for the admin role on each. See repo README for the fixture SQL."
clean; echo cleaned

echo; echo "###### TEST 1: FRESH SETUP ######"
"$SCRIPT" setup --target-db smt_shared --source-db smt_src --consumer-dbs "smt_c1 smt_c2" --consumer-roles "$ADMIN $ADMIN" --admin-role "$ADMIN" >/tmp/t1.log 2>&1 || true
set_mapping_pw smt_c1; set_mapping_pw smt_c2
"$SCRIPT" reconcile --target-db smt_shared --consumer-dbs "smt_c1 smt_c2" --admin-role "$ADMIN" >/tmp/t1r.log 2>&1 || true
"$SCRIPT" setup --target-db smt_shared --source-db smt_src --consumer-dbs "smt_c1 smt_c2" --consumer-roles "$ADMIN $ADMIN" --copy-from smt_src --admin-role "$ADMIN" >/tmp/t1c.log 2>&1 || true
chk "T1 reconcile complete"        "grep -q 'reconcile complete' /tmp/t1r.log"
chk "T1 copy verification passed"  "grep -q 'copy verification passed' /tmp/t1c.log"
chk "T1 c1 UNIVERSAL=2"            "[ \$(q smt_c1 \"SELECT count(*) FROM agent_bootstrap_context WHERE context_type='UNIVERSAL'\") = 2 ]"
chk "T1 no AGENT rows in shared"   "[ \$(q smt_shared \"SELECT count(*) FROM agent_bootstrap_context WHERE context_type='AGENT'\") = 0 ]"

echo; echo "###### TEST 2: RE-RUN NO-OP ######"
B=$(q smt_shared "SELECT count(*) FROM agent_bootstrap_context")
"$SCRIPT" setup --target-db smt_shared --source-db smt_src --consumer-dbs "smt_c1 smt_c2" --consumer-roles "$ADMIN $ADMIN" --admin-role "$ADMIN" >/tmp/t2.log 2>&1 || true
A=$(q smt_shared "SELECT count(*) FROM agent_bootstrap_context")
chk "T2 no real ERROR"             "! grep -E 'ERROR' /tmp/t2.log | grep -qv skipping"
chk "T2 rowcount stable ($B==$A)"  "[ '$B' = '$A' ] && [ '$A' -gt 0 ]"

echo; echo "###### TEST 3: #675 ADD COLUMN + RETYPE + reconcile ######"
psql -U "$ADMIN" -h "$PGHOST" -p "$PGPORT" -d smt_shared -v ON_ERROR_STOP=1 >/dev/null 2>&1 <<'SQL'
ALTER TABLE agent_bootstrap_context ADD COLUMN IF NOT EXISTS priority integer DEFAULT 0;
ALTER TABLE ai_models ALTER COLUMN cost_tier TYPE varchar(40);
SQL
PRE=$(q smt_c1 "SELECT priority FROM shared_agent_bootstrap_context LIMIT 1" | head -1)
chk "T3 drift invisible pre-reconcile" "echo \"$PRE\" | grep -qiE 'does not exist'"
"$SCRIPT" reconcile --target-db smt_shared --consumer-dbs "smt_c1 smt_c2" --admin-role "$ADMIN" >/tmp/t3.log 2>&1 || true
POST=$(q smt_c1 "SELECT priority FROM shared_agent_bootstrap_context LIMIT 1" | head -1)
chk "T3 reconcile complete"         "grep -q 'reconcile complete' /tmp/t3.log"
chk "T3 new col visible post"       "echo \"$POST\" | grep -qE '^[0-9]+$'"
chk "T3 retyped col reads"          "q smt_c1 'SELECT cost_tier FROM ai_models LIMIT 1' >/dev/null 2>&1"

echo; echo "###### TEST 4: --dry-run ######"
q postgres "DROP DATABASE IF EXISTS smt_c3;" >/dev/null; q postgres "CREATE DATABASE smt_c3 OWNER $ADMIN;" >/dev/null
"$SCRIPT" setup --target-db smt_shared --source-db smt_src --consumer-dbs "smt_c3" --consumer-roles "$ADMIN" --admin-role "$ADMIN" --dry-run >/tmp/t4.log 2>&1 || true
chk "T4 printed planned SQL"        "[ \$(grep -cE 'CREATE|IMPORT|GRANT|ALTER' /tmp/t4.log) -gt 0 ]"
chk "T4 no tables created in c3"    "[ \$(q smt_c3 \"SELECT count(*) FROM pg_tables WHERE schemaname='public'\") = 0 ]"
chk "T4 no fdw server in c3"        "[ \$(q smt_c3 'SELECT count(*) FROM pg_foreign_server') = 0 ]"

echo; echo "============ TOTAL: PASS=$PASS FAIL=$FAIL ============"
[ "$FAIL" -eq 0 ]
