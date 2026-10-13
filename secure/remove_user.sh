#!/bin/bash

: <<'EOF'
Created date: 2026-10-03
Purpose: Delete a user following customer requirements.
Caveats: Must be run with root privileges. Home directory is retained (no -r).
         Deleted usernames stay in the issued-users registry on purpose, so
         they cannot be reissued (IA-4 | 3.5.5).
Usage:   sudo ./delete_user.sh <username> <ticket_id>
EOF
 
set -Eeuo pipefail

readonly LOG_FILE="/var/log/user_admin.log"
readonly LOG_TAG="user_admin"

# Shared audit logging, safeguards, and compliance checks.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: cannot load lib/common.sh" >&2; exit 1; }

deleted_user=""         # set after validation
deleted_uid=""          # recorded before deletion for the audit trail
deleted_home=""         # recorded before deletion for the audit trail

########################
#
# Function definitions
#
########################

offboard_user() {
  local target=$1
  # POSSIBLE FUTURE FUNCTIONALITY: Archive the user's home directory
  # before deleting to meet data retention requirements.
 
  # POSSIBLE FUTURE FUNCTIONALITY: Check whether dev_group is empty and,
  # after prompting for confirmation, delete it.
  # --> Nixed. Deleting an empty group is a separate operation and should be reserved 
  # for a separate script. Group deletion in this context may cause unforeseen issues.
  # Controls: (AC-2 | 3.1.1)
  if userdel -- "$target"; then
    echo "User '$target' deleted successfully."
    log_event "delete_user" "SUCCESS" "uid=${deleted_uid} home=${deleted_home} (home directory retained)"
  else
    die "userdel failed for '$target' (is the user logged in or running processes?)."
  fi
}

#######################
#
# Preconditions
#
#######################

require_root "<username> <ticket_id>"
protect_log_file
trap 'on_error $? $LINENO' ERR

######################
#
# Validate deleted_user and ticket ID arguments
#
######################

require_args 2 "$0 <username> <ticket_id>" "$@"

deleted_user=$1
validate_ticket "$2"
validate_username "$deleted_user"

# The name now matches the safe pattern, so it can be recorded in the audit log.
# Set here (not later) so refusals below are attributable to a target.
TARGET="$deleted_user"
 
# User must exist
if ! id "$deleted_user" >/dev/null 2>&1; then
  die "User '$deleted_user' does not exist."
fi
 
# Record identity details now; they are gone once the account is deleted.
deleted_uid=$(id -u "$deleted_user")
deleted_home=$(getent passwd "$deleted_user" | cut -d: -f6)
 
# Safety guards
# Controls: (AC-2, AC-6 | 3.1.1, 3.1.5)
# Won't delete system/service accounts (UID < 1000)
if [ "$deleted_uid" -lt 1000 ]; then
  die "Refusing to delete '$deleted_user': system account (UID < 1000)."
fi
 
# Won't delete the user running this script (SUDO_USER)
if [ "$deleted_user" = "${SUDO_USER:-}" ]; then
  die "Refusing to delete the user running this script."
fi

#######################
#
# Compliance checks
#
#######################

check_time_sync
verify_script_integrity "$0"
log_event "script" "STARTED" "sha256=${SCRIPT_HASH} lib_sha256=${LIB_HASH}"

######################
#
# Delete user
#
######################
 
# NOTE: the issued-users registry is intentionally NOT modified here. A deleted
# username must stay reserved so it cannot be reissued.
# Controls: (IA-4 | 3.5.5)
echo "Deleting user '$deleted_user'..."
offboard_user "$deleted_user"
 
# Verify the user is actually gone
if getent passwd "$deleted_user" >/dev/null; then
  die "User '$deleted_user' still present after deletion."
fi
 
echo "User '$deleted_user' deleted."
log_event "script" "COMPLETED"
