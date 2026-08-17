#!/usr/bin/env bash
# Provision PostgreSQL roles referenced by database/schema.sql.
# Roles are derived dynamically from GRANT/ALTER DEFAULT PRIVILEGES targets so
# this script stays in sync with schema changes. External deployment guide owns
# the canonical role/password mapping; CI only needs login-less placeholders.
set -euo pipefail

SCHEMA_FILE="${1:-database/schema.sql}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
# Default to the standard CI password when unset or empty. Use PGPASSFILE or set
# PGPASSWORD explicitly to override.
: "${PGPASSWORD:=postgres}"
PGDATABASE="${PGDATABASE:-postgres}"
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: schema file not found: $SCHEMA_FILE" >&2
  exit 1
fi

# Extract quoted/unquoted role names appearing as GRANT/ALTER DEFAULT PRIVILEGES
# targets. The file is split on semicolons so multi-line statements are handled
# correctly, and every name after FOR ROLE or TO is captured. New grants are
# picked up automatically; a failure message reports any role that could not be
# created.
mapfile -t roles < <(
  perl -0pe 's/;\n/;\x00/g' "$SCHEMA_FILE" \
    | perl -ne '
        while (/(?:ALTER\s+DEFAULT\s+PRIVILEGES\s+FOR\s+ROLE\s+([^;\s]+)|GRANT\s+[^;]+\s+TO\s+([^;\s]+))/gi) {
          my $r = $1 // $2;
          $r =~ s/^"//; $r =~ s/"$//;
          print "$r\n" if $r =~ /^[a-zA-Z_][a-zA-Z0-9_\-]*$/;
        }
      ' \
    | sort -u
)

if [[ ${#roles[@]} -eq 0 ]]; then
  echo "ERROR: no roles found in $SCHEMA_FILE; check extraction regex" >&2
  exit 1
fi

echo "Provisioning ${#roles[@]} role(s) from $SCHEMA_FILE"
missing=()
for role in "${roles[@]}"; do
  if ! psql -v ON_ERROR_STOP=1 -tc "SELECT 1 FROM pg_roles WHERE rolname = '$role';" | grep -q 1; then
    echo "  creating role: $role"
    if psql -v ON_ERROR_STOP=1 -c "CREATE ROLE \"$role\" NOLOGIN;"; then
      echo "    created $role"
    else
      missing+=("$role")
    fi
  else
    echo "  exists: $role"
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: failed to create the following role(s): ${missing[*]}" >&2
  exit 1
fi

echo "All schema roles provisioned."
