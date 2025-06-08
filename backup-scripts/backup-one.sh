#!/usr/bin/env bash
#
# backup-one.sh <hostname>
#   Fetches a set of JSON endpoints from one WLED host,
#   auto-tries HTTP/HTTPS, logs with timestamps.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

[ $# -eq 1 ] || { LOG "[ERROR] Usage: $0 <hostname>"; exit 1; }
HOST="$1"
DEST_DIR="${BACKUP_DIR:?Environment variable BACKUP_DIR must be set}"
JQ_CMD=$(command -v jq || true)

# Default WLED API endpoints
ENDPOINTS=(
  cfg.json            # legacy
  presets.json        # legacy
  json/state
  json/info
  json/si
  json/nodes
  json/eff
  json/palx
  json/fxdata
  json/net
  json/live           # only if you compiled with WLED_ENABLE_JSONLIVE
  json/pal
  json/cfg
)

# Add extra endpoints via env var, e.g. "json/custom,json/extra"
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  ENDPOINTS+=( "${EXTRA[@]}" )
fi

LOG "[INFO] Backing up host: $HOST"

for EP in "${ENDPOINTS[@]}"; do
  SUCCESS=false
  for PROTO in http https; do
    URL="$PROTO://$HOST/$EP"
    # replace slashes for filename
    OUT="$DEST_DIR/$HOST.${EP//\//_}.json"
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
    LOG "[ERROR] Could not fetch endpoint $EP from $HOST"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST"
