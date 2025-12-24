#!/bin/bash

# ==============================================================================
# view_by_id.bash
#
# Purpose:
#   Look up the full_path for one or more database IDs and display them using imgcat.
#
# Usage:
#   ./bin/view_by_id.bash <id1> [id2] ... [idN]
# ==============================================================================

set -euo pipefail

# Database configuration
DB_HOST=${PGHOST:-cooper}
DB_PORT=${PGPORT:-5432}
DB_USER=${PGUSER:-tyler}
DB_NAME=${PGDATABASE:-tyler}

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <id1> [id2] ... [idN]"
    exit 1
fi

for ID in "$@"; do
        # 1. Fetch the full_path and mime_type from the database
        # Validate ID is a number to prevent SQL injection or psql errors
        if [[ ! "$ID" =~ ^[0-9]+$ ]]; then
            echo "ID: $ID : ERROR : id does not exist"
            echo ""
            continue
        fi

        RESULT=$(psql \
            --host="$DB_HOST" \
            --port="$DB_PORT" \
            --username="$DB_USER" \
            --dbname="$DB_NAME" \
            --tuples-only \
            --no-align \
            --field-separator='|' \
            --command="SELECT full_path, mime_type, 
                CASE
                    WHEN file_size < 1024 THEN file_size::text || ' B'
                    WHEN file_size < 1024^2 THEN trunc(file_size::numeric / 1024, 1)::text || ' KB'
                    WHEN file_size < 1024^3 THEN trunc(file_size::numeric / 1024^2, 1)::text || ' MB'
                    WHEN file_size < 1024^4 THEN trunc(file_size::numeric / 1024^3, 1)::text || ' GB'
                    ELSE trunc(file_size::numeric / 1024^4, 1)::text || ' TB'
                END,
                to_char(last_modified, 'YYYY-MM-DD HH24:MI:SS')
                FROM hashes WHERE id = $ID;")

        if [ -n "$RESULT" ]; then
            FULL_PATH=$(echo "$RESULT" | cut -d'|' -f1)
            MIME_TYPE=$(echo "$RESULT" | cut -d'|' -f2)
            SIZE_STR=$(echo "$RESULT" | cut -d'|' -f3)
            DATE_STR=$(echo "$RESULT" | cut -d'|' -f4)

            if [ -f "$FULL_PATH" ]; then
                echo "ID : $ID MIME-TYPE: $MIME_TYPE SIZE: $SIZE_STR DATE: $DATE_STR"
                echo "$FULL_PATH"
                # 2. Execute imgcat
                imgcat --preserve-aspect-ratio --width 30% "$FULL_PATH"
                echo "" # Output a blank line
            else
                echo "ID: $ID : ERROR : file does not exist on disk: $FULL_PATH"
                echo ""
            fi
        else
            echo "ID: $ID : ERROR : id does not exist"
            echo ""
        fi
    done
