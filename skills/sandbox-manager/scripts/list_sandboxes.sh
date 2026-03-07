#!/bin/bash
source "$(dirname "$0")/db.sh"
init_db

echo "Active Sandboxes:"
echo "-----------------"
# formatting might be tricky with simple sqlite output, but let's try column mode
sqlite3 -header -column "$DB_PATH" "SELECT name, stack, tunnel_url, created_at FROM sandboxes;"
