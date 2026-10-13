#!/bin/bash

: <<'EOF'
Created date: 2026-10-10
Purpose: Archive a directory with gzip, bzip2 and xz, then compare the
         archive sizes, following customer requirements.
Caveats: Must be run with root privileges. Archives hold a full copy of the
         source data. They are stored root-only (0600, in a 0700 directory)
         but are NOT encrypted; encrypt them before they leave this host.
Usage:   sudo ./g_archive_dir_secure.sh <directory_to_archive> <ticket_id>
EOF

set -Eeuo pipefail

readonly LOG_FILE="/var/log/archive_admin.log"
readonly LOG_TAG="archive_admin"
readonly ARCHIVE_DIR="/var/lib/archive_admin/archives"

# Shared audit logging, safeguards, and compliance checks.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: cannot load lib/common.sh" >&2; exit 1; }

# Archives and checksum files are created readable by root only (0600).
# Controls: (AC-3, SC-28 | 3.1.1, 3.1.2, 3.13.16)
umask 077

DIR_TO_ARCHIVE=""   # resolved source path, set by validate_source_dir
PARENT_DIR=""       # parent of the source directory
BASE_NAME=""        # name of the source directory
NEW_ARCHIVE=""      # path of the archive just created by makeArchive
in_progress=""      # archive being written; removed by the exit trap on failure

#######################
#
# Requirement G1
#
#######################

# Function to get the size of a file in bytes.
# Callers must assign the result to a variable first (size=$(fileSize ...)).
# Inside "echo $(...)" a failure here would be masked and print an empty size.
# Controls: (SI-11 | n/a)
fileSize() {
  if [ ! -f "$1" ]; then
    die "File $1 does not exist."
  fi
  stat --format="%s" "$1"
}

# Function: validate_source_dir()
# Purpose: Resolve symlinks and refuse paths that are unsafe to archive: the
# root of the filesystem, pseudo-filesystems, and anything holding or inside
# the archive store. Sets DIR_TO_ARCHIVE, PARENT_DIR and BASE_NAME.
# The rejected input is deliberately NOT echoed: it could carry control
# characters into the terminal and the audit log.
# Controls: (AC-6, SI-10 | 3.1.5)
validate_source_dir() {
  local resolved
  resolved=$(realpath -e -- "$1" 2>/dev/null) || die "Directory does not exist or is not accessible."
  [[ $resolved != *[[:cntrl:]]* ]] || die "Invalid directory path."
  [ -d "$resolved" ] || die "'${resolved}' is not a directory."

  case "$resolved" in
    /|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/run|/run/*)
      die "Refusing to archive '${resolved}'." ;;
  esac

  # The archive store must never be inside the directory being archived,
  # and the store itself is not archived.
  case "$ARCHIVE_DIR" in
    "$resolved"|"$resolved"/*)
      die "Refusing to archive '${resolved}': it contains the archive store." ;;
  esac
  case "$resolved" in
    "$ARCHIVE_DIR"|"$ARCHIVE_DIR"/*)
      die "Refusing to archive the archive store." ;;
  esac

  DIR_TO_ARCHIVE="$resolved"
  PARENT_DIR="$(dirname "$resolved")"
  BASE_NAME="$(basename "$resolved")"
}

# Function: makeArchive()
# Purpose: Create, verify and checksum one archive of the source directory.
# Inputs: $1 - tar compression flag (z = gzip, j = bzip2, J = xz)
#         $2 - archive file extension (tar.gz, tar.bz2, tar.xz)
# Sets NEW_ARCHIVE to the path of the finished archive.
# Controls: (CP-9, SI-7 | 3.8.9)
makeArchive() {
  local flag=$1 ext=$2 archive size hash
  archive="${ARCHIVE_DIR}/${BASE_NAME}_${TIMESTAMP}.${ext}"

  # Never overwrite an existing archive.
  [ ! -e "$archive" ] || die "Archive '$(basename "$archive")' already exists."
  in_progress="$archive"

  # --one-file-system: do not wander into other mounts (NFS, removable media).
  # --numeric-owner:   record UIDs/GIDs, not names that may differ on restore.
  # '--':              a directory named like an option cannot be misread.
  if ! tar "-c${flag}f" "$archive" --one-file-system --numeric-owner \
       -C "$PARENT_DIR" -- "$BASE_NAME"; then
    die "tar failed while creating '$(basename "$archive")'; incomplete archive removed."
  fi

  # Read the whole archive back to prove it is intact before relying on it.
  if ! tar -tf "$archive" > /dev/null; then
    die "Verification failed for '$(basename "$archive")'; archive removed."
  fi

  # Record the checksum next to the archive (check with: sha256sum -c).
  hash=$(sha256sum "$archive" | cut -d' ' -f1)
  echo "${hash}  $(basename "$archive")" > "${archive}.sha256"

  size=$(fileSize "$archive")
  log_event "create_archive" "SUCCESS" "file=$(basename "$archive") bytes=${size} sha256=${hash}"

  in_progress=""
  NEW_ARCHIVE="$archive"
}

#######################
#
# Preconditions
#
#######################

require_root "<directory_to_archive> <ticket_id>"

for cmd in tar gzip bzip2 xz sha256sum realpath du df stat; do
  command -v "$cmd" > /dev/null || die "$cmd is required."
done

protect_log_file

# The archive store must exist and be root-only before any archive is written.
# Controls: (AC-3, MP-4 | 3.1.1, 3.1.2, 3.8.1)
if ! install -d -m 700 "$(dirname "$ARCHIVE_DIR")" "$ARCHIVE_DIR"; then
  die "Cannot prepare archive directory; refusing to continue."
fi

#######################
#
# Failure handling
#
#######################

cleanup_on_exit() {
  # If the script fails mid-archive, do not leave a partial archive behind
  # that could later be mistaken for a good one.
  # Runs on every exit (including die, which an ERR trap would not catch).
  # Controls: (CP-9, SI-11 | 3.8.9)
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$in_progress" ]; then
    rm -f -- "$in_progress" "${in_progress}.sha256" || true
    log_event "remove_partial_archive" "SUCCESS" "incomplete archive removed after failure" || true
  fi
}

trap 'on_error $? $LINENO' ERR
trap cleanup_on_exit EXIT

######################
#
# Validate arguments
#
######################

require_args 2 "$0 <directory_to_archive> <ticket_id>" "$@"
validate_ticket "$2"
validate_source_dir "$1"

# Validation passed; the target is now safe to record in the audit log.
TARGET="$DIR_TO_ARCHIVE"

#######################
#
# Compliance checks
#
#######################

check_time_sync
verify_script_integrity "$0"
log_event "script" "STARTED" "sha256=${SCRIPT_HASH} lib_sha256=${LIB_HASH}"

# One timestamp for the whole run, so all three archives share a name.
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# Make sure the archive store can hold all three archives (worst case: each
# is as large as the source) before starting. A full disk can also stop
# audit logging.
# Controls: (AU-4, AU-5 | 3.3.4)
src_bytes=$(du -sbx "$DIR_TO_ARCHIVE" | cut -f1)
free_bytes=$(df -B1 --output=avail "$ARCHIVE_DIR" | tail -n 1 | tr -d ' ')
[[ $src_bytes =~ ^[0-9]+$ && $free_bytes =~ ^[0-9]+$ ]] || die "Cannot determine space requirements."
if (( free_bytes < src_bytes * 3 )); then
  die "Not enough free space in the archive directory for three archives."
fi

######################
#
# Requirement G2
#
######################

# Archive and compress files and directories in the specified directory using gzip.
makeArchive z tar.gz
ARCHIVE_NAME="$NEW_ARCHIVE"
echo "Directory $DIR_TO_ARCHIVE has been archived and compressed as $ARCHIVE_NAME."
GZIP_SIZE=$(fileSize "$ARCHIVE_NAME")
echo "Archive size: $GZIP_SIZE"

######################
#
# Requirement G3
#
######################

# Archive and compress files and directories in the specified directory using bzip2.
makeArchive j tar.bz2
BZIP2_ARCHIVE_NAME="$NEW_ARCHIVE"
echo "Directory $DIR_TO_ARCHIVE has been archived and compressed as $BZIP2_ARCHIVE_NAME."
BZIP2_SIZE=$(fileSize "$BZIP2_ARCHIVE_NAME")
echo "Archive size: $BZIP2_SIZE"

######################
#
# Archive and compress files and directories in the specified directory using xz.
#
######################

makeArchive J tar.xz
XZ_ARCHIVE_NAME="$NEW_ARCHIVE"
echo "Directory $DIR_TO_ARCHIVE has been archived and compressed as $XZ_ARCHIVE_NAME."
XZ_SIZE=$(fileSize "$XZ_ARCHIVE_NAME")
echo "Archive size: $XZ_SIZE"

######################
#
# Display the sizes of all created archives.
#
######################

echo "Sizes of all created archives:"
echo "Gzip archive: $GZIP_SIZE"
echo "Bzip2 archive: $BZIP2_SIZE"
echo "Xz archive: $XZ_SIZE"

######################
#
# Requirement G4
#
######################

# Display the size difference between the gzip and bzip2 archives using
# fileSize(). Re-read the sizes so the figures reflect the files on disk now.
GZIP_SIZE=$(fileSize "$ARCHIVE_NAME")
BZIP2_SIZE=$(fileSize "$BZIP2_ARCHIVE_NAME")
SIZE_DIFF=$((GZIP_SIZE - BZIP2_SIZE))

######################
#
# Requirement G5
#
######################

echo "Size difference between gzip and bzip2 archives: $SIZE_DIFF bytes"

# Controls: (AU-2/3/12 | 3.3.1, 3.3.2)
log_event "archive_sizes" "SUCCESS" "gzip=${GZIP_SIZE} bzip2=${BZIP2_SIZE} xz=${XZ_SIZE} gzip_minus_bzip2=${SIZE_DIFF}"
log_event "script" "COMPLETED"

# Exit the script
exit 0
