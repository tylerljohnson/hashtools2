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
    # 1. Fetch the full_path from the database
    FULL_PATH=$(psql \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --username="$DB_USER" \
        --dbname="$DB_NAME" \
        --tuples-only \
        --no-align \
        --command="SELECT full_path FROM hashes WHERE id = $ID;")

    if [ -n "$FULL_PATH" ]; then
        if [ -f "$FULL_PATH" ]; then
            echo "Displaying ID $ID: $FULL_PATH"
            # 2. Execute imgcat
            imgcat -r -W 30% -p "$FULL_PATH"
            echo "" # Output a blank line
        else
            echo "Error: File for ID $ID not found on filesystem: $FULL_PATH"
            echo ""
        fi
    else
        echo "Error: ID $ID not found in database."
        echo ""
    fi
done
