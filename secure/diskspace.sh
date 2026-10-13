#!/bin/bash

: <<'EOF'
Created date: 2026-10-10
Purpose: Free disk space by cleaning a list of directories, reporting the
         free space on the root partition before and after.
Caveats: Must be run with root privileges. Non-interactive: the change
         ticket ID is the approval, so the script is safe to schedule.
         Deletion only unlinks files; it is not media sanitization.
Usage:   sudo ./f_diskspace.sh <ticket_id>
EOF

set -Eeuo pipefail

readonly LOG_FILE="/var/log/diskspace_admin.log"
readonly LOG_TAG="diskspace_admin"
readonly THRESHOLD_GB=5

# Entries in a cleaned directory that must survive: live sockets and the
# per-service private temp directories used by systemd.
readonly PRESERVE_PATTERNS=(
  ".X11-unix"
  ".ICE-unix"
  ".font-unix"
  ".XIM-unix"
  ".Test-unix"
  "systemd-private-*"
)

# Shared audit logging, safeguards, and compliance checks.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: cannot load lib/common.sh" >&2; exit 1; }

RESOLVED_DIR=""   # set by validate_clean_dir
failures=0        # directories that could not be fully cleaned

#######################
#
# Requirement F2
#
#######################

# Function: validate_clean_dir()
# Purpose: Resolve symlinks, then refuse system paths and any directory that
# holds the audit log. Sets RESOLVED_DIR. Returns 1 if the directory does not
# exist. A protected path is fatal (die).
# Controls: (AC-6 | 3.1.5)
validate_clean_dir() {
  RESOLVED_DIR=$(realpath -e -- "$1" 2>/dev/null) || return 1

  case "$RESOLVED_DIR" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/usr|/var|/var/lib|/var/log)
      die "Refusing to clean protected path '${RESOLVED_DIR}'." ;;
  esac

  # The audit log must never live under a directory that gets cleaned.
  # Controls: (AU-9 | 3.3.8)
  case "$LOG_FILE" in
    "$RESOLVED_DIR"/*)
      die "Refusing to clean '${RESOLVED_DIR}': it contains the audit log." ;;
  esac
}

# Function: cleanDir()
# Purpose: Clean the specified directory by removing all its contents,
# including hidden files, except the entries in PRESERVE_PATTERNS. The
# directory itself is kept. Returns 1 if anything could not be removed.
# Controls: (SC-4, MP-6 | 3.13.4, 3.8.3)
cleanDir() {
  local dir=${1:-}
  local items pattern
  local -a keep=()

  if [ -z "$dir" ]; then
    echo "Error: cleanDir() - No directory passed to function." >&2
    return 1
  fi

  # Resolve and re-validate immediately before deleting, not just up front.
  if ! validate_clean_dir "$dir"; then
    echo "Directory does not exist: $dir"
    log_event "clean_dir" "WARNING" "directory does not exist"
    return 0
  fi

  for pattern in "${PRESERVE_PATTERNS[@]}"; do
    keep+=( ! -name "$pattern" )
  done

  # Count the top-level entries to be removed (one dot per entry, so odd
  # filenames cannot skew the count).
  items=$(find "$RESOLVED_DIR" -mindepth 1 -maxdepth 1 -xdev "${keep[@]}" -printf '.' | wc -c)

  # --one-file-system keeps rm from descending into other mounts; find lists
  # symlinks as entries, so rm removes the link and never follows it.
  if ! find "$RESOLVED_DIR" -mindepth 1 -maxdepth 1 -xdev "${keep[@]}" \
       -exec rm -rf --one-file-system -- {} +; then
    echo "Error: not everything in '$dir' could be removed." >&2
    log_event "clean_dir" "FAILURE" "some items could not be removed; items_found=${items}"
    return 1
  fi

  echo "Cleaned directory: $dir"
  log_event "clean_dir" "SUCCESS" "items_removed=${items}"
}

# Function: checkSpace()
# Purpose: Check the free space on the root partition and save it as a
# variable. Print a warning if it is below a specified threshold (in GB).
# Return value is the local free_space variable, in bytes. Messages go to
# stderr so that command substitution captures only the number.
# Controls: (AU-4, AU-5 | 3.3.4)
checkSpace() {
  local threshold=$1
  local free_space

  free_space=$(df -B1 --output=avail / | tail -n 1 | tr -d ' ')
  if ! [[ $free_space =~ ^[0-9]+$ ]]; then
    echo "Error: checkSpace() - could not read free space on /." >&2
    return 1
  fi

  echo "Free space on root partition: $(numfmt --to=iec "$free_space")" >&2
  if (( free_space < threshold * 1024**3 )); then
    echo "Warning: Free space on root partition is below $threshold GB." >&2
    log_event "check_space" "WARNING" "free_bytes=${free_space} below ${threshold} GB threshold"
  else
    log_event "check_space" "SUCCESS" "free_bytes=${free_space}"
  fi

  echo "$free_space"
}

#######################
#
# Preconditions
#
#######################

require_root "<ticket_id>"

for cmd in df find realpath numfmt; do
  command -v "$cmd" > /dev/null || die "$cmd is required."
done

protect_log_file

trap 'on_error $? $LINENO' ERR

######################
#
# Validate arguments
#
######################

require_args 1 "$0 <ticket_id>" "$@"
validate_ticket "$1"

# Validation passed; the ticket is recorded. Run-level events target the root
# partition; the clean loops below set TARGET to each directory in turn.
TARGET="/"

#######################
#
# Compliance checks
#
#######################

check_time_sync
verify_script_integrity "$0"
log_event "script" "STARTED" "sha256=${SCRIPT_HASH} lib_sha256=${LIB_HASH}"

#######################
#
# Requirement F1
#
#######################

# Free space on the root partition before cleaning, in bytes.
FREE_SPACE=$(checkSpace "$THRESHOLD_GB")

#######################
#
# Requirement F3
#
#######################

# Declare variable containing a list of directories to be cleaned.
# Controls: (CM-5 | 3.4.5)
# readonly: the list cannot be altered after this point.
readonly DIRS_TO_CLEAN=(
  "/tmp"
  "/var/tmp"
  "$HOME/.cache"
)

# Validate every entry before anything is deleted, so a protected path stops
# the run before any directory is touched. A missing directory is not fatal
# here; cleanDir() reports it.
# Controls: (AC-6 | 3.1.5)
for dir in "${DIRS_TO_CLEAN[@]}"; do
  TARGET="$dir"
  validate_clean_dir "$dir" || true
done
TARGET="/"

#######################
#
# Requirement F4
#
#######################

# Delete all of the files and subdirectories in the specified directories
# using a for loop and the cleanDir function.
# Controls: (AU-2/3/12 | 3.3.1, 3.3.2)
for dir in "${DIRS_TO_CLEAN[@]}"; do
  TARGET="$dir"
  cleanDir "$dir" || failures=$(( failures + 1 ))
done
TARGET="/"

#######################
#
# Requirement F5
#
#######################

# Find the free disk space in the root partition after cleaning. Report any
# amount more than zero. Respond with "No significant disk space was freed"
# if the amount is zero. Compare the difference, not the free space itself.
FREE_SPACE_AFTER_CLEANING=$(checkSpace "$THRESHOLD_GB")
freed=$(( FREE_SPACE_AFTER_CLEANING - FREE_SPACE ))

if [ "$freed" -gt 0 ]; then
  echo "Freed disk space: $(numfmt --to=iec "$freed")"
  log_event "space_freed" "SUCCESS" "freed_bytes=${freed}"
else
  echo "No significant disk space was freed"
  log_event "space_freed" "SUCCESS" "no significant disk space was freed"
fi

if [ "$failures" -gt 0 ]; then
  die "${failures} directory(ies) were not fully cleaned; see the audit log."
fi

log_event "script" "COMPLETED"