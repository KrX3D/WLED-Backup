#!/usr/bin/env bash
#
# backup-discover.sh
#   Discovers WLED hosts via mDNS + EXTRA_HOSTS,
#   runs backup-one.sh in a timestamped folder,
#   then prunes old runs.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

SERVICE="_wled._tcp"
SCRIPT="/usr/local/bin/backup-one.sh"
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
EXTRA_HOSTS="${EXTRA_HOSTS:-}"

# 1) Make run directory
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
export BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
LOG "[INFO] Created backup directory: $BACKUP_DIR"

# 2) Discover via mDNS
LOG "[INFO] Discovering via mDNS..."
mapfile -t MDNS < <(
  avahi-browse -r -p "$SERVICE" --terminate \
    | awk -F';' '/^=/ {print $7".local"}' | sort -u
)

# 3) Add any EXTRA_HOSTS (comma-separated)
HOSTS=( "${MDNS[@]}" )
if [ -n "$EXTRA_HOSTS" ]; then
  LOG "[INFO] Including EXTRA_HOSTS: $EXTRA_HOSTS"
  IFS=',' read -ra EXTRA <<< "$EXTRA_HOSTS"
  HOSTS+=( "${EXTRA[@]}" )
fi

# dedupe & filter blank
readarray -t HOSTS < <(printf '%s\n' "${HOSTS[@]}" | grep -v '^$' | sort -u)

if [ ${#HOSTS[@]} -eq 0 ]; then
  LOG "[INFO] No hosts to back up."
  exit 0
fi

LOG "[INFO] Will back up:"
for h in "${HOSTS[@]}"; do LOG "  - $h"; done

# 4) Backup each
FAIL=0
for H in "${HOSTS[@]}"; do
  if ! "$SCRIPT" "$H"; then
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
