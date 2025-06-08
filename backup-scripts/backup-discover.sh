#!/usr/bin/env bash
#
# backup-discover.sh
#   Discovers all WLED instances via mDNS PLUS any EXTRA_HOSTS,
#   then calls backup-one.sh for each in a timestamped folder,
#   and prunes old runs based on RETENTION_DAYS.

set -euo pipefail

LOG() { echo "$(date +'%Y-%m-%d %H:%M:%S') $@"; }

SERVICE="_wled._tcp"
SCRIPT="$(dirname "$0")/backup-one.sh"
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"      # host-mounted root dir
RETENTION_DAYS="${RETENTION_DAYS:-30}"      # delete runs older than this

# create this run's folder
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
export BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
LOG "[INFO] New backup run directory: $BACKUP_DIR"

# 1) discover via mDNS
LOG "[INFO] Discovering WLED devices via mDNS..."
mapfile -t MDNS < <(
  avahi-browse -r -p "$SERVICE" --terminate \
    | awk -F';' '/^=/ {printf "%s.local\n",$7}' \
    | sort -u
)

# 2) include any EXTRA_HOSTS
EXTRA_LIST=()
if [ -n "${EXTRA_HOSTS:-}" ]; then
  LOG "[INFO] Adding EXTRA_HOSTS: $EXTRA_HOSTS"
  IFS=',' read -ra EXTRA_LIST <<< "$EXTRA_HOSTS"
fi

# merge & dedupe
ALL=( "${MDNS[@]}" "${EXTRA_LIST[@]}" )
# filter out blanks, dedupe
readarray -t HOSTS < <(printf '%s\n' "${ALL[@]}" | grep -v '^$' | sort -u)

if [ ${#HOSTS[@]} -eq 0 ]; then
  LOG "[INFO] No hosts found via mDNS or EXTRA_HOSTS."
  exit 0
fi

LOG "[INFO] Will back up the following hosts:"
for h in "${HOSTS[@]}"; do echo "  - $h"; done

# 3) loop & back up
FAIL=0
for H in "${HOSTS[@]}"; do
  if ! "$SCRIPT" "$H"; then
    LOG "[ERROR] backup-one.sh failed for $H"
    FAIL=1
  fi
done

if [ $FAIL -ne 0 ]; then
  LOG "[ERROR] One or more backups failed."
  exit 2
fi

LOG "[INFO] All backups completed successfully."

# 4) prune old runs
LOG "[INFO] Pruning backup runs older than $RETENTION_DAYS days..."
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
  -mtime +"$RETENTION_DAYS" -print -exec rm -rf {} \;
LOG "[INFO] Prune complete."
