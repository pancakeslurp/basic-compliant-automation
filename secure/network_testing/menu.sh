#!/bin/bash

: <<'DOC'
Created date: 2026-10-07
Purpose: Main menu for the three network connectivity test scripts (req. E).
Caveats: Interactive; for scheduled runs call the three scripts directly.
Usage:   ./req_e_menu_secure.sh
Control mapping (NIST SP 800-53 | 800-171) is noted beside each section.
DOC

set -Euo pipefail

PATH=/usr/bin:/bin
export PATH

readonly OPERATOR="$(id -un)"
readonly NODE="$(hostname)"
dir="$(cd "$(dirname "$0")" && pwd)"
user_exit=0

log_event() {
  # Controls: (AU-2, AU-3, AU-12 | 3.3.1, 3.3.2)
  local entry
  entry="$(date -u +%Y-%m-%dT%H:%M:%SZ) operator=${OPERATOR} node=${NODE} action=menu result=$1 detail=\"$2\""
  if command -v logger > /dev/null; then
    logger -t net_check -p auth.notice -- "$entry" || echo "$entry" >&2
  else
    echo "$entry" >&2
  fi
}

run_check() {
  # Run one child script only if it exists, is executable, and is not
  # group/world-writable (the menu runs it, so a writable child is an
  # escalation path). Controls: (CM-5, SI-7 | 3.4.5)
  local script="$dir/$1" mode rc=0
  if [ ! -x "$script" ]; then
    echo "Cannot run $1: missing or not executable."
    log_event "ERROR" "$1 missing or not executable"
    return 0
  fi
  mode=$(stat -c '%a' "$script")
  if (( (8#$mode & 8#022) != 0 )); then
    echo "Refusing to run $1: group- or world-writable."
    log_event "ERROR" "$1 has unsafe permissions"
    return 0
  fi
  echo "Running $1..."
  "$script" || rc=$?
  log_event "RAN" "$1 exit=$rc"
}

log_event "STARTED" "sha256=$(sha256sum "$0" | cut -d' ' -f1)"

until [ "$user_exit" -eq 1 ]; do
  echo "Network testing main menu:"
  echo "1. ping_google.sh: Ping google.com"
  echo "2. ping_google_dns.sh: Ping Google DNS server (8.8.8.8)"
  echo "3. resolve_example_dns.sh: Resolve IP address for example.com via DNS"
  echo "4. quit"
  echo
  # EOF on stdin (Ctrl-D) exits cleanly instead of looping.
  if ! read -r -p "Enter selection> " user_selection; then
    echo; user_selection=4
  fi

  # Controls: (SI-10 | 3.14.1) only exact known values are accepted.
  case "$user_selection" in
    1) run_check ping_google.sh ;;
    2) run_check ping_google_dns.sh ;;
    3) run_check resolve_example_dns.sh ;;
    4) echo "Exiting..."; user_exit=1 ;;
    *) echo "Invalid selection. Please try again."
       log_event "INVALID" "unrecognized menu input" ;;
  esac
  echo
done
log_event "COMPLETED" "menu exited"
