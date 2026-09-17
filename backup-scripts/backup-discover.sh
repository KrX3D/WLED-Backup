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
RETENTION_WEEKS="${RETENTION_WEEKS:-0}"
RETENTION_MONTHS="${RETENTION_MONTHS:-0}"
RETENTION_YEARS="${RETENTION_YEARS:-0}"
EXTRA_HOSTS="${EXTRA_HOSTS:-}"
LOG_TO_FILE="${LOG_TO_FILE:-false}"
KEEP_LATEST="${KEEP_LATEST:-false}"

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  LOG WARN "RETENTION_DAYS must be a number, defaulting to 30."
  RETENTION_DAYS=30
fi
for VAR in RETENTION_WEEKS RETENTION_MONTHS RETENTION_YEARS; do
  if ! [[ "${!VAR}" =~ ^[0-9]+$ ]]; then
    LOG WARN "$VAR must be a number, defaulting to 0 (disabled)."
    printf -v "$VAR" '%s' 0
  fi
done

# 1) Create run directory
TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"
export BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
if [ "$LOG_TO_FILE" = "true" ]; then
  LOG_FILE="${BACKUP_DIR}/backup.log"
  export LOG_FILE
  : > "$LOG_FILE"
fi

# Export variables needed by backup-one.sh
export BACKUP_ROOT
export KEEP_LATEST
LATEST_DIR="${BACKUP_ROOT}/latest"
export LATEST_DIR
if [ "$KEEP_LATEST" = "true" ]; then
  mkdir -p "$LATEST_DIR"
  LOG INFO "KEEP_LATEST enabled; latest backups will be kept in: $LATEST_DIR"
fi

LOG INFO "New backup run: $BACKUP_DIR"
LOG INFO "Settings: BACKUP_ROOT=$BACKUP_ROOT RETENTION_DAYS=$RETENTION_DAYS RETENTION_WEEKS=$RETENTION_WEEKS RETENTION_MONTHS=$RETENTION_MONTHS RETENTION_YEARS=$RETENTION_YEARS EXTRA_HOSTS=${EXTRA_HOSTS:-<none>} ENDPOINTS=${ENDPOINTS:-<default>} ADDITIONAL_ENDPOINTS=${ADDITIONAL_ENDPOINTS:-<none>} PROTOCOLS=${PROTOCOLS:-http,https} SKIP_TLS_VERIFY=${SKIP_TLS_VERIFY:-false} LOG_TO_FILE=$LOG_TO_FILE OFFLINE_OK=${OFFLINE_OK:-true} KEEP_LATEST=$KEEP_LATEST"

# 2) Discover via mDNS
LOG INFO "Discovering WLED via mDNS..."
MDNS=()
if command -v avahi-browse >/dev/null 2>&1; then
  AVAHI_OUT="$(mktemp)"
  AVAHI_ERR="$(mktemp)"
  if avahi-browse -r -p "$SERVICE" --terminate >"$AVAHI_OUT" 2>"$AVAHI_ERR"; then
    mapfile -t MDNS < <(awk -F';' '/^=/ {print $7".local"}' "$AVAHI_OUT" | sort -u)
  else
    LOG WARN "avahi-browse failed: $(tr '\n' ' ' < "$AVAHI_ERR")"
    LOG WARN "mDNS discovery may not work without access to the host's D-Bus/Avahi sockets (--network=host alone is not enough; also mount /var/run/dbus and the avahi-daemon socket, or run avahi-daemon on the host)."
  fi
  rm -f "$AVAHI_OUT" "$AVAHI_ERR"
else
  LOG WARN "avahi-browse not found; skipping mDNS discovery."
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
  # Remove the run directory, since nothing to back up. It may contain only
  # backup.log (when LOG_TO_FILE=true), so rmdir alone would fail here.
  unset LOG_FILE
  rm -rf "$BACKUP_DIR"
  LOG INFO "Removed empty run directory: $BACKUP_DIR"
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
# Tiered retention (grandfather-father-son). A run is kept if ANY rule keeps it:
#   RETENTION_DAYS   - every run younger than N*24h (N <= 1 means 24h).
#   RETENTION_WEEKS  - the newest run of each of the last N ISO weeks (Mon-Sun)
#                      that have a backup.
#   RETENTION_MONTHS - the newest run of each of the last N calendar months
#                      that have a backup.
#   RETENTION_YEARS  - the newest run of each of the last N calendar years
#                      that have a backup.
# Weeks/months/years are counted by buckets that actually contain a run, so
# a gap in backups (e.g. the container was down for a while) never makes the
# older weekly/monthly/yearly runs disappear. The current week/month/year
# counts as one of the N.
#
# A run's time comes from its YYYYMMDD_HHMMSS folder name, falling back to the
# folder's mtime for other names, so copying or restoring the backup folder
# does not reset ages. Runs without any device folder (e.g. only backup.log
# because every device was offline) are never chosen as a weekly/monthly/yearly
# run; they only live for RETENTION_DAYS.
#
# The "latest" folder is always excluded from pruning regardless of KEEP_LATEST,
# so it is never accidentally deleted.

# run_info <dir>: prints "<epoch> <iso-week> <month> <year>" for a run folder.
run_info() {
  local dir="$1" name="${1##*/}"
  if [[ "$name" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$ ]]; then
    if date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}:${BASH_REMATCH[6]}" \
         +'%s %G-W%V %Y-%m %Y' 2>/dev/null; then
      return 0
    fi
  fi
  date -r "$dir" +'%s %G-W%V %Y-%m %Y'
}

declare -A BUCKET_SEEN=()
declare -A BUCKET_COUNT=( [weekly]=0 [monthly]=0 [yearly]=0 )

# claim_bucket <period> <key> <limit>
#   Succeeds if <key> is a bucket not seen before and fewer than <limit> buckets
#   of <period> have been kept so far. Runs are visited newest first, so the
#   run that claims a bucket is the newest run in it.
claim_bucket() {
  local period="$1" key="$2" limit="$3"
  local count="${BUCKET_COUNT[$period]}"
  if [ "$limit" -eq 0 ] || [ "$count" -ge "$limit" ] || [ -n "${BUCKET_SEEN["$period:$key"]:-}" ]; then
    return 1
  fi
  BUCKET_SEEN["$period:$key"]=1
  BUCKET_COUNT[$period]=$(( count + 1 ))
}

if [ "$RETENTION_DAYS" -le 1 ]; then
  KEEP_SECONDS=86400
else
  KEEP_SECONDS=$(( 10#$RETENTION_DAYS * 86400 ))
fi
NOW="$(date +%s)"

LOG INFO "Pruning runs: keeping everything from the last ${RETENTION_DAYS} day(s), plus the newest run of the last ${RETENTION_WEEKS} week(s), ${RETENTION_MONTHS} month(s) and ${RETENTION_YEARS} year(s)..."
while IFS=' ' read -r -d '' RUN_EPOCH RUN_WEEK RUN_MONTH RUN_YEAR RUN_DIR; do
  REASONS=()
  if [ $(( NOW - RUN_EPOCH )) -lt "$KEEP_SECONDS" ]; then
    REASONS+=( "daily" )
  fi
  if [ -n "$(find "$RUN_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]; then
    if claim_bucket weekly "$RUN_WEEK" "$RETENTION_WEEKS"; then REASONS+=( "weekly:$RUN_WEEK" ); fi
    if claim_bucket monthly "$RUN_MONTH" "$RETENTION_MONTHS"; then REASONS+=( "monthly:$RUN_MONTH" ); fi
    if claim_bucket yearly "$RUN_YEAR" "$RETENTION_YEARS"; then REASONS+=( "yearly:$RUN_YEAR" ); fi
  fi

  if [ ${#REASONS[@]} -eq 0 ]; then
    LOG INFO "Removing old run directory: $RUN_DIR"
    rm -rf "$RUN_DIR"
  elif [ "${REASONS[0]}" != "daily" ]; then
    LOG INFO "Keeping $RUN_DIR ($(IFS=,; echo "${REASONS[*]}"))"
  fi
done < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -not -name "latest" -print0 |
    while IFS= read -r -d '' DIR; do
      if INFO="$(run_info "$DIR")"; then
        printf '%s %s\0' "$INFO" "$DIR"
      else
        LOG WARN "Could not determine the age of $DIR; keeping it." >&2
      fi
    done |
    sort -z -k1,1nr
)
LOG INFO "Prune complete."
