#!/usr/bin/env bash
# lib/common.sh - shared audit logging, security safeguards, and compliance
# checks for the admin scripts.
#
# Source this file; do not execute it.
# The calling script must define these BEFORE sourcing:
#   LOG_FILE - audit log path  (e.g. /var/log/user_admin.log)
#   LOG_TAG  - syslog tag      (e.g. user_admin)

# Guard against double-sourcing and direct execution
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "common.sh is a library; source it instead." >&2
  exit 1
fi

: "${LOG_FILE:?LOG_FILE must be set before sourcing common.sh}"
: "${LOG_TAG:?LOG_TAG must be set before sourcing common.sh}"

#######################
#
# Shared state
#
#######################

readonly OPERATOR="${SUDO_USER:-root}"
TARGET="unvalidated"; TICKET="unvalidated"   # set only after validation passes
SCRIPT_HASH=""; LIB_HASH=""                  # set by verify_script_integrity

#######################
#
# Audit logging
#
#######################

log_event() {
  # Log an event to both the log file and the system logger.
  # Controls: (AU-2/3/12, AC-2(4), AC-6(9) | 3.3.1, 3.3.2)

  # Inputs:
  #   $1 - action (string)
  #   $2 - result (string)
  #   $3 - detail (optional string)
  local action=$1 result=$2 detail=${3:-}

  # Set log entry with timestamp, operator, action, target, ticket, and result.
  local entry="$(date -u +%Y-%m-%dT%H:%M:%SZ) operator=${OPERATOR} action=${action} target=${TARGET} ticket=${TICKET} result=${result}"
  [ -n "$detail" ] && entry+=" detail=\"${detail}\""
  # Append entry, do not overwrite existing log content.
  echo "$entry" >> "$LOG_FILE"
  # Send the log entry to the system logger as well.
  command -v logger > /dev/null && logger -t "$LOG_TAG" -p auth.notice -- "$entry" || true
}

die() {
  # Display error message, record it in the audit log if the log is ready,
  # then exit with status 1
  echo "ERROR: $*" >&2
  [ -w "$LOG_FILE" ] && log_event "die" "FAILURE" "$*" || true
  exit 1
}

on_error() {
  # Record unexpected failures (a failed command under set -e).
  # Install with: trap 'on_error $? $LINENO' ERR   (requires set -E)
  # With set -E, command-substitution subshells inherit this trap too; skip
  # them so each failure is logged once.
  # Inputs: $1 - exit code, $2 - line number
  [ "$BASHPID" = "$$" ] || return 0
  log_event "script" "FAILURE" "line $2 exit $1" || true
}

#######################
#
# Security safeguards
#
#######################

require_root() {
  # Confirm script is run as root.
  # Controls: (AC-6 | 3.1.5)
  # Inputs: $1 - argument synopsis for the hint, e.g. "<username> <ticket_id>"
  if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root (try: sudo $0 ${1:-})."
  fi
}

protect_log_file() {
  # If the event cannot be logged, the script will refuse to continue.
  # Controls: (AU-9 | 3.3.8, 3.3.9)
  if ! ( umask 027; touch "$LOG_FILE" ) || ! chmod 640 "$LOG_FILE"; then
    die "Cannot prepare audit log; refusing to continue."
  fi
}

verify_script_integrity() {
  # Verify that the calling script and this library are owned by root and
  # not group- or world-writable, then record their hashes.
  # Controls: (CM-5, SI-7 | 3.4.5)
  # Inputs: $1 - path of the calling script (pass "$0")
  local f owner mode
  for f in "$1" "${BASH_SOURCE[0]}"; do
    owner=$(stat -c '%U' "$f"); mode=$(stat -c '%a' "$f")
    [ "$owner" = "root" ] || die "$(basename "$f") must be owned by root."
    (( (8#$mode & 8#022) == 0 )) || die "$(basename "$f") must not be group- or world-writable."
  done
  SCRIPT_HASH=$(sha256sum "$1" | cut -d' ' -f1)
  LIB_HASH=$(sha256sum "${BASH_SOURCE[0]}" | cut -d' ' -f1)
}

#######################
#
# Input validation
#
#######################

require_args() {
  # Inputs: $1 - expected argument count, $2 - usage string, remaining - "$@"
  local expected=$1 usage=$2 arg; shift 2
  [ $# -eq "$expected" ] || die "Wrong number of arguments. Usage: $usage"
  for arg in "$@"; do
    [ -n "$arg" ] || die "Empty argument. Usage: $usage"
  done
}

validate_ticket() {
  # Verify that a valid ticket ID was passed, then record it for the audit log.
  # Controls: (CM-3, CM-4 | 3.4.3, 3.4.4)
  # In real life, you would check the ticket ID against a change management
  # system like JIRA, ServiceNow, etc.
  local ticket_re='^[A-Za-z0-9._-]{3,40}$'
  [[ $1 =~ $ticket_re ]] || die "Invalid change ticket ID format."
  TICKET=$1
}

validate_username() {
  # Must begin with a letter; letters, numbers, underscores and hyphens only;
  # max 32 characters (the common Linux limit).
  # The rejected input is deliberately NOT echoed: it could carry control
  # characters into the terminal and the audit log.
  [[ $1 =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] && [ "${#1}" -le 32 ] \
    || die "Invalid username format."
}

#######################
#
# Compliance checks
#
#######################

check_time_sync() {
  # Controls: (AU-8 | 3.3.7)
  [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] \
    || log_event "verify_datetime_sync" "WARNING" "clock not NTP-synchronized"
}
