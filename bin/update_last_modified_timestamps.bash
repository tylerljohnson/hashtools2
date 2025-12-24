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

# 1. OS Detection
IS_MAC=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MAC=true

# Database configuration
DB_HOST=${PGHOST:-cooper}
DB_PORT=${PGPORT:-5432}
DB_USER=${PGUSER:-tyler}
DB_NAME=${PGDATABASE:-tyler}

FORCE=false
DEBUG=false
INPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [--force] <tsv_file>"
            exit 1
            ;;
        *)
            INPUT_FILE="$1"
            shift
            ;;
    esac
done

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 [--force] [--debug] <tsv_file>"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: File $INPUT_FILE not found."
    exit 1
fi

# 2. Setup Cleanup
SQL_FILE=$(mktemp)
trap 'rm -f "$SQL_FILE"' EXIT

# 3. Pre-flight DB Check
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -q; then
    echo "Error: Database at $DB_HOST:$DB_PORT is not reachable."
    exit 1
fi

# 4. Processing
echo "BEGIN;" > "$SQL_FILE"

count_ok=0
count_skip=0
line_num=0

if [ "$DEBUG" = true ]; then
    echo "[DEBUG] Starting processing of: $INPUT_FILE"
fi

# Use a standard while read loop. 
# We use -r to prevent backslash escapes and IFS to define the delimiter.
while IFS=$'\t' read -r vault_id primary_last_modified vault_full_path || [[ -n "$vault_id" ]]; do
    ((line_num++))
    
    if [ "$DEBUG" = true ]; then
        echo "[DEBUG Line $line_num] Processing started..."
        echo "[DEBUG Line $line_num] Raw vault_id: [$vault_id]"
        echo "[DEBUG Line $line_num] Raw primary_last_modified: [$primary_last_modified]"
        echo "[DEBUG Line $line_num] Raw vault_full_path: [$vault_full_path]"
    fi

    # Clean inputs (handle CRLF and extra whitespace)
    # Using printf for cleaner cleaning
    vault_id=$(printf '%s' "$vault_id" | tr -d '\r' | xargs)
    primary_last_modified=$(printf '%s' "$primary_last_modified" | tr -d '\r' | xargs)
    vault_full_path=$(printf '%s' "$vault_full_path" | tr -d '\r' | xargs)

    if [ "$DEBUG" = true ]; then
        echo "[DEBUG Line $line_num] Cleaned: id='$vault_id', ts='$primary_last_modified', path='$vault_full_path'"
    fi

    # Skip empty lines or standard header
    if [[ -z "$vault_id" || "$vault_id" == "vault_id" ]]; then
        [ "$DEBUG" = true ] && echo "[DEBUG Line $line_num] Skipping empty or header"
        continue
    fi

echo "COMMIT;" >> "$SQL_FILE"

# 5. Database Execution
if [ "$count_ok" -gt 0 ]; then
    echo "--- SQL Script Contents ---"
    cat "$SQL_FILE"
    echo "---------------------------"

    echo "Executing database transaction for $count_ok updates..."
    if psql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --username="$DB_USER" \
        --dbname="$DB_NAME" \
        --file="$SQL_FILE" \
        --set ON_ERROR_STOP=1 \
        --quiet \
        --no-psqlrc; then
        echo "Database transaction successful."
    else
        echo "Error: Database transaction failed and was rolled back."
        exit 1
    fi
else
    echo "No valid updates were found in the file."
fi

echo "Summary: $count_ok successful, $count_skip skipped."
