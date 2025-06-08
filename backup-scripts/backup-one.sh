#!/usr/bin/env bash
#
# backup-one.sh <hostname>
#   Fetches configured JSON endpoints from one WLED host,
#   auto-tries HTTP/HTTPS, logs with timestamps.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

[ $# -eq 1 ] || { LOG "[ERROR] Usage: $0 <hostname>"; exit 1; }
HOST="$1"
DEST_DIR="${BACKUP_DIR:?Environment variable BACKUP_DIR must be set}"
JQ_CMD=$(command -v jq || true)

# endpoints to fetch by default
ENDPOINTS=(cfg.json presets.json)

# allow extra endpoints, e.g. "json/state,json/info"
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  ENDPOINTS+=( "${EXTRA[@]}" )
fi

LOG "[INFO] Backing up host: $HOST"

for EP in "${ENDPOINTS[@]}"; do
  SUCCESS=false
  for PROTO in http https; do
    URL="$PROTO://$HOST/$EP"
    OUT="$DEST_DIR/$HOST.$EP"
    LOG "[INFO] Trying $URL → $OUT"
    if curl -sSLf "$URL" -o "$OUT"; then
      LOG "[INFO] Saved $OUT"
      SUCCESS=true
      # pretty-print JSON if possible
      if [ -n "$JQ_CMD" ] && [[ "$OUT" == *.json ]]; then
        LOG "[INFO] Formatting JSON: $OUT"
        "$JQ_CMD" . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG "[WARN] $PROTO failed for $EP"
    fi
  done
  if [ "$SUCCESS" != true ]; then
    LOG "[ERROR] Could not fetch any protocol for $EP from $HOST"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST"
