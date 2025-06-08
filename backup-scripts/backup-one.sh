#!/usr/bin/env bash
#
# backup-one.sh <hostname>
#   Fetches cfg.json and presets.json from one WLED host.
#   Logs progress with timestamps.

set -euo pipefail

LOG_PREFIX() {
  local level="$1"; shift
  echo "$(date +'%Y-%m-%d %H:%M:%S') [$level]" "$@"
}

usage() {
  LOG_PREFIX ERROR "Usage: $0 <hostname>"
  exit 1
}

[ $# -eq 1 ] || usage
HOST="$1"
DEST_DIR="${BACKUP_DIR:-/backups}"
JQ_CMD=$(command -v jq || true)

mkdir -p "$DEST_DIR"

fetch() {
  local url="$1" out="$2"
  LOG_PREFIX INFO "Fetching $url → $out"
  if curl -sSf "$url" -o "$out"; then
    if [ -n "$JQ_CMD" ] && [[ "$out" =~ \.json$ ]]; then
      "$JQ_CMD" . "$out" > "$out.tmp" && mv "$out.tmp" "$out"
    fi
    LOG_PREFIX INFO "Saved $out"
  else
    LOG_PREFIX ERROR "Failed to fetch $url"
    return 1
  fi
}

LOG_PREFIX INFO "Starting backup for host: $HOST"

if fetch "http://$HOST/cfg.json"     "$DEST_DIR/$HOST.cfg.json" \
   && fetch "http://$HOST/presets.json" "$DEST_DIR/$HOST.presets.json"; then
  LOG_PREFIX INFO "Backup completed for $HOST"
else
  LOG_PREFIX ERROR "Backup failed for $HOST"
  exit 2
fi
