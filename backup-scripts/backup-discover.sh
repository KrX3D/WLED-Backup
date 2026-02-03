#!/usr/bin/env bash
#
# backup-discover.sh
#   Discovers WLED hosts via mDNS + EXTRA_HOSTS,
#   runs backup-one.sh for each with an index,
#   removes any empty device folders and possibly the run dir if empty,
#   then prunes old runs with clear logging.

set -euo pipefail

LOG() {
  local level="$1"; shift
  local message="$*"
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  local line="$ts [$level] [discover] $message"
  if [ -n "${LOG_FILE:-}" ]; then
    echo "$line" | tee -a "$LOG_FILE"
  else
    echo "$line"
  fi
}

SERVICE="_wled._tcp"
SCRIPT="/usr/local/bin/backup-one.sh"
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
EXTRA_HOSTS="${EXTRA_HOSTS:-}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  LOG WARN "RETENTION_DAYS must be a number, defaulting to 30."
  RETENTION_DAYS=30
fi

# 1) Create run directory
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
export BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
if [ "$LOG_TO_FILE" = "true" ]; then
  LOG_FILE="${BACKUP_DIR}/backup.log"
  export LOG_FILE
  : > "$LOG_FILE"
fi

LOG INFO "New backup run: $BACKUP_DIR"
LOG INFO "Settings: BACKUP_ROOT=$BACKUP_ROOT RETENTION_DAYS=$RETENTION_DAYS EXTRA_HOSTS=${EXTRA_HOSTS:-<none>} ENDPOINTS=${ENDPOINTS:-<default>} ADDITIONAL_ENDPOINTS=${ADDITIONAL_ENDPOINTS:-<none>} PROTOCOLS=${PROTOCOLS:-http,https} SKIP_TLS_VERIFY=${SKIP_TLS_VERIFY:-false} LOG_TO_FILE=$LOG_TO_FILE OFFLINE_OK=${OFFLINE_OK:-true}"

# 2) Discover via mDNS
LOG INFO "Discovering WLED via mDNS..."
if command -v avahi-browse >/dev/null 2>&1; then
  mapfile -t MDNS < <(
    avahi-browse -r -p "$SERVICE" --terminate \
      | awk -F';' '/^=/ {print $7".local"}' \
      | sort -u \
      || true
  )
else
  LOG WARN "avahi-browse not found; skipping mDNS discovery."
  MDNS=()
fi

# 3) Merge EXTRA_HOSTS if any
HOSTS=( "${MDNS[@]}" )
if [ -n "$EXTRA_HOSTS" ]; then
  LOG INFO "Adding EXTRA_HOSTS: $EXTRA_HOSTS"
  IFS=',' read -ra EXTRA <<< "$EXTRA_HOSTS"
  HOSTS+=( "${EXTRA[@]}" )
fi

# dedupe and filter blanks
readarray -t HOSTS < <(printf '%s\n' "${HOSTS[@]}" | grep -v '^$' | sort -u)

if [ ${#HOSTS[@]} -eq 0 ]; then
  LOG INFO "No hosts found."
  # Remove the empty run directory, since nothing to back up
  if rmdir "$BACKUP_DIR"; then
    LOG INFO "Removed empty run directory: $BACKUP_DIR"
  fi
  exit 0
fi

LOG INFO "Hosts to back up:"
for i in "${!HOSTS[@]}"; do
  LOG INFO "$((i+1)). ${HOSTS[i]}"
done

# 4) Back up each, passing index (1-based)
FAIL=0
for i in "${!HOSTS[@]}"; do
  idx=$((i+1))
  H="${HOSTS[i]}"
  LOG INFO "----- Starting backup ${idx}/${#HOSTS[@]}: ${H} -----"
  if ! "$SCRIPT" "$H" "$idx"; then
    LOG ERROR "backup-one.sh failed for $H"
    FAIL=1
  fi
  LOG INFO "----- Finished backup ${idx}/${#HOSTS[@]}: ${H} -----"
done

# 4a) Remove any empty device folders in this run
# For example, if backup-one.sh failed early and left an empty subfolder.
LOG INFO "Checking for empty device folders in this run..."
while IFS= read -r -d '' DIR; do
  # DIR is: /backups/<timestamp>/<deviceName>
  if [ -d "$DIR" ] && [ -z "$(ls -A "$DIR")" ]; then
    if rmdir "$DIR"; then
      LOG INFO "Removed empty device folder: $DIR"
    fi
  fi
done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

# If after removing empty device folders, the run dir itself is empty, remove it
if [ -z "$(ls -A "$BACKUP_DIR")" ]; then
  if rmdir "$BACKUP_DIR"; then
    LOG INFO "All device folders removed; removed run directory: $BACKUP_DIR"
  fi
  # We still go on to prune older runs
fi

if [ $FAIL -ne 0 ]; then
  LOG ERROR "Some backups failed."
else
  LOG INFO "All backups succeeded."
fi

# --- 5) Prune old runs ---
#
# find’s -mtime semantics: 
#   -mtime +n matches items whose data was last modified *strictly more than* n*24h ago.
#   E.g., -mtime +0 matches files modified more than 24h ago.
#
# If RETENTION_DAYS=1, we want to remove runs older than 24h. I.e., use -mtime +0.
# If RETENTION_DAYS=30, remove runs older than 30*24h; I.e., -mtime +29 (strictly >29 days),
# but often admins want "keep last N days, delete anything older than N days". 
# Using -mtime +$((RETENTION_DAYS-1)) approximates that.
#
# For RETENTION_DAYS <= 1, we use -mtime +0 (remove >24h). For >1, use +RETENTION_DAYS-1.

if [ "$RETENTION_DAYS" -le 1 ]; then
  MTDAYS=0
else
  MTDAYS=$((RETENTION_DAYS - 1))
fi

LOG INFO "Pruning runs older than ${RETENTION_DAYS} day(s) (find -mtime +${MTDAYS})..."
while IFS= read -r -d '' OLD_DIR; do
  LOG INFO "Removing old run directory: $OLD_DIR"
  rm -rf "$OLD_DIR"
done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$MTDAYS" -print0)
LOG INFO "Prune complete."
