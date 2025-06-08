#!/usr/bin/env bash
#
# backup-discover.sh
#   Discovers all WLED instances via avahi-browse and runs backup-one.sh.

set -e

SERVICE="_wled._tcp"
SCRIPT="$(dirname "$0")/backup-one.sh"

if [ ! -x "$SCRIPT" ]; then
  echo "ERROR: backup script not found or not executable."
  exit 1
fi

# Discover hostnames via mDNS
mapfile -t HOSTS < <(
  avahi-browse -r -p "${SERVICE}" --terminate \
    | awk -F';' '/^=/ {print $7}' \
    | sort -u
)

if [ "${#HOSTS[@]}" -eq 0 ]; then
  echo "No WLED devices found."
  exit 0
fi

FAIL=0
for H in "${HOSTS[@]}"; do
  if ! "${SCRIPT}" "$H"; then
    echo "✗ backup failed for $H"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo "One or more backups failed."
  exit 2
fi

echo "All backups completed successfully."
