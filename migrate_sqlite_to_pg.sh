#!/usr/bin/env bash
set -euo pipefail
SRC="/root/llm-stack/backups/openwebui_db_20251221_180332.sqlite"
TMPDIR="/root/llm-stack/tmp_mig"
PGCMD="docker compose exec -T db psql -U litellmadmin -d openwebui_db"
mkdir -p "$TMPDIR"
TABLES=(
  user "group" group_member folder
  chat message message_reaction
  api_key auth channel channel_member channel_webhook chatidtag config document feedback file function knowledge knowledge_file memory migratehistory model note oauth_session prompt tag tool
)
$PGCMD -c "SET session_replication_role = 'replica';"
for tbl in "${TABLES[@]}"; do
  csv="$TMPDIR/${tbl}.csv"
  sqlite3 -header -csv "$SRC" "SELECT * FROM \"$tbl\"" > "$csv"
  # truncate target table
  $PGCMD -c "TRUNCATE TABLE \"$tbl\" RESTART IDENTITY CASCADE;"
  # import
  cat "$csv" | $PGCMD -c "COPY \"$tbl\" FROM STDIN WITH (FORMAT csv, HEADER true);"
done
$PGCMD -c "SET session_replication_role = 'origin';"
echo "DONE"
