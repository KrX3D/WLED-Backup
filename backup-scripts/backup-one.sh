#!/usr/bin/env bash
#
# backup-one.sh <hostname> <index>
#   Fetches JSON endpoints from one WLED host,
#   names its folder by id.name or device<index>,
#   supports dynamic endpoints, protocol fallback,
#   optional TLS skip, and logging.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

if [ $# -lt 2 ]; then
  LOG "[ERROR] Usage: $0 <hostname> <index>"
  exit 1
fi

HOST="$1"
IDX="$2"
RUN_DIR="${BACKUP_DIR:?BACKUP_DIR must be set}"

JQ_CMD=$(command -v jq || true)

# 1) Fetch cfg.json first to extract device name
TMP_CFG="$(mktemp)"
LOG "[INFO] Fetching cfg.json for name resolution"
curl_opts="-sSLf"
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  curl_opts="$curl_opts -k"
  LOG "[WARN] TLS certificate verification is disabled"
fi

if ! curl $curl_opts "${PROTOCOLS:-http,https}" | awk -v host="$HOST" -v pf="$curl_opts" \
   'BEGIN{split(protos,",",p)} END{}' ; then
  # Sorry, simpler: we try http then https explicitly:
  if ! curl $curl_opts "http://$HOST/cfg.json" -o "$TMP_CFG" \
     && ! curl $curl_opts "https://$HOST/cfg.json" -o "$TMP_CFG"; then
    LOG "[ERROR] Could not fetch cfg.json from $HOST"
    rm -f "$TMP_CFG"
    exit 2
  fi
fi

# parse device name
if [ -n "$JQ_CMD" ]; then
  DEV_NAME=$(jq -r '.id.name // empty' "$TMP_CFG")
fi
rm -f "$TMP_CFG"

# sanitize or fallback
if [ -n "${DEV_NAME:-}" ]; then
  DIR_NAME="${DEV_NAME//[^[:alnum:]-_]/_}"
else
  DIR_NAME="device${IDX}"
fi

HOST_DIR="$RUN_DIR/$DIR_NAME"
mkdir -p "$HOST_DIR"
LOG "[INFO] Created device folder: $HOST_DIR"

# 2) Determine endpoints list
if [ -n "${ENDPOINTS:-}" ]; then
  IFS=',' read -ra ENDPOINTS_LIST <<< "$ENDPOINTS"
else
  ENDPOINTS_LIST=( "cfg.json" "json/state" )
fi
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  ENDPOINTS_LIST+=( "${EXTRA[@]}" )
fi

# 3) Protocols
IFS=',' read -ra PROT_ARR <<< "${PROTOCOLS:-http,https}"

# 4) Fetch each endpoint
for EP in "${ENDPOINTS_LIST[@]}"; do
  SAFE_EP="${EP//\//_}"
  OUT="$HOST_DIR/$SAFE_EP"
  [[ "$OUT" != *.json ]] && OUT="$OUT.json"

  SUCCESS=false
  for P in "${PROT_ARR[@]}"; do
    URL="$P://$HOST/$EP"
    LOG "[INFO] Trying $URL → $OUT"
    if curl $curl_opts "$URL" -o "$OUT"; then
      LOG "[INFO] Saved $OUT"
      SUCCESS=true
      if [ -n "$JQ_CMD" ]; then
        LOG "[INFO] Formatting JSON: $OUT"
        jq . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG "[WARN] $P failed for $EP"
    fi
  done

  if ! $SUCCESS; then
    LOG "[ERROR] Could not fetch $EP from $HOST using [${PROTOCOLS:-http,https}]"
    exit 2
  fi
done

LOG "[INFO] Completed backup for $HOST ($DIR_NAME)"
