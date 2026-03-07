#!/bin/bash
set -e

# Configuration
DB_PATH="$HOME/.openclaw/sandboxes.db"
mkdir -p "$(dirname "$DB_PATH")"

# Initialize Schema
init_db() {
    sqlite3 "$DB_PATH" <<EOF
CREATE TABLE IF NOT EXISTS sandboxes (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE,
    stack TEXT,
    port INTEGER,
    tunnel_url TEXT,
    volume_path TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
EOF
}

# Helper to run queries
query_db() {
    sqlite3 "$DB_PATH" "$1"
}

# Run init if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_db
    echo "Database initialized at $DB_PATH"
fi
