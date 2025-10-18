#!/bin/bash
# ============================================================================
# Moodle VM Disaster Recovery Restore Script
# Industry Standard Restoration Process
# ============================================================================
#
# This script restores Moodle from a backup created by backup-vm.sh
# Supports restoration from:
#   - Local backups (/var/backups/moodle/)
#   - Google Cloud Storage backups
#   - Manual backup archives
#
# What it restores:
#   - Database (MariaDB)
#   - Moodledata directory (user files)
#   - Moodle code (if included in backup)
#   - Configuration files
#
# IMPORTANT: This script will OVERWRITE existing Moodle data
# USE WITH EXTREME CAUTION in production environments
#
# Usage:
#   Interactive mode (select backup):
#     sudo bash restore-vm.sh
#
#   Restore specific backup:
#     sudo bash restore-vm.sh /var/backups/moodle/daily/backup_20250117_020000
#
#   Restore from Google Cloud Storage:
#     sudo bash restore-vm.sh gs://bucket-name/daily/backup_20250117_020000
#
#   Restore with confirmation:
#     sudo bash restore-vm.sh --backup=/path/to/backup --confirm
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Backup directories
BACKUP_ROOT="/var/backups/moodle"

# Moodle directories
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"

# Temporary restoration directory
RESTORE_TEMP="/tmp/moodle-restore-$$"

# Database configuration (from Secret Manager or credentials file)
# Try Secret Manager first (industry standard), fall back to file if unavailable
if command -v get-moodle-secret &> /dev/null; then
    # Use Secret Manager (preferred)
    MOODLE_DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
    MOODLE_DB_USER=$(get-moodle-secret moodle-db-user 2>/dev/null || echo "${MOODLE_DB_USER:-moodle_user}")
    DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
elif [[ -f /root/.moodle-credentials ]]; then
    # Fallback to credentials file (legacy)
    source /root/.moodle-credentials
else
    # Fallback to environment variables
    DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
    MOODLE_DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
    MOODLE_DB_USER="${MOODLE_DB_USER:-moodle_user}"
fi

# Google Cloud Storage
GCS_BUCKET="${MOODLE_BACKUP_BUCKET:-}"

# Log file
LOG_FILE="/var/log/moodle-restore.log"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# CHECK REQUIREMENTS
# ============================================================================

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if MariaDB is running
if ! systemctl is-active --quiet mariadb; then
    error "MariaDB is not running"
    exit 1
fi

# Check if database credentials are available
if [[ -z "$DB_ROOT_PASSWORD" ]]; then
    error "Database root password not found. Run 'sudo bash secrets-manager-setup.sh' or check /root/.moodle-credentials"
    exit 1
fi

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

BACKUP_PATH=""
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup=*)
            BACKUP_PATH="${1#*=}"
            shift
            ;;
        --confirm)
            AUTO_CONFIRM=true
            shift
            ;;
        *)
            # Positional argument (backup path)
            if [[ -z "$BACKUP_PATH" ]]; then
                BACKUP_PATH="$1"
            fi
            shift
            ;;
    esac
done

# ============================================================================
# SELECT BACKUP (INTERACTIVE MODE)
# ============================================================================

if [[ -z "$BACKUP_PATH" ]]; then
    log "============================================"
    log "Moodle Disaster Recovery - Backup Selection"
    log "============================================"
    log ""

    # List available backups
    log "Available local backups:"
    log ""

    BACKUP_LIST=()
    BACKUP_INDEX=1

    # Find all backups (daily, weekly, monthly)
    for backup_type in daily weekly monthly; do
        backup_dir="$BACKUP_ROOT/$backup_type"
        if [[ -d "$backup_dir" ]]; then
            while IFS= read -r backup; do
                if [[ -f "$backup/BACKUP_MANIFEST.txt" ]]; then
                    BACKUP_LIST+=("$backup")

                    # Read manifest info
                    backup_date=$(grep "Backup Date:" "$backup/BACKUP_MANIFEST.txt" | cut -d: -f2- | xargs)
                    backup_size=$(du -sh "$backup" | cut -f1)

                    echo "  [$BACKUP_INDEX] $backup_type - $backup_date ($backup_size)"
                    echo "      Path: $backup"

                    BACKUP_INDEX=$((BACKUP_INDEX + 1))
                fi
            done < <(find "$backup_dir" -maxdepth 1 -type d -name "backup_*" | sort -r)
        fi
    done

    log ""
    log "  [0] Enter custom path (local or GCS)"
    log "  [q] Quit"
    log ""

    read -p "Select backup to restore: " selection

    if [[ "$selection" == "q" ]] || [[ "$selection" == "Q" ]]; then
        log "Restoration cancelled by user"
        exit 0
    elif [[ "$selection" == "0" ]]; then
        read -p "Enter backup path: " BACKUP_PATH
    elif [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -lt $BACKUP_INDEX ]]; then
        BACKUP_PATH="${BACKUP_LIST[$((selection - 1))]}"
    else
        error "Invalid selection"
        exit 1
    fi
fi

# ============================================================================
# VALIDATE BACKUP PATH
# ============================================================================

log "============================================"
log "Validating backup..."
log "============================================"

# Check if it's a GCS path
if [[ "$BACKUP_PATH" =~ ^gs:// ]]; then
    log "Backup source: Google Cloud Storage"
    log "Path: $BACKUP_PATH"

    if ! command -v gsutil &> /dev/null; then
        error "gsutil not installed (required for GCS backups)"
        exit 1
    fi

    # Download backup from GCS
    log "Downloading backup from Cloud Storage..."
    mkdir -p "$RESTORE_TEMP"

    gsutil -m rsync -r "$BACKUP_PATH" "$RESTORE_TEMP/"

    BACKUP_LOCAL_PATH="$RESTORE_TEMP"
else
    # Local backup
    log "Backup source: Local filesystem"
    log "Path: $BACKUP_PATH"

    if [[ ! -d "$BACKUP_PATH" ]]; then
        error "Backup directory not found: $BACKUP_PATH"
        exit 1
    fi

    BACKUP_LOCAL_PATH="$BACKUP_PATH"
fi

# Verify backup manifest exists
if [[ ! -f "$BACKUP_LOCAL_PATH/BACKUP_MANIFEST.txt" ]]; then
    error "Invalid backup: BACKUP_MANIFEST.txt not found"
    exit 1
fi

# Display backup information
log ""
log "Backup Information:"
log "$(cat "$BACKUP_LOCAL_PATH/BACKUP_MANIFEST.txt" | head -20)"
log ""

# ============================================================================
# CONFIRMATION
# ============================================================================

if [[ "$AUTO_CONFIRM" == false ]]; then
    warn "============================================"
    warn "WARNING: This will OVERWRITE existing data!"
    warn "============================================"
    warn ""
    warn "The following will be replaced:"
    warn "  - Database: $MOODLE_DB_NAME"
    warn "  - Moodledata: $MOODLE_DATA"
    warn "  - Configuration files"
    warn ""
    warn "Current Moodle site will be OFFLINE during restore"
    warn ""

    read -p "Are you absolutely sure you want to continue? (type YES to confirm): " confirm

    if [[ "$confirm" != "YES" ]]; then
        log "Restoration cancelled by user"
        exit 0
    fi
fi

# ============================================================================
# PRE-RESTORE BACKUP (SAFETY)
# ============================================================================

log "============================================"
log "Creating safety backup of current state..."
log "============================================"

SAFETY_BACKUP_DIR="/var/backups/moodle/pre-restore-safety-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SAFETY_BACKUP_DIR"

# Quick database dump
log "Backing up current database..."
mysqldump -u root -p"$DB_ROOT_PASSWORD" \
    --single-transaction \
    --quick \
    "$MOODLE_DB_NAME" | gzip > "$SAFETY_BACKUP_DIR/database-pre-restore.sql.gz"

# Backup config.php
if [[ -f "$MOODLE_DIR/config.php" ]]; then
    cp "$MOODLE_DIR/config.php" "$SAFETY_BACKUP_DIR/config.php.backup"
fi

log "Safety backup created: $SAFETY_BACKUP_DIR"

# ============================================================================
# ENABLE MAINTENANCE MODE
# ============================================================================

log "Enabling maintenance mode..."

if [[ -f "$MOODLE_DIR/admin/cli/maintenance.php" ]]; then
    php "$MOODLE_DIR/admin/cli/maintenance.php" --enable || true
fi

# ============================================================================
# STOP WEB SERVER
# ============================================================================

log "Stopping web server..."
systemctl stop apache2 || systemctl stop nginx || true

# ============================================================================
# STEP 1: RESTORE DATABASE
# ============================================================================

log "============================================"
log "Step 1: Restoring database..."
log "============================================"

DB_BACKUP_FILE="$BACKUP_LOCAL_PATH/database.sql.gz"

if [[ ! -f "$DB_BACKUP_FILE" ]]; then
    error "Database backup file not found: $DB_BACKUP_FILE"
    exit 1
fi

# Drop and recreate database
log "Dropping existing database..."
mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS ${MOODLE_DB_NAME};"

log "Creating fresh database..."
mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE ${MOODLE_DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

log "Restoring database from backup..."
RESTORE_START=$(date +%s)

gunzip < "$DB_BACKUP_FILE" | mysql -u root -p"$DB_ROOT_PASSWORD" "$MOODLE_DB_NAME"

RESTORE_END=$(date +%s)
RESTORE_DURATION=$((RESTORE_END - RESTORE_START))

log "Database restored successfully (${RESTORE_DURATION}s)"

# ============================================================================
# STEP 2: RESTORE MOODLEDATA
# ============================================================================

log "============================================"
log "Step 2: Restoring moodledata..."
log "============================================"

MOODLEDATA_BACKUP_FILE="$BACKUP_LOCAL_PATH/moodledata.tar.gz"

if [[ ! -f "$MOODLEDATA_BACKUP_FILE" ]]; then
    error "Moodledata backup file not found: $MOODLEDATA_BACKUP_FILE"
    exit 1
fi

# Backup existing moodledata (move to safety location)
if [[ -d "$MOODLE_DATA" ]]; then
    log "Moving existing moodledata to safety location..."
    mv "$MOODLE_DATA" "$SAFETY_BACKUP_DIR/moodledata-old"
fi

# Extract moodledata
log "Extracting moodledata..."
mkdir -p "$(dirname "$MOODLE_DATA")"
tar xzf "$MOODLEDATA_BACKUP_FILE" -C "$(dirname "$MOODLE_DATA")"

# Recreate cache and sessions directories
mkdir -p "$MOODLE_DATA/cache"
mkdir -p "$MOODLE_DATA/sessions"
mkdir -p "$MOODLE_DATA/temp"
mkdir -p "$MOODLE_DATA/trashdir"

# Set permissions
chown -R www-data:www-data "$MOODLE_DATA"
chmod -R 777 "$MOODLE_DATA"

log "Moodledata restored successfully"

# ============================================================================
# STEP 3: RESTORE CONFIGURATION FILES
# ============================================================================

log "============================================"
log "Step 3: Restoring configuration files..."
log "============================================"

CONFIG_BACKUP_FILE="$BACKUP_LOCAL_PATH/config-files.tar.gz"

if [[ -f "$CONFIG_BACKUP_FILE" ]]; then
    log "Extracting configuration files..."
    tar xzf "$CONFIG_BACKUP_FILE" -C /

    log "Configuration files restored"
else
    warn "Configuration backup not found, skipping"
fi

# ============================================================================
# STEP 4: RESTORE MOODLE CODE (IF PRESENT)
# ============================================================================

log "============================================"
log "Step 4: Checking for Moodle code backup..."
log "============================================"

MOODLE_CODE_BACKUP_FILE="$BACKUP_LOCAL_PATH/moodle-code.tar.gz"

if [[ -f "$MOODLE_CODE_BACKUP_FILE" ]]; then
    warn "Moodle code backup found. Restore it? (y/N): "

    if [[ "$AUTO_CONFIRM" == true ]]; then
        restore_code="N"
    else
        read restore_code
    fi

    if [[ "$restore_code" == "y" ]] || [[ "$restore_code" == "Y" ]]; then
        log "Restoring Moodle code..."

        # Backup existing code
        if [[ -d "$MOODLE_DIR" ]]; then
            mv "$MOODLE_DIR" "$SAFETY_BACKUP_DIR/moodle-code-old"
        fi

        # Extract code
        tar xzf "$MOODLE_CODE_BACKUP_FILE" -C "$(dirname "$MOODLE_DIR")"

        # Restore config.php from config backup (don't overwrite with code backup)
        if [[ -f "$SAFETY_BACKUP_DIR/config.php.backup" ]]; then
            cp "$SAFETY_BACKUP_DIR/config.php.backup" "$MOODLE_DIR/config.php"
        fi

        chown -R www-data:www-data "$MOODLE_DIR"
        chmod -R 755 "$MOODLE_DIR"

        log "Moodle code restored"
    else
        log "Skipping code restoration (using existing code)"
    fi
else
    log "No code backup found (normal for daily/weekly backups)"
fi

# ============================================================================
# STEP 5: CLEAR MOODLE CACHE
# ============================================================================

log "============================================"
log "Step 5: Clearing Moodle cache..."
log "============================================"

if [[ -f "$MOODLE_DIR/admin/cli/purge_caches.php" ]]; then
    sudo -u www-data php "$MOODLE_DIR/admin/cli/purge_caches.php"
    log "Cache purged"
else
    warn "Cache purge script not found, skipping"
fi

# ============================================================================
# STEP 6: FIX PERMISSIONS
# ============================================================================

log "============================================"
log "Step 6: Fixing permissions..."
log "============================================"

chown -R www-data:www-data "$MOODLE_DIR"
chown -R www-data:www-data "$MOODLE_DATA"
chmod -R 755 "$MOODLE_DIR"
chmod -R 777 "$MOODLE_DATA"

log "Permissions fixed"

# ============================================================================
# STEP 7: START WEB SERVER
# ============================================================================

log "Starting web server..."
systemctl start apache2 || systemctl start nginx || true

# ============================================================================
# STEP 8: DISABLE MAINTENANCE MODE
# ============================================================================

log "Disabling maintenance mode..."

if [[ -f "$MOODLE_DIR/admin/cli/maintenance.php" ]]; then
    sudo -u www-data php "$MOODLE_DIR/admin/cli/maintenance.php" --disable || true
fi

# ============================================================================
# CLEANUP
# ============================================================================

if [[ "$BACKUP_PATH" =~ ^gs:// ]]; then
    log "Cleaning up temporary files..."
    rm -rf "$RESTORE_TEMP"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Restoration Complete!"
log "============================================"
log ""
log "Restored from: $BACKUP_PATH"
log ""
log "What was restored:"
log "  ✓ Database ($MOODLE_DB_NAME)"
log "  ✓ Moodledata ($MOODLE_DATA)"
log "  ✓ Configuration files"
if [[ -f "$MOODLE_CODE_BACKUP_FILE" ]] && [[ "$restore_code" == "y" ]]; then
    log "  ✓ Moodle code"
fi
log ""
log "Safety backup location: $SAFETY_BACKUP_DIR"
log "(Keep for at least 24 hours in case rollback is needed)"
log ""
log "Next steps:"
log "  1. Test Moodle site functionality"
log "  2. Verify user data and courses"
log "  3. Check error logs for any issues"
log "  4. Remove safety backup after confirmation"
log ""
log "============================================"

exit 0
