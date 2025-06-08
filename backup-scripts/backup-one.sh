#!/usr/bin/env bash
#
# backup-one.sh <hostname> <index>
#   - Fixed LOG to not pass extra args to date.
#   - Uses absolute paths for curl & jq to avoid PATH issues.

set -euo pipefail

# LOG <LEVEL> <MESSAGE...>
LOG() {
  local level="$1"; shift
  # date only gets its format, all other args go to echo
  local ts
  ts=$(/bin/date +'%Y-%m-%d %H:%M:%S')
  echo "$ts [$level] $*"
}

if [ $# -lt 2 ]; then
  LOG ERROR "Usage: $0 <hostname> <index>"
  exit 1
fi

HOST="$1"; IDX="$2"
RUN_DIR="${BACKUP_DIR:?BACKUP_DIR must be set}"

# Build curl command array
CURL_CMD=( /usr/bin/curl -sSLf )
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  CURL_CMD+=( -k )
  LOG WARN "TLS certificate verification is disabled"
fi

# 1) Fetch cfg.json for name
TMP_CFG="$(mktemp)"
if ! "${CURL_CMD[@]}" "http://$HOST/cfg.json" -o "$TMP_CFG" \
    && ! "${CURL_CMD[@]}" "https://$HOST/cfg.json" -o "$TMP_CFG"; then
  LOG ERROR "Could not fetch cfg.json from $HOST"
  rm -f "$TMP_CFG"
  exit 2
fi

# 2) Extract id.name
DEV_NAME=""
if command -v /usr/bin/jq &>/dev/null; then
  DEV_NAME=$(/usr/bin/jq -r '.id.name // empty' "$TMP_CFG")
fi
rm -f "$TMP_CFG"

if [ -n "$DEV_NAME" ]; then
  DIR_NAME="${DEV_NAME//[^[:alnum:]_-]/_}"
else
  DIR_NAME="device${IDX}"
fi

HOST_DIR="$RUN_DIR/$DIR_NAME"
mkdir -p "$HOST_DIR"
LOG INFO "Backing up $HOST as '$DIR_NAME' → $HOST_DIR"

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

# 5) Loop and fetch each key
for KEY in "${KEYS[@]}"; do
  case "$KEY" in
    cfg)     PATH_SUFFIX="cfg.json"     ;;
    presets) PATH_SUFFIX="presets.json" ;;
    *)       PATH_SUFFIX="json/${KEY}"  ;;
  esac

  OUT="$HOST_DIR/$KEY.json"
  SUCCESS=false

  for P in "${PROT_ARRAY[@]}"; do
    URL="$P://$HOST/$PATH_SUFFIX"
    LOG INFO "Trying $URL → $OUT"
    if "${CURL_CMD[@]}" "$URL" -o "$OUT"; then
      LOG INFO "Saved $OUT"
      SUCCESS=true
      # pretty‐print
      if command -v /usr/bin/jq &>/dev/null; then
        LOG INFO "Formatting $OUT"
        /usr/bin/jq . "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
      fi
      break
    else
      LOG WARN "$P failed for $KEY"
    fi
  done

  if [ "$SUCCESS" != "true" ]; then
    LOG ERROR "Failed to fetch '$KEY' from $HOST via [${PROTOCOLS:-http,https}]"
    exit 2
  fi
done

LOG INFO "Completed backup for $HOST ($DIR_NAME)"
