#!/bin/bash
# Run after migration to verify TC-01 and TC-02 automatically
set -e
SCRIPTS_DIR="$(dirname "$0")/../scripts"
FAIL=0

echo "=== TC-02: Checking for residual hardcoded connection vars ==="
if grep -rn --include='*.sh' 'DB_HOST=' "$SCRIPTS_DIR" | grep -v '^#'; then
  echo "FAIL: DB_HOST= still found"; FAIL=1
fi
if grep -rn --include='*.py' 'host="localhost"' "$SCRIPTS_DIR" | grep -v '^#'; then
  echo "FAIL: host=\"localhost\" still found in Python"; FAIL=1
fi
if grep -rn --include='*.py' 'user="nova"' "$SCRIPTS_DIR" | grep -v '^#'; then
  echo "FAIL: user=\"nova\" still found in Python"; FAIL=1
fi

echo "=== TC-01: Checking loader is sourced/imported ==="
for f in "$SCRIPTS_DIR"/*.sh; do
  if grep -q 'psql ' "$f" && ! grep -q 'load_pg_env' "$f"; then
    echo "FAIL: $f uses psql but doesn't call load_pg_env"; FAIL=1
  fi
done
for f in "$SCRIPTS_DIR"/*.py; do
  if grep -q 'psycopg2' "$f" && ! grep -q 'load_pg_env' "$f"; then
    echo "FAIL: $f uses psycopg2 but doesn't call load_pg_env"; FAIL=1
  fi
done

[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $FAIL
