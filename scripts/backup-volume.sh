#!/usr/bin/env bash
set -euo pipefail

VOLUME_NAME="${VOLUME_NAME:-runclawd-data}"
BACKUP_DIR="${BACKUP_DIR:-/opt/backups/runclawd}"
TIMESTAMP="$(date +%F_%H%M%S)"
ARCHIVE_NAME="${ARCHIVE_NAME:-${VOLUME_NAME}-${TIMESTAMP}.tgz}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/backup-volume.sh [--volume NAME] [--backup-dir DIR] [--archive-name FILE.tgz]

Environment variables:
  VOLUME_NAME   Docker volume to back up (default: runclawd-data)
  BACKUP_DIR    Output directory on host (default: /opt/backups/runclawd)
  ARCHIVE_NAME  Archive filename (default: <volume>-<timestamp>.tgz)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --volume)
      VOLUME_NAME="$2"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    --archive-name)
      ARCHIVE_NAME="$2"
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

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found" >&2
  exit 1
fi

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "Docker volume not found: $VOLUME_NAME" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"

ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"

echo "Backing up volume '$VOLUME_NAME' to '$ARCHIVE_PATH' ..."
docker run --rm \
  -v "$VOLUME_NAME:/from:ro" \
  -v "$BACKUP_DIR:/to" \
  alpine sh -c "tar czf '/to/$ARCHIVE_NAME' -C /from ."

echo "Backup complete: $ARCHIVE_PATH"
