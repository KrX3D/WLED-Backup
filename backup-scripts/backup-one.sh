#!/usr/bin/env bash
#
# backup-one.sh <hostname>
#   Fetches cfg.json and presets.json from one WLED host.

set -e

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"
JQ=$(command -v jq || true)
DEST_DIR="${BACKUP_DIR:-/backups}"

mkdir -p "${DEST_DIR}"

fetch() {
  local url="$1" out="$2"
  curl -sSf "$url" -o "$out"
  if [ -n "$JQ" ]; then
    jq . "$out" > "${out}.tmp" && mv "${out}.tmp" "$out"
  fi
}

echo "Backing up ${HOST}…"
fetch "http://${HOST}/cfg.json"     "${DEST_DIR}/${HOST}.cfg.json"
fetch "http://${HOST}/presets.json" "${DEST_DIR}/${HOST}.presets.json"
echo "✓ ${HOST}"
