#!/usr/bin/env bash
#
# backup-discover.sh
#   Discovers WLED hosts via mDNS + EXTRA_HOSTS,
#   runs backup-one.sh for each with an index,
#   then prunes old runs.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

SERVICE="_wled._tcp"
SCRIPT="/usr/local/bin/backup-one.sh"
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
EXTRA_HOSTS="${EXTRA_HOSTS:-}"

# 1) Create run directory
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
export BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
LOG "[INFO] New backup run: $BACKUP_DIR"

# 2) Discover via mDNS
LOG "[INFO] Discovering WLED via mDNS..."
mapfile -t MDNS < <(
  avahi-browse -r -p "$SERVICE" --terminate \
    | awk -F';' '/^=/ {print $7".local"}' \
    | sort -u
)

# 3) Merge EXTRA_HOSTS if any
HOSTS=( "${MDNS[@]}" )
if [ -n "$EXTRA_HOSTS" ]; then
  LOG "[INFO] Adding EXTRA_HOSTS: $EXTRA_HOSTS"
  IFS=',' read -ra EXTRA <<< "$EXTRA_HOSTS"
  HOSTS+=( "${EXTRA[@]}" )
fi

# dedupe and filter blanks
readarray -t HOSTS < <(printf '%s\n' "${HOSTS[@]}" | grep -v '^$' | sort -u)

if [ ${#HOSTS[@]} -eq 0 ]; then
  LOG "[INFO] No hosts found."
  exit 0
fi

LOG "[INFO] Hosts to back up:"
for i in "${!HOSTS[@]}"; do
  LOG "  $((i+1)). ${HOSTS[i]}"
done

# 4) Back up each, passing index (1-based)
FAIL=0
for i in "${!HOSTS[@]}"; do
  idx=$((i+1))
  H="${HOSTS[i]}"
  if ! "$SCRIPT" "$H" "$idx"; then
    LOG "[ERROR] backup-one.sh failed for $H"
    FAIL=1
  fi
done

if [ $FAIL -ne 0 ]; then
  LOG "[ERROR] Some backups failed."
  exit 2
else
  LOG "[INFO] All backups succeeded."
fi

# 5) Prune old runs
LOG "[INFO] Pruning runs older than $RETENTION_DAYS days..."
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
  -mtime +"$RETENTION_DAYS" -print -exec rm -rf {} \;
LOG "[INFO] Prune complete."
