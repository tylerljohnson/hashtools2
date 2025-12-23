#!/usr/bin/env bash
#
# truncate_hashes_table.bash
# Safely truncates the 'hashes' table in the configured PostgreSQL database.

set -euo pipefail

DB_HOST="${PGHOST:-cooper}"
DB_PORT="${PGPORT:-54321}"
DB_USER="${PGUSER:-tyler}"
DB_DATABASE="${PGDATABASE:-tyler}"

psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_DATABASE" -c "TRUNCATE TABLE hashes RESTART IDENTITY;"
