#!/usr/bin/env bash
#
# backup-one.sh <hostname> <index>
#   - Fetches WLED JSON endpoints for one host.
#   - Creates a subfolder named by the device’s "id.name" (or "device<index>" fallback).
#   - Maps simple keys to real paths (no need to include “json/” or “.json”).
#   - Supports:
#       • ENDPOINTS="cfg,state,info,si,..."      # comma-separated keys
#       • ADDITIONAL_ENDPOINTS="live,nodes,eff"   # extra keys to append
#       • PROTOCOLS="https,http"                  # try HTTPS first, then HTTP
#       • SKIP_TLS_VERIFY=true                    # add -k to curl for self-signed certs
#
# Writes each response to:
#   $BACKUP_DIR/<deviceName>/<key>.json
#
set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

# --- args & env check ---
if [ $# -lt 2 ]; then
  LOG "[ERROR] Usage: $0 <hostname> <index>"
  exit 1
fi
HOST="$1"
IDX="$2"
RUN_DIR="${BACKUP_DIR:?BACKUP_DIR must be set by backup-discover.sh}"

# --- prepare curl options ---
CURL_OPTS="-sSLf"
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  CURL_OPTS+=" -k"
  LOG "[WARN] TLS certificate verification is disabled"
fi

# --- resolve device name from cfg.json ---
TMP_CFG="$(mktemp)"
if ! curl $CURL_OPTS "http://$HOST/cfg.json" -o "$TMP_CFG" \
    && ! curl $CURL_OPTS "https://$HOST/cfg.json" -o "$TMP_CFG"; then
  LOG "[ERROR] Could not fetch cfg.json from $HOST"
  rm -f "$TMP_CFG"
  exit 2
fi

JQ=$(command -v jq || true)
if [ -n "$JQ" ]; then
  DEV_NAME=$(jq -r '.id.name // empty' "$TMP_CFG")
else
  DEV_NAME=""
fi
rm -f "$TMP_CFG"

if [ -n "$DEV_NAME" ]; then
  DIR_NAME="${DEV_NAME//[^[:alnum:]_-]/_}"
else
  DIR_NAME="device${IDX}"
fi

HOST_DIR="$RUN_DIR/$DIR_NAME"
mkdir -p "$HOST_DIR"
LOG "[INFO] Using folder: $HOST_DIR"

# --- build list of keys ---
if [ -n "${ENDPOINTS:-}" ]; then
  IFS=',' read -ra KEYS <<< "$ENDPOINTS"
else
  KEYS=( "cfg" "state" )
fi
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  KEYS+=( "${EXTRA[@]}" )
fi

# --- protocols to try ---
IFS=',' read -ra PROT_ARR <<< "${PROTOCOLS:-http,https}"

LOG "[INFO] Backing up $HOST (as $DIR_NAME): keys=${KEYS[*]}"

# --- fetch each key ---
for KEY in "${KEYS[@]}"; do
  # map to actual path & output filename
  case "$KEY" in
    cfg)      PATH="cfg.json"         ;;
    presets)  PATH="presets.json"     ;;
    *)        PATH="json/${KEY}"      ;;
  esac
  OUT="$HOST_DIR/$KEY.json"

  SUCCESS=false
  for P in "${PROT_ARR[@]}"; do
    URL="$P://$HOST/$PATH"
    LOG "[INFO] Trying $URL → $OUT"
    if curl $CURL_OPTS "$URL" -o "$OUT"; then
      LOG "[INFO] Saved $OUT"
      SUCCESS=true
      # pretty-print JSON if jq is available
      if [ -n "$JQ" ]; then
        LOG "[INFO] Formatting $OUT"
        jq . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG "[WARN] $P failed for $KEY"
    fi
  done

  if [ "$SUCCESS" != "true" ]; then
    LOG "[ERROR] Could not fetch '$KEY' from $HOST via [${PROTOCOLS:-http,https}]"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST ($DIR_NAME)"
