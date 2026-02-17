#!/usr/bin/env bash
set -euo pipefail

VOLUME_NAME="${VOLUME_NAME:-runclawd-data}"
WIPE_FIRST=true
FORCE=false
BACKUP_FILE=""

usage() {
  cat <<'EOF'
Usage:
  bash scripts/restore-volume.sh --backup-file /path/to/backup.tgz [--volume NAME] [--no-wipe] [--force]

Options:
  --backup-file PATH  Backup archive (.tgz) created by backup-volume.sh (required)
  --volume NAME       Docker volume to restore into (default: runclawd-data)
  --no-wipe           Do not delete existing files in target volume before restore
  --force             Skip confirmation prompt
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --backup-file)
      BACKUP_FILE="$2"
      shift 2
      ;;
    --volume)
      VOLUME_NAME="$2"
      shift 2
      ;;
    --no-wipe)
      WIPE_FIRST=false
      shift
      ;;
    --force)
      FORCE=true
      shift
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

if [ -z "$BACKUP_FILE" ]; then
  echo "--backup-file is required" >&2
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found" >&2
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Backup file not found: $BACKUP_FILE" >&2
  exit 1
fi

if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "Docker volume not found: $VOLUME_NAME" >&2
  exit 1
fi

if [ "$FORCE" != "true" ]; then
  echo "This will restore '$BACKUP_FILE' into volume '$VOLUME_NAME'."
  if [ "$WIPE_FIRST" = "true" ]; then
    echo "Existing files in the volume will be deleted first."
  fi
  printf "Continue? [y/N] "
  read -r answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
fi

BACKUP_DIR="$(dirname "$BACKUP_FILE")"
BACKUP_NAME="$(basename "$BACKUP_FILE")"

if [ "$WIPE_FIRST" = "true" ]; then
  echo "Wiping existing data in volume '$VOLUME_NAME' ..."
  docker run --rm -v "$VOLUME_NAME:/data" alpine sh -c "rm -rf /data/* /data/.[!.]* /data/..?* 2>/dev/null || true"
fi

echo "Restoring '$BACKUP_FILE' into volume '$VOLUME_NAME' ..."
docker run --rm \
  -v "$VOLUME_NAME:/to" \
  -v "$BACKUP_DIR:/from:ro" \
  alpine sh -c "tar xzf '/from/$BACKUP_NAME' -C /to"

echo "Restore complete."
echo "Tip: restart services after restore: docker compose up -d"
