#!/usr/bin/env bash
#
# backup-one.sh <hostname> <index>
#   Backs up a single WLED device. Called by backup-discover.sh.

set -euo pipefail

# LOG <LEVEL> <MESSAGE...>
LOG() {
  local level="$1"; shift
  local ts
  ts=$(/bin/date +'%Y-%m-%d %H:%M:%S')
  local context="device"
  if [ -n "${HOST:-}" ]; then
    context="$HOST"
  fi
  local line="$ts [$level] [$context] $*"
  if [ -n "${LOG_FILE:-}" ]; then
    echo "$line" | tee -a "$LOG_FILE"
  else
    echo "$line"
  fi
}

if [ $# -lt 2 ]; then
  LOG ERROR "Usage: $0 <hostname> <index>"
  exit 1
fi

HOST="$1"; IDX="$2"
RUN_DIR="${BACKUP_DIR:?BACKUP_DIR must be set}"
OFFLINE_OK="${OFFLINE_OK:-true}"

# Build curl command array
# --compressed: some devices/proxies answer with gzip even for plain requests.
CURL_CMD=( /usr/bin/curl -sSLf --compressed --connect-timeout 10 --max-time 60 )
if [ "${SKIP_TLS_VERIFY:-false}" = "true" ]; then
  CURL_CMD+=( -k )
  LOG WARN "TLS certificate verification is disabled"
fi

# gunzip_if_needed <file>: some servers send gzip data without a
# Content-Encoding header, which curl cannot decode. Detect the magic bytes.
gunzip_if_needed() {
  local f="$1"
  if [ "$(head -c 2 "$f" | od -An -tx1 | tr -d ' 
')" = "1f8b" ]; then
    if gzip -dc "$f" > "$f.dec" 2>/dev/null; then
      mv "$f.dec" "$f"
    else
      rm -f "$f.dec"
    fi
  fi
}

# Protocol order (used for both name fetch and endpoint downloads)
IFS=',' read -ra PROT_ARRAY <<< "${PROTOCOLS:-http,https}"

# 1) Fetch cfg.json for name, respecting PROTOCOLS order
TMP_CFG="$(mktemp)"
NAME_FETCHED=false
REACHED_BAD=false
for P in "${PROT_ARRAY[@]}"; do
  if FINAL_URL=$("${CURL_CMD[@]}" "$P://$HOST/cfg.json" -o "$TMP_CFG" -w '%{url_effective}' 2>/dev/null); then
    gunzip_if_needed "$TMP_CFG"
    if /usr/bin/jq -e . "$TMP_CFG" >/dev/null 2>&1; then
      NAME_FETCHED=true
      break
    fi
    REACHED_BAD=true
    LOG WARN "$P://$HOST/cfg.json did not return JSON (ended up at $FINAL_URL); a redirect or reverse proxy in front of the device?"
  fi
done

if [ "$NAME_FETCHED" != "true" ]; then
  rm -f "$TMP_CFG"
  if [ "$REACHED_BAD" = "true" ]; then
    # The host answered, so it is not offline: never hide this behind OFFLINE_OK.
    LOG ERROR "$HOST answered but did not return a valid cfg.json (see warnings above)"
    exit 2
  fi
  LOG WARN "Could not fetch cfg.json from $HOST"
  if [ "$OFFLINE_OK" = "true" ]; then
    LOG WARN "Skipping $HOST because it appears offline (OFFLINE_OK=true)."
    exit 0
  fi
  exit 2
fi

# 2) Extract id.name
DEV_NAME=""
if command -v /usr/bin/jq &>/dev/null; then
  DEV_NAME=$(/usr/bin/jq -r '.id.name // empty' "$TMP_CFG" 2>/dev/null || true)
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
LOG INFO "----- Device backup start -----"

# 3) Collect keys
if [ -n "${ENDPOINTS:-}" ]; then
  IFS=',' read -ra KEYS <<< "$ENDPOINTS"
else
  KEYS=( "cfg" "presets" "state" )
fi
if [ -n "${ADDITIONAL_ENDPOINTS:-}" ]; then
  IFS=',' read -ra EXTRA <<< "$ADDITIONAL_ENDPOINTS"
  KEYS+=( "${EXTRA[@]}" )
fi

LOG INFO "Endpoints: ${KEYS[*]} | Protocols: ${PROTOCOLS:-http,https} | SKIP_TLS_VERIFY=${SKIP_TLS_VERIFY:-false}"

# 4) Loop and fetch each key
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
      gunzip_if_needed "$OUT"
      # validate + pretty-print; a non-JSON answer counts as a failed fetch
      if command -v /usr/bin/jq &>/dev/null; then
        if /usr/bin/jq . "$OUT" > "$OUT.tmp" 2>/dev/null; then
          mv "$OUT.tmp" "$OUT"
        else
          rm -f "$OUT.tmp" "$OUT"
          LOG WARN "$URL did not return valid JSON"
          continue
        fi
      fi
      LOG INFO "Saved $OUT"
      SUCCESS=true
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

# 5) Update latest snapshot if KEEP_LATEST is enabled.
#    Only runs after all endpoints succeed, so the latest folder always
#    contains a complete backup — never a partial one.
if [ "${KEEP_LATEST:-false}" = "true" ] && [ -n "${LATEST_DIR:-}" ]; then
  LOG INFO "Updating latest backup → $LATEST_DIR/$DIR_NAME"
  rm -rf "${LATEST_DIR:?}/$DIR_NAME"
  cp -r "$HOST_DIR" "$LATEST_DIR/$DIR_NAME"
  LOG INFO "Latest backup updated."
fi

LOG INFO "----- Device backup end -----"
