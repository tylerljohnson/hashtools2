#!/usr/bin/env bash
#
# truncate_hashes.bash
# Safely truncates the 'hashes' table in the configured PostgreSQL database.
# Asks for confirmation before proceeding.
#
# Env: PGHOST, PGUSER, PGDATABASE (defaults to cooper, tyler, tyler)

set -euo pipefail

PGHOST="${PGHOST:-cooper}"
PGUSER="${PGUSER:-tyler}"
PGDATABASE="${PGDATABASE:-tyler}"

psql -h "$PGHOST" -U "$PGUSER" -d "$PGDATABASE" -c "TRUNCATE TABLE hashes RESTART IDENTITY;"

