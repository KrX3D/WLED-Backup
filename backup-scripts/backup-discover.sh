#!/usr/bin/env bash
#
# backup-discover.sh
#   Discovers all WLED instances via avahi-browse PLUS any EXTRA_HOSTS,
#   then calls backup-one.sh for each, logging progress.

set -euo pipefail

LOG_PREFIX() {
  local level="$1"; shift
  echo "$(date +'%Y-%m-%d %H:%M:%S') [$level]" "$@"
}

SERVICE="_wled._tcp"
SCRIPT="$(dirname "$0")/backup-one.sh"
DEST_DIR="${BACKUP_DIR:-/backups}"

# collect hosts from mDNS
LOG_PREFIX INFO "Discovering WLED devices via mDNS..."
mapfile -t MDNS_HOSTS < <(
  avahi-browse -r -p "$SERVICE" --terminate \
    | awk -F';' '/^=/ {print $7".local"}' \
    | sort -u
)

# collect extra hosts from env var (comma-separated)
EXTRA_HOSTS_LIST=()
if [ -n "${EXTRA_HOSTS:-}" ]; then
  LOG_PREFIX INFO "Adding extra hosts from EXTRA_HOSTS: $EXTRA_HOSTS"
  IFS=',' read -ra EXTRA_HOSTS_LIST <<< "$EXTRA_HOSTS"
fi

# merge & dedupe
ALL_HOSTS=("${MDNS_HOSTS[@]}" "${EXTRA_HOSTS_LIST[@]}")
# remove empty entries
ALL_HOSTS=($(printf '%s\n' "${ALL_HOSTS[@]}" | grep -v '^$' | sort -u))

if [ ${#ALL_HOSTS[@]} -eq 0 ]; then
  LOG_PREFIX INFO "No WLED devices found (mdns nor EXTRA_HOSTS)."
  exit 0
fi

LOG_PREFIX INFO "Will back up the following hosts:"
for h in "${ALL_HOSTS[@]}"; do
  echo "  - $h"
done

FAIL=0
for H in "${ALL_HOSTS[@]}"; do
  if ! "$SCRIPT" "$H"; then
    LOG_PREFIX ERROR "Backup script failed for $H"
    FAIL=1
  fi
done

if [ $FAIL -ne 0 ]; then
  LOG_PREFIX ERROR "One or more backups failed."
  exit 2
else
  LOG_PREFIX INFO "All backups completed successfully."
fi
