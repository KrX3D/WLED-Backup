#!/usr/bin/env bash
#
# backup-one.sh <hostname> <index>
#   - Requires: bash, curl, date, jq
#   - Fetches WLED JSON endpoints for one host
#   - Subfolder named by id.name (or device<index>)
#   - Keys only: no need for “json/” or “.json” in ENDPOINTS
#
set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

if [ $# -lt 2 ]; then
  LOG "[ERROR] Usage: $0 <hostname> <index>"
  exit 1
fi

HOST="$1"; IDX="$2"
RUN_DIR="${BACKUP_DIR:?BACKUP_DIR must be set}"

# Build curl options
CURL_OPTS="-sSLf"
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  CURL_OPTS+=" -k"
  LOG "[WARN] TLS certificate verification is disabled"
fi

# 1) Fetch cfg.json to extract .id.name
TMP_CFG="$(mktemp)"
if ! curl $CURL_OPTS "http://$HOST/cfg.json" -o "$TMP_CFG" \
    && ! curl $CURL_OPTS "https://$HOST/cfg.json" -o "$TMP_CFG"; then
  LOG "[ERROR] Could not fetch cfg.json from $HOST"
  rm -f "$TMP_CFG"
  exit 2
fi

# 2) Extract id.name via jq, fallback to device<index>
DEV_NAME=""
if command -v jq >/dev/null; then
  DEV_NAME=$(jq -r '.id.name // empty' "$TMP_CFG")
fi
rm -f "$TMP_CFG"

if [ -n "$DEV_NAME" ]; then
  DIR_NAME="${DEV_NAME//[^[:alnum:]_-]/_}"
else
  DIR_NAME="device${IDX}"
fi

HOST_DIR="$RUN_DIR/$DIR_NAME"
mkdir -p "$HOST_DIR"
LOG "[INFO] Backing up $HOST as '$DIR_NAME' → $HOST_DIR"

# 3) Collect keys
if [ -n "${ENDPOINTS:-}" ]; then
  IFS=',' read -ra KEYS <<< "$ENDPOINTS"
else
  KEYS=( "cfg" "state" )
fi
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  KEYS+=( "${EXTRA[@]}" )
fi

# 4) Protocol order
IFS=',' read -ra PROT_ARRAY <<< "${PROTOCOLS:-http,https}"

# 5) Loop and fetch
for KEY in "${KEYS[@]}"; do
  case "$KEY" in
    cfg)     PATH="cfg.json"     ;;
    presets) PATH="presets.json" ;;
    *)       PATH="json/${KEY}"  ;;
  esac

  OUT="$HOST_DIR/$KEY.json"
  SUCCESS=false

  for P in "${PROT_ARRAY[@]}"; do
    URL="$P://$HOST/$PATH"
    LOG "[INFO] Trying $URL → $OUT"
    if curl $CURL_OPTS "$URL" -o "$OUT"; then
      LOG "[INFO] Saved $OUT"
      SUCCESS=true
      # pretty‐print
      if command -v jq >/dev/null; then
        LOG "[INFO] Formatting $OUT"
        jq . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG "[WARN] $P failed for $KEY"
    fi
  done

  if [ "$SUCCESS" != "true" ]; then
    LOG "[ERROR] Failed to fetch '$KEY' from $HOST via [${PROTOCOLS:-http,https}]"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST ($DIR_NAME)"
