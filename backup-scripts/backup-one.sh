#!/usr/bin/env bash
#
# backup-one.sh <hostname>
#   Fetches JSON endpoints from one WLED host,
#   auto-tries protocols from $PROTOCOLS,
#   supports skipping TLS verify, and logs with timestamps.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

[ $# -eq 1 ] || { LOG "[ERROR] Usage: $0 <hostname>"; exit 1; }
HOST="$1"
DEST_DIR="${BACKUP_DIR:?BACKUP_DIR must be set}"
JQ_CMD=$(command -v jq || true)

# Default endpoints
ENDPOINTS=(
  cfg.json
  presets.json
  json/state
  json/info
  json/si
  json/nodes
  json/eff
  json/palx
  json/fxdata
  json/net
  json/live
  json/pal
  json/cfg
)

# Extra endpoints?
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  ENDPOINTS+=( "${EXTRA[@]}" )
fi

# Protocols to try, in order
PROTOCOLS="${PROTOCOLS:-http,https}"

# curl options
CURL_OPTS="-sSLf"
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  CURL_OPTS="$CURL_OPTS -k"
  LOG "[WARN] TLS certificate verification is disabled (SKIP_TLS_VERIFY=true)"
fi

LOG "[INFO] Backing up host: $HOST"

for EP in "${ENDPOINTS[@]}"; do
  # generate output filename
  SAFE_EP="${EP//\//_}"            # json/state → json_state
  if [[ "$SAFE_EP" == *.* ]]; then
    OUT="$DEST_DIR/$HOST.$SAFE_EP"
  else
    OUT="$DEST_DIR/$HOST.$SAFE_EP.json"
  fi

  SUCCESS=false
  IFS=',' read -ra PROT_ARR <<< "$PROTOCOLS"
  for P in "${PROT_ARR[@]}"; do
    URL="$P://$HOST/$EP"
    LOG "[INFO] Trying $URL → $OUT"
    if curl $CURL_OPTS "$URL" -o "$OUT"; then
      LOG "[INFO] Saved $OUT"
      SUCCESS=true
      # pretty‐print JSON
      if [ -n "$JQ_CMD" ] && [[ "$OUT" == *.json ]]; then
        LOG "[INFO] Formatting JSON: $OUT"
        "$JQ_CMD" . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG "[WARN] $P failed for $EP"
    fi
  done

  if [ "$SUCCESS" != true ]; then
    LOG "[ERROR] Could not fetch $EP from $HOST using [$PROTOCOLS]"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST"
