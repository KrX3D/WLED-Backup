#!/usr/bin/env bash
#
# backup-one.sh <hostname> <index>
#   Fetches JSON endpoints from one WLED host,
#   mapping simple keys to real paths, placing
#   each under $BACKUP_DIR/<deviceName>/host.<key>.json.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

if [ $# -lt 2 ]; then
  LOG "[ERROR] Usage: $0 <hostname> <index>"
  exit 1
fi

HOST="$1"
IDX="$2"
RUN_DIR="${BACKUP_DIR:?BACKUP_DIR must be set}"

# First fetch cfg.json just to resolve name
TMP_CFG="$(mktemp)"
CURL_OPTS="-sSLf"
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  CURL_OPTS="$CURL_OPTS -k"
  LOG "[WARN] TLS verification disabled"
fi
# Try HTTP then HTTPS for cfg.json
if ! curl $CURL_OPTS "http://$HOST/cfg.json" -o "$TMP_CFG" \
   && ! curl $CURL_OPTS "https://$HOST/cfg.json" -o "$TMP_CFG"; then
  LOG "[ERROR] Could not fetch cfg.json from $HOST"
  rm -f "$TMP_CFG"
  exit 2
fi

# Determine directory name from .id.name
JQ=$(command -v jq || true)
if [ -n "$JQ" ]; then
  NAME=$(jq -r '.id.name // empty' "$TMP_CFG")
else
  NAME=""
fi
rm -f "$TMP_CFG"

if [ -n "$NAME" ]; then
  DIR_NAME="${NAME//[^[:alnum:]-_]/_}"
else
  DIR_NAME="device${IDX}"
fi

HOST_DIR="$RUN_DIR/$DIR_NAME"
mkdir -p "$HOST_DIR"
LOG "[INFO] Using folder: $HOST_DIR"

# Build list of keys
if [ -n "${ENDPOINTS:-}" ]; then
  IFS=',' read -ra KEYS <<< "$ENDPOINTS"
else
  KEYS=( "cfg" "state" )
fi
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  KEYS+=( "${EXTRA[@]}" )
fi

# Protocols to try
IFS=',' read -ra PROT_ARR <<< "${PROTOCOLS:-http,https}"

for KEY in "${KEYS[@]}"; do
  # map key → path & safe filename
  case "$KEY" in
    cfg)      PATH="cfg.json";        SAFE="cfg"      ;;
    presets)  PATH="presets.json";    SAFE="presets"  ;;
    *)        PATH="json/${KEY}";     SAFE="$KEY"     ;;
  esac

  OUT="$HOST_DIR/$SAFE.json"
  SUCCESS=false

  for P in "${PROT_ARR[@]}"; do
    URL="$P://$HOST/$PATH"
    LOG "[INFO] Trying $URL → $OUT"
    if curl $CURL_OPTS "$URL" -o "$OUT"; then
      LOG "[INFO] Saved $OUT"
      SUCCESS=true
      if [ -n "$JQ" ]; then
        LOG "[INFO] Formatting JSON: $OUT"
        jq . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG "[WARN] $P failed for $KEY"
    fi
  done

  if ! $SUCCESS; then
    LOG "[ERROR] Could not fetch '$KEY' from $HOST via [${PROTOCOLS:-http,https}]"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST ($DIR_NAME)"
