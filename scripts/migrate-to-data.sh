#!/usr/bin/env bash
set -e

MIGRATION_FLAG="/data/.migration-complete"
OLD_CONFIG_DIR="/root/.openclaw"
OLD_WORKSPACE_DIR="/root/openclaw-workspace"
NEW_CONFIG_DIR="/data/.openclaw"
NEW_WORKSPACE_DIR="/data/openclaw-workspace"

if [ -f "$MIGRATION_FLAG" ]; then
    echo "Migration already completed. Skipping."
    exit 0
fi

if [ ! -d "$OLD_CONFIG_DIR" ] && [ ! -d "$OLD_WORKSPACE_DIR" ]; then
    echo "No old data found at /root paths. Fresh install detected."
    touch "$MIGRATION_FLAG"
    exit 0
fi

echo "=========================================="
echo "Migrating data from /root to /data"
echo "=========================================="

mkdir -p "$NEW_CONFIG_DIR"
mkdir -p "$NEW_WORKSPACE_DIR"

if [ -d "$OLD_CONFIG_DIR" ] && [ "$(ls -A $OLD_CONFIG_DIR 2>/dev/null)" ]; then
    echo "Migrating $OLD_CONFIG_DIR to $NEW_CONFIG_DIR..."
    cp -r "$OLD_CONFIG_DIR"/* "$NEW_CONFIG_DIR"/ 2>/dev/null || true
    echo "Config migrated"
fi

if [ -d "$OLD_WORKSPACE_DIR" ] && [ "$(ls -A $OLD_WORKSPACE_DIR 2>/dev/null)" ]; then
    echo "Migrating $OLD_WORKSPACE_DIR to $NEW_WORKSPACE_DIR..."
    cp -r "$OLD_WORKSPACE_DIR"/* "$NEW_WORKSPACE_DIR"/ 2>/dev/null || true
    echo "Workspace migrated"
fi

for dir in .agents .ssh .config .local .cache .npm .bun .claude .kimi .gitconfig .bash_history; do
    if [ -e "/root/$dir" ] && [ ! -L "/root/$dir" ]; then
        echo "Migrating /root/$dir to /data/$dir..."
        if [ -d "/root/$dir" ]; then
            mkdir -p "/data/$dir"
            cp -r "/root/$dir"/* "/data/$dir"/ 2>/dev/null || true
        else
            cp "/root/$dir" "/data/$dir" 2>/dev/null || true
        fi
        echo "/root/$dir migrated"
    fi
done

chmod 700 "$NEW_CONFIG_DIR" 2>/dev/null || true
chmod 700 "$NEW_WORKSPACE_DIR" 2>/dev/null || true
chmod 700 "/data/.ssh" 2>/dev/null || true

touch "$MIGRATION_FLAG"
echo ""
echo "=========================================="
echo "Migration complete!"
echo "Your data has been moved from /root to /data"
echo "Old data remains at /root as backup"
echo "=========================================="
