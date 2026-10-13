#!/bin/bash

: <<'EOF'
Created date: 2026-10-06
Purpose: Install vim (if not already installed) and apply all available
         package updates via dnf, under a change ticket, with an audit trail.
Caveats: Must be run with root privileges. Script must be root-owned and not
         group- or world-writable. Updates should be validated in a test
         environment before this runs in production (CM-3, CM-4).
Usage:   sudo ./d_package_management.sh <ticket_id>
EOF

set -Eeuo pipefail

readonly PACKAGE="vim-enhanced"
readonly LOG_FILE="/var/log/pkg_admin.log"
readonly LOG_TAG="pkg_admin"
readonly UPDATE_LOG="$SCRIPT_DIR/update.log"

# Shared audit logging, safeguards, and compliance checks.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: cannot load lib/common.sh" >&2; exit 1; }

#######################
#
# Preconditions
#
#######################

require_root "<ticket_id>"
protect_log_file
trap 'on_error $? $LINENO' ERR

#######################
#
# Verify Ticket ID
#
#######################

require_args 1 "$0 <ticket_id>" "$@"
validate_ticket "$1"
TARGET="$PACKAGE"

#######################
#
# Compliance checks
#
#######################

check_time_sync
verify_script_integrity "$0"

# Package signature verification must not be disabled.
# Controls: (SI-7, SR-3 | 3.14.1)
readonly REQUIRE_REPO_GPGCHECK=false   # set true in CUI environments
if grep -rEqs '^\s*gpgcheck\s*=\s*0' /etc/dnf/dnf.conf /etc/yum.repos.d/; then
  die "gpgcheck is disabled in dnf configuration; refusing to continue."
fi

# repo_gpgcheck=0 (metadata signing) is common, so warn unless the
# environment requires it.
if grep -rEqs '^\s*repo_gpgcheck\s*=\s*0' /etc/dnf/dnf.conf /etc/yum.repos.d/; then
  if [ "$REQUIRE_REPO_GPGCHECK" = true ]; then
    die "repo_gpgcheck is disabled in dnf configuration; refusing to continue."
  fi
  log_event "verify_gpgcheck" "WARNING" "repo_gpgcheck=0 found in dnf configuration"
fi

log_event "script" "STARTED" "sha256=${SCRIPT_HASH} lib_sha256=${LIB_HASH}"

# Remember the last dnf transaction before this run changes anything.
# Controls: (CM-2, CM-3 | 3.4.1, 3.4.3)
txn_before=$(dnf history info last 2>/dev/null | grep -m1 'Transaction ID' || true)

#######################
#
# Install Vim
#
#######################
 
# Controls: (CM-2, CM-7, CM-11, CM-8 | 3.4.1, 3.4.6, 3.4.9)
if ! rpm -q "$PACKAGE" > /dev/null 2>&1; then
  echo "Vim is not installed. Installing..."
  log_event "install_package" "STARTED"
  dnf install -y "$PACKAGE"
  log_event "install_package" "SUCCESS" "$(rpm -q "$PACKAGE")"
else
  echo "Vim is already installed."
  log_event "install_package" "SKIPPED" "already installed: $(rpm -q "$PACKAGE")"
fi
 
#######################
#
# Install Updates
#
#######################
 
# Controls: (SI-2 | 3.14.1)
TARGET="all-packages"
log_event "update_packages" "STARTED"
dnf update -y 2>&1 | tee -a "$UPDATE_LOG"
log_event "update_packages" "SUCCESS" "output saved to $UPDATE_LOG"

#######################
#
# Record dnf transaction ID for rollback tracing
#
#######################
 
# Controls: (CM-2, CM-3 | 3.4.1, 3.4.3)
txn=$(dnf history info last 2>/dev/null | grep -m1 'Transaction ID' || true)
[ -n "$txn" ] && [ "$txn" = "$txn_before" ] && txn="no new transaction"
log_event "dnf_history" "SUCCESS" "${txn:-transaction id unavailable}"
 
#######################
#
# Record whether a reboot is required
#
#######################
 
# Controls: (SI-2 | 3.14.1)
if ! dnf needs-restarting --help > /dev/null 2>&1; then
  log_event "reboot_check" "WARNING" "needs-restarting unavailable (install dnf-plugins-core)"
elif dnf needs-restarting -r > /dev/null 2>&1; then
  log_event "reboot_check" "SUCCESS" "reboot not required"
else
  echo "A reboot is required to finish updates."
  log_event "reboot_check" "WARNING" "reboot required"
fi
 
log_event "script" "COMPLETED"
