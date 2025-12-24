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
asdfasdf
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

echo "Reading from: $INPUT_FILE"

# IFS=$'\t' ensures we split columns by tabs, preserving spaces in timestamps/paths
# || [ -n "$vault_id" ] ensures the last line is processed even if it lacks a trailing newline
while IFS=$'\t' read -r vault_id primary_last_modified vault_full_path || [ -n "$vault_id" ]; do
    ((line_num++))

    if [ "$DEBUG" = true ]; then
        echo "[DEBUG Line $line_num] Raw input: vault_id='$vault_id', ts='$primary_last_modified', path='$vault_full_path'"
    fi

    # Clean inputs (handle CRLF and extra whitespace)
    vault_id=$(echo "$vault_id" | tr -d '\r' | xargs)
    primary_last_modified=$(echo "$primary_last_modified" | tr -d '\r' | xargs)
    vault_full_path=$(echo "$vault_full_path" | tr -d '\r' | xargs)

    if [ "$DEBUG" = true ]; then
        echo "[DEBUG Line $line_num] Cleaned: vault_id='$vault_id', ts='$primary_last_modified', path='$vault_full_path'"
    fi

    # Skip empty lines
    if [[ -z "$vault_id" ]]; then
        [ "$DEBUG" = true ] && echo "[DEBUG Line $line_num] Skipping: Empty vault_id"
        continue
    fi
    # Skip the header row if it's the standard header
    if [[ "$vault_id" == "vault_id" ]]; then
        [ "$DEBUG" = true ] && echo "[DEBUG Line $line_num] Skipping: Header detected"
        continue
    fi
    # If vault_id is not a number, skip it
    if [[ ! "$vault_id" =~ ^[0-9]+$ ]]; then
        [ "$DEBUG" = true ] && echo "[DEBUG Line $line_num] Skipping: vault_id '$vault_id' is not numeric"
        continue
    fi

    FILE_EXISTS=false
    if [ -e "$vault_full_path" ]; then FILE_EXISTS=true; fi

    if [ "$DEBUG" = true ]; then
        echo "[DEBUG Line $line_num] File exists: $FILE_EXISTS, Force: $FORCE"
    fi

    if [ "$FORCE" = true ] || [ "$FILE_EXISTS" = true ]; then
        TOUCH_SUCCESS=false

        if [ "$FILE_EXISTS" = true ]; then
            if [ "$IS_MAC" = true ]; then
                # macOS (BSD) touch requires [[CC]YY]MMDDhhmm[.ss]
                MAC_DATE=$(echo "$primary_last_modified" | sed 's/[- : ]//g' | sed 's/\(..\)$/.\1/')
                [ "$DEBUG" = true ] && echo "[DEBUG Line $line_num] macOS touch date: $MAC_DATE"
                if touch -mt "$MAC_DATE" "$vault_full_path" 2>/dev/null; then
                    TOUCH_SUCCESS=true
                fi
            else
                # Linux (GNU) touch handles "YYYY-MM-DD HH:MM:SS" directly
                [ "$DEBUG" = true ] && echo "[DEBUG Line $line_num] Linux touch date: $primary_last_modified"
                if touch -c -d "$primary_last_modified" "$vault_full_path" 2>/dev/null; then
                    TOUCH_SUCCESS=true
                fi
            fi
        fi

        if [ "$DEBUG" = true ]; then
            echo "[DEBUG Line $line_num] Touch success: $TOUCH_SUCCESS"
        fi

        # If touch worked, OR if we are forcing and the file doesn't exist, queue the DB update
        if [ "$TOUCH_SUCCESS" = true ] || { [ "$FORCE" = true ] && [ "$FILE_EXISTS" = false ]; }; then
            echo "UPDATE hashes SET last_modified = '$primary_last_modified'::TIMESTAMP WHERE id = $vault_id;" >> "$SQL_FILE"
            ((count_ok++))
            if [ -e "$vault_full_path" ]; then
                echo "[Line $line_num] Updated FS & DB: $vault_full_path"
            else
                echo "[Line $line_num] Updated DB (FS missing, --force): $vault_full_path"
            fi
        else
            echo "[Line $line_num] FATAL ERROR: touch failed for: $vault_full_path"
            exit 1
        fi
    else
        echo "[Line $line_num] SKIP: File not found: $vault_full_path"
        ((count_skip++))
    fi
done < "$INPUT_FILE"

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