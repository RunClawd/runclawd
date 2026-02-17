#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/runclawd}"
SCHEDULE="${SCHEDULE:-30 3 * * *}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
CRON_MARKER="# runclawd-volume-backup"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/backup-cron-install.sh [--project-dir DIR] [--schedule "CRON_EXPR"] [--retention-days N]

Options:
  --project-dir DIR    Directory containing docker-compose.yaml and scripts/backup-volume.sh (default: /opt/runclawd)
  --schedule EXPR      Cron expression for backup job (default: "30 3 * * *")
  --retention-days N   Delete backup files older than N days (default: 14)

Environment variables:
  PROJECT_DIR
  SCHEDULE
  RETENTION_DAYS
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --schedule)
      SCHEDULE="$2"
      shift 2
      ;;
    --retention-days)
      RETENTION_DAYS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v crontab >/dev/null 2>&1; then
  echo "crontab command not found" >&2
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

if [ ! -f "$PROJECT_DIR/scripts/backup-volume.sh" ]; then
  echo "backup-volume.sh not found in: $PROJECT_DIR/scripts" >&2
  exit 1
fi

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  echo "--retention-days must be a non-negative integer" >&2
  exit 1
fi

BACKUP_CMD="mkdir -p /opt/backups/runclawd && cd $PROJECT_DIR && bash scripts/backup-volume.sh && find /opt/backups/runclawd -name 'runclawd-data-*.tgz' -mtime +$RETENTION_DAYS -delete"
CRON_LINE="$SCHEDULE $BACKUP_CMD $CRON_MARKER"

TMP_CRON_FILE="$(mktemp)"
cleanup() {
  rm -f "$TMP_CRON_FILE"
}
trap cleanup EXIT

crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$TMP_CRON_FILE" || true
echo "$CRON_LINE" >> "$TMP_CRON_FILE"
crontab "$TMP_CRON_FILE"

echo "Installed/updated cron job:"
echo "$CRON_LINE"
echo ""
echo "Current crontab entries with marker:"
crontab -l | grep "$CRON_MARKER" || true
