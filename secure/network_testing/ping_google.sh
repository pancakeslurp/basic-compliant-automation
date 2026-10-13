#!/bin/bash

: <<'DOC'
Created date: 2026-10-07
Purpose: Ping google.com exactly once. Print 'Network is up.' on success, 'No connection.' on failure.
Caveats: Runs unprivileged. Needs outbound ICMP; a firewall that blocks ICMP reports 'No connection.'
Usage:   ./e_ping_google_secure.sh
Exit codes: 0 = test passed, 1 = test failed, 2 = environment/integrity error
Control mapping (NIST SP 800-53 | 800-171) is noted beside each section.
DOC

set -Eeuo pipefail

# Fixed PATH so a planted binary earlier in the user's PATH cannot replace
# ping/nslookup/logger. Controls: (CM-5, SI-7 | 3.4.5)
PATH=/usr/bin:/bin
export PATH

readonly HOST="google.com"
readonly ACTION="ping"
readonly OPERATOR="$(id -un)"
readonly NODE="$(hostname)"

log_event() {
  # Log to syslog via logger. Never log secrets or raw user input.
  # Controls: (AU-2, AU-3, AU-8, AU-12 | 3.3.1, 3.3.2, 3.3.7)
  # Inputs: $1 - result (string), $2 - detail (optional string)
  local result=$1 detail=${2:-}
  local entry
  entry="$(date -u +%Y-%m-%dT%H:%M:%SZ) operator=${OPERATOR} node=${NODE} action=${ACTION} target=${HOST} result=${result}"
  [ -n "$detail" ] && entry+=" detail=\"${detail}\""
  if command -v logger > /dev/null; then
    logger -t net_check -p auth.notice -- "$entry" || echo "$entry" >&2
  else
    # Unlike create_user.sh this does not fail closed: a connectivity check
    # that cannot log still reports, but the gap is visible on stderr.
    echo "$entry" >&2
  fi
}

die() {
  # Controls: (SI-11 | 3.14.1) Generic message to the user, detail to the log.
  echo "ERROR: $*" >&2
  log_event "ERROR" "$*" || true
  exit 2
}

on_error() {
  # Skip command-substitution subshells so each failure is logged once.
  [ "$BASHPID" = "$$" ] || return 0
  log_event "ERROR" "line $2 exit $1" || true
}
trap 'on_error $? $LINENO' ERR

# Least privilege: nothing here needs root, so refuse to run as root.
# Controls: (AC-6 | 3.1.5)
[ "$(id -u)" -ne 0 ] || die "Do not run this script as root."

# Script ownership/permission check and hash logging.
# Controls: (CM-5, SI-7 | 3.4.5)
script_owner=$(stat -c '%U' "$0"); script_mode=$(stat -c '%a' "$0")
{ [ "$script_owner" = "root" ] || [ "$script_owner" = "$OPERATOR" ]; } \
  || die "Script must be owned by root or the invoking user."
(( (8#$script_mode & 8#022) == 0 )) || die "Script must not be group- or world-writable."
log_event "STARTED" "sha256=$(sha256sum "$0" | cut -d' ' -f1)"

# Test connectivity once, capturing output so a failure is logged, not hidden.
# Controls: (SI-4, AU-12 | 3.14.6, 3.3.1)
if out=$(ping -c 1 -W 2 "$HOST" 2>&1); then
  echo "Network is up."
  log_event "SUCCESS"
  exit 0
else
  echo "No connection."
  log_event "FAILURE" "$(printf '%s\n' "$out" | tail -n 1 | tr -d '"')"
  exit 1
fi
