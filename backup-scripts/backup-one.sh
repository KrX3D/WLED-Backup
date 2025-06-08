#!/usr/bin/env bash
#
# backup-one.sh <hostname>
#   Fetches cfg.json and presets.json from one WLED host.
#   Logs progress with timestamps and follows redirects.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

[ $# -eq 1 ] || { LOG "[ERROR] Usage: $0 <hostname>"; exit 1; }
HOST="$1"
DEST_DIR="${BACKUP_DIR:?Needs BACKUP_DIR set to a writable path}"
JQ_CMD=$(command -v jq || true)

LOG "[INFO] Starting backup for host: $HOST"

for ENDPOINT in cfg.json presets.json; do
  URL="http://$HOST/$ENDPOINT"
  OUT="${DEST_DIR}/${HOST}.${ENDPOINT}"
  LOG "[INFO] Fetching $URL → $OUT"
  if curl -sSLf "$URL" -o "$OUT"; then
    LOG "[INFO] Saved $OUT"
    # pretty-print if jq is present
    if [ -n "$JQ_CMD" ]; then
      LOG "[INFO] Formatting JSON: $OUT"
      "$JQ_CMD" . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
    fi
  else
    LOG "[ERROR] Failed to fetch $URL"
    return 1
  fi
done

LOG "[INFO] Backup completed for $HOST"
