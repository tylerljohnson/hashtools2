#!/bin/bash

# ==============================================================================
# update_last_modified_timestamps.bash
#
# Purpose:
#   1. Updates filesystem last modified timestamp for {vault_full_path}.
#   2. Updates PostgreSQL 'hashes' table for {vault_id}.
#
# Compatibility: Linux (GNU) and macOS (BSD)
# Input: TSV file (vault_id, primary_last_modified, vault_full_path)
# ==============================================================================

set -euo pipefail

# 1. OS Detection (for touch command compatibility)
IS_MAC=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MAC=true

# Database configuration (defaults from README)
DB_HOST=${PGHOST:-cooper}
DB_PORT=${PGPORT:-5432}
DB_USER=${PGUSER:-tyler}
DB_NAME=${PGDATABASE:-tyler}

# 2. Input Validation
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <tsv_file>"
    exit 1
fi

INPUT_FILE="$1"
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File $INPUT_FILE not found."
    exit 1
fi

# 3. Setup Cleanup Trap
SQL_FILE=$(mktemp)
cleanup() {
    rm -f "$SQL_FILE"
}
trap cleanup EXIT

# 4. Pre-flight DB Check
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -q; then
    echo "Error: Database at $DB_HOST:$DB_PORT is not reachable."
    exit 1
fi

# 5. Processing
echo "BEGIN;" > "$SQL_FILE"

count_ok=0
count_skip=0
line_num=0

echo "Processing TSV and updating filesystem..."

# IFS=$'\t' ensures we split columns by tabs, preserving spaces in timestamps/paths
while IFS=$'\t' read -r vault_id primary_last_modified vault_full_path || [ -n "$vault_id" ]; do
    ((line_num++))

    # Skip header
    [[ "$vault_id" == "vault_id" ]] && continue

    # Clean inputs (handle CRLF and extra whitespace)
    vault_id=$(echo "$vault_id" | tr -d '\r' | xargs)
    primary_last_modified=$(echo "$primary_last_modified" | tr -d '\r' | xargs)
    vault_full_path=$(echo "$vault_full_path" | tr -d '\r' | xargs)

    # Skip empty lines
    [[ -z "$vault_id" ]] && continue

    if [ -e "$vault_full_path" ]; then
        TOUCH_SUCCESS=false

        if [ "$IS_MAC" = true ]; then
            # macOS (BSD) touch requires [[CC]YY]MMDDhhmm[.ss]
            # Convert "YYYY-MM-DD HH:MM:SS" -> "YYYYMMDDHHMM.SS"
            MAC_DATE=$(echo "$primary_last_modified" | sed 's/[- : ]//g' | sed 's/\(..\)$/.\1/')
            if touch -mt "$MAC_DATE" "$vault_full_path" 2>/dev/null; then
                TOUCH_SUCCESS=true
            fi
        else
            # Linux (GNU) touch handles "YYYY-MM-DD HH:MM:SS" directly
            if touch -c -d "$primary_last_modified" "$vault_full_path" 2>/dev/null; then
                TOUCH_SUCCESS=true
            fi
        fi

        if [ "$TOUCH_SUCCESS" = true ]; then
            # Queue SQL Update (Postgres cast to TIMESTAMP)
            echo "UPDATE hashes SET last_modified = '$primary_last_modified'::TIMESTAMP WHERE id = $vault_id;" >> "$SQL_FILE"
            ((count_ok++))
        else
            echo "[Line $line_num] FATAL ERROR: Failed to update timestamp for: $vault_full_path"
            echo "Timestamp provided: '$primary_last_modified'"
            exit 1 # Fail fast to prevent database/filesystem desync
        fi
    else
        echo "[Line $line_num] SKIP: File not found on disk: $vault_full_path"
        ((count_skip++))
    fi

done < "$INPUT_FILE"

echo "COMMIT;" >> "$SQL_FILE"

# 6. Database Execution
if [ "$count_ok" -gt 0 ]; then
    echo "Executing database transaction for $count_ok updates..."
    # ON_ERROR_STOP=1 ensures the transaction rolls back if any SQL statement fails
    if psql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --username="$DB_USER" \
        --dbname="$DB_NAME" \
        --file="$SQL_FILE" \
        --set ON_ERROR_STOP=1 \
        --quiet \
        --no-psqlrc; then
        echo "Successfully updated $count_ok records in database."
    else
        echo "Error: Database transaction failed and was rolled back."
        exit 1
    fi
else
    echo "No files were found to update."
fi

echo "Finished. (Skipped $count_skip missing files)"