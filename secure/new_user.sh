#!/bin/bash

: <<'EOF'
Created date: 2026-10-03
Purpose: Create a user following customer requirements.
Caveats: Must be run with root privileges.
Usage:   sudo ./create_user.sh <new_username> <ticket_id>
EOF

# Strict mode options
set -Eeuo pipefail

GROUPNAME="dev_group"

readonly LOG_FILE="/var/log/user_admin.log"
readonly LOG_TAG="user_admin"
readonly REGISTRY="/var/lib/user_admin/issued_users"

# Shared audit logging, safeguards, and compliance checks.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: cannot load lib/common.sh" >&2; exit 1; }

new_user=""             # set after validation; used by the cleanup trap
user_created=false      # true once useradd succeeds
account_locked=false    # true once the account has been locked after a failure

# Function definitions
create_group() {
  local group_name=${1:-}
 
  if [ -z "$group_name" ]; then
    echo "Error: create_group() - No group name passed to function." >&2
    return 1
  fi
 
  # Test groupadd directly; under 'set -e' a bare failure would exit
  # before any custom message could be printed.
  if ! groupadd "$group_name"; then
    die "Group '$group_name' failed to create."
  fi
 
  if getent group "$group_name" > /dev/null; then
    echo "Group '$group_name' created successfully."
  else
    die "Group '$group_name' not found after creation."
  fi
}

#######################
#
# Preconditions
#
#######################

# Require sudo/root privileges
require_root "<new_username> <ticket_id>"

# Require openssl for password generation
command -v openssl > /dev/null || die "openssl is required to generate a password."

# Protect the log file before proceeding with any operations.
protect_log_file

# The registry of issued usernames must exist and be protected before any
# account is created; otherwise the reuse check and the registry write fail.
# Controls: (IA-4, AU-9 | 3.5.5, 3.3.8)
if ! install -d -m 750 "$(dirname "$REGISTRY")" \
   || ! ( umask 027; touch "$REGISTRY" ) || ! chmod 640 "$REGISTRY"; then
  die "Cannot prepare issued-users registry; refusing to continue."
fi

#######################
#
# Failure handling
#
#######################
 
cleanup_on_exit() {
  # If the script fails after the account exists, do not leave it open.
  # Runs on every exit (including die, which an ERR trap would not catch).
  # Controls: (AC-2 | 3.1.1)
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$user_created" = true ] && [ "$account_locked" != true ]; then
    if usermod -L "$new_user" 2>/dev/null; then
      log_event "lock_account" "SUCCESS" "script failed after account creation" || true
    else
      log_event "lock_account" "FAILURE" "could not lock account; lock or remove it manually" || true
    fi
  fi
}
 
trap 'on_error $? $LINENO' ERR
trap cleanup_on_exit EXIT

######################
#
# Validate arguments
#
######################

require_args 2 "$0 <new_username> <ticket_id>" "$@"

new_user=$1
validate_ticket "$2"
validate_username "$new_user"

# Failure condition: User already exists.
if id "$new_user" > /dev/null 2>&1; then
  die "User '$new_user' already exists."
fi

# Validation passed; the target is now safe to record in the audit log.
TARGET="$new_user"

#######################
#
# Compliance checks
#
#######################

# Controls: (SC-13 | 3.13.11)
readonly REQUIRE_FIPS=false   # set true in CUI environments
if [ "$REQUIRE_FIPS" = true ] && [ "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null)" != "1" ]; then
  die "FIPS mode is required but not enabled."
fi

check_time_sync
verify_script_integrity "$0"
log_event "script" "STARTED" "sha256=${SCRIPT_HASH} lib_sha256=${LIB_HASH}"

######################
#
# Check/create group dev_group
#
######################

# Check whether group dev_group exists. If it doesn't, create it.
# Controls: (AC-2 | 3.1.1)
if getent group "$GROUPNAME" > /dev/null; then
  echo "Group '$GROUPNAME' already exists."
else
  echo "Group '$GROUPNAME' does not exist. Creating group $GROUPNAME."
  create_group "$GROUPNAME"
  log_event "create_group" "SUCCESS" "group=${GROUPNAME}"
fi

######################
#
# Add user
#
######################
 
# Prevent Username and UID reuse
# Controls: (IA-4 | 3.5.5)
 
# Check if the username was previously issued, to prevent reuse.
# The registry stores name:uid, so compare against the name field only.
if awk -F: -v u="$new_user" '$1 == u { found = 1 } END { exit !found }' "$REGISTRY"; then
  die "'$new_user' was previously issued and cannot be reused."
fi
 
# Controls: (AC-2 | 3.1.1)
if ! useradd -m -g "$GROUPNAME" "$new_user"; then
  die "useradd failed for '$new_user'."
fi
user_created=true   # from here on, any failure locks the account (cleanup_on_exit)
 
# Add the username and UID to the registry to prevent future reuse.
echo "$new_user:$(id -u "$new_user")" >> "$REGISTRY"   # store name:uid, check names by field 1
log_event "create_user" "SUCCESS" "uid=$(id -u "$new_user") group=${GROUPNAME}"
 
# Show the new user's /etc/passwd entry. The trailing colon in the pattern
# prevents 'cmburns' from also matching 'cmburnside'.
if ! grep "^${new_user}:" /etc/passwd; then
  die "User creation failed: '$new_user' not found in /etc/passwd."
fi

######################
#
# Assign password and force a change at first login
#
######################
 
# Controls: (IA-5(1) | 3.5.9)
temp_pw=$(openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-20)
 
if ! echo "${new_user}:${temp_pw}" | chpasswd \
   || ! chage -d 0 "$new_user"; then
  unset temp_pw
  if usermod -L "$new_user"; then
    account_locked=true
    log_event "lock_account" "SUCCESS" "password setup failed"
    die "Password setup failed; account '$new_user' has been locked."
  else
    die "Password setup failed and '$new_user' could NOT be locked; lock or remove it manually."
  fi
fi
 
log_event "set_temp_password" "SUCCESS" "password expired; change required at first login"
 
# Show password once, then discard. Never write it to the audit log.
# Controls: (IA-5(1) | 3.5.9)
if [ -t 1 ]; then
  echo "Temporary password for '$new_user': $temp_pw"
else
  pw_file=$(umask 077; mktemp /root/temp_pw_XXXXXX)
  echo "$temp_pw" > "$pw_file"
  echo "Temporary password stored in $pw_file (root-only); deliver securely, then delete it."
fi
unset temp_pw
 
echo "User '$new_user' created in group '$GROUPNAME'; password change required at first login."
log_event "script" "COMPLETED"
