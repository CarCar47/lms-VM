#!/bin/bash
# ============================================================================
# Moodle VM Automated Backup Script
# Industry Standard Backup Solution
# ============================================================================
#
# This script performs comprehensive backups of Moodle installation:
#   - Database (MariaDB dump)
#   - Moodledata directory (user files, cache, sessions)
#   - Moodle code directory (optional - usually not needed)
#   - Configuration files
#
# Backup Strategy (3-2-1 Rule):
#   - 3 copies of data (original + 2 backups)
#   - 2 different storage types (local disk + cloud storage)
#   - 1 offsite backup (Google Cloud Storage)
#
# Retention Policy:
#   - Daily backups: Keep 7 days
#   - Weekly backups: Keep 4 weeks
#   - Monthly backups: Keep 12 months
#
# Usage:
#   Manual backup:
#     sudo bash backup-vm.sh
#
#   Install cron job (automatic daily backups):
#     sudo bash backup-vm.sh --install-cron
#
#   Restore from backup:
#     See restore-vm.sh script
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Backup directories
BACKUP_ROOT="/var/backups/moodle"
BACKUP_DIR_DAILY="$BACKUP_ROOT/daily"
BACKUP_DIR_WEEKLY="$BACKUP_ROOT/weekly"
BACKUP_DIR_MONTHLY="$BACKUP_ROOT/monthly"

# Moodle directories
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"

# Database configuration (from Secret Manager or credentials file)
# Try Secret Manager first (industry standard), fall back to file if unavailable
if command -v get-moodle-secret &> /dev/null; then
    # Use Secret Manager (preferred)
    MOODLE_DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
    MOODLE_DB_USER=$(get-moodle-secret moodle-db-user 2>/dev/null || echo "${MOODLE_DB_USER:-moodle_user}")
    MOODLE_DB_PASSWORD=$(get-moodle-secret moodle-db-password 2>/dev/null || echo "${MOODLE_DB_PASSWORD:-}")
    DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
elif [[ -f /root/.moodle-credentials ]]; then
    # Fallback to credentials file (legacy)
    source /root/.moodle-credentials
else
    # Fallback to environment variables
    DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
    MOODLE_DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
    MOODLE_DB_USER="${MOODLE_DB_USER:-moodle_user}"
    MOODLE_DB_PASSWORD="${MOODLE_DB_PASSWORD:-}"
fi

# Google Cloud Storage bucket (for offsite backups)
# Set to empty to disable cloud backups
GCS_BUCKET="${MOODLE_BACKUP_BUCKET:-}"
GCS_REGION="${GCP_REGION:-us-central1}"

# Retention periods (days)
RETENTION_DAILY=7
RETENTION_WEEKLY=28   # 4 weeks
RETENTION_MONTHLY=365 # 12 months

# Compression
COMPRESSION_LEVEL=6  # 1-9 (1=fast, 9=best compression)

# Notification email (optional)
NOTIFICATION_EMAIL="${BACKUP_NOTIFICATION_EMAIL:-}"

# Log file
LOG_FILE="/var/log/moodle-backup.log"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
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
if [[ -z "$DB_ROOT_PASSWORD" ]] && [[ -z "$MOODLE_DB_PASSWORD" ]]; then
    error "Database credentials not found. Run 'sudo bash secrets-manager-setup.sh' or check /root/.moodle-credentials"
    exit 1
fi

# ============================================================================
# INSTALL CRON JOB (if --install-cron flag is used)
# ============================================================================

if [[ "${1:-}" == "--install-cron" ]]; then
    log "Installing cron job for automated daily backups..."

    # Create cron job (runs daily at 2 AM)
    cat > /etc/cron.d/moodle-backup << EOF
# Moodle automated backup - runs daily at 2 AM
0 2 * * * root /bin/bash $(readlink -f "$0") >> $LOG_FILE 2>&1
EOF

    chmod 644 /etc/cron.d/moodle-backup

    log "Cron job installed successfully"
    log "Backups will run daily at 2:00 AM"
    log "Log file: $LOG_FILE"

    exit 0
fi

# ============================================================================
# INITIALIZE BACKUP
# ============================================================================

log "============================================"
log "Starting Moodle Backup"
log "============================================"

# Create backup directories
mkdir -p "$BACKUP_DIR_DAILY"
mkdir -p "$BACKUP_DIR_WEEKLY"
mkdir -p "$BACKUP_DIR_MONTHLY"

# Determine backup type and directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DAY_OF_WEEK=$(date +%u)   # 1-7 (1=Monday)
DAY_OF_MONTH=$(date +%d)  # 1-31

if [[ "$DAY_OF_MONTH" == "01" ]]; then
    # First day of month = monthly backup
    BACKUP_TYPE="monthly"
    BACKUP_DIR="$BACKUP_DIR_MONTHLY"
    RETENTION_DAYS=$RETENTION_MONTHLY
elif [[ "$DAY_OF_WEEK" == "7" ]]; then
    # Sunday = weekly backup
    BACKUP_TYPE="weekly"
    BACKUP_DIR="$BACKUP_DIR_WEEKLY"
    RETENTION_DAYS=$RETENTION_WEEKLY
else
    # All other days = daily backup
    BACKUP_TYPE="daily"
    BACKUP_DIR="$BACKUP_DIR_DAILY"
    RETENTION_DAYS=$RETENTION_DAILY
fi

log "Backup type: $BACKUP_TYPE"
log "Backup directory: $BACKUP_DIR"
log "Retention period: $RETENTION_DAYS days"

# Create dated backup subdirectory
BACKUP_SUBDIR="$BACKUP_DIR/backup_$TIMESTAMP"
mkdir -p "$BACKUP_SUBDIR"

# Track backup size and timing
BACKUP_START_TIME=$(date +%s)

# ============================================================================
# STEP 1: BACKUP DATABASE
# ============================================================================

log "Step 1: Backing up database ($MOODLE_DB_NAME)..."

DB_BACKUP_FILE="$BACKUP_SUBDIR/database.sql.gz"

# Use root password if available, otherwise use moodle user password
if [[ -n "$DB_ROOT_PASSWORD" ]]; then
    mysqldump -u root -p"$DB_ROOT_PASSWORD" \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --routines \
        --triggers \
        --events \
        "$MOODLE_DB_NAME" | gzip -$COMPRESSION_LEVEL > "$DB_BACKUP_FILE"
else
    mysqldump -u "$MOODLE_DB_USER" -p"$MOODLE_DB_PASSWORD" \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --routines \
        --triggers \
        --events \
        "$MOODLE_DB_NAME" | gzip -$COMPRESSION_LEVEL > "$DB_BACKUP_FILE"
fi

DB_SIZE=$(du -h "$DB_BACKUP_FILE" | cut -f1)
log "Database backup complete: $DB_SIZE"

# ============================================================================
# STEP 2: BACKUP MOODLEDATA
# ============================================================================

log "Step 2: Backing up moodledata directory..."

# Exclude cache and sessions from backup (can be regenerated)
MOODLEDATA_BACKUP_FILE="$BACKUP_SUBDIR/moodledata.tar.gz"

tar czf "$MOODLEDATA_BACKUP_FILE" \
    --exclude="$MOODLE_DATA/cache" \
    --exclude="$MOODLE_DATA/sessions" \
    --exclude="$MOODLE_DATA/temp" \
    --exclude="$MOODLE_DATA/trashdir" \
    -C "$(dirname "$MOODLE_DATA")" \
    "$(basename "$MOODLE_DATA")"

MOODLEDATA_SIZE=$(du -h "$MOODLEDATA_BACKUP_FILE" | cut -f1)
log "Moodledata backup complete: $MOODLEDATA_SIZE"

# ============================================================================
# STEP 3: BACKUP MOODLE CODE (OPTIONAL)
# ============================================================================

# Only backup code on monthly backups (rarely changes)
if [[ "$BACKUP_TYPE" == "monthly" ]]; then
    log "Step 3: Backing up Moodle code directory (monthly only)..."

    MOODLE_CODE_BACKUP_FILE="$BACKUP_SUBDIR/moodle-code.tar.gz"

    tar czf "$MOODLE_CODE_BACKUP_FILE" \
        --exclude="$MOODLE_DIR/config.php" \
        -C "$(dirname "$MOODLE_DIR")" \
        "$(basename "$MOODLE_DIR")"

    CODE_SIZE=$(du -h "$MOODLE_CODE_BACKUP_FILE" | cut -f1)
    log "Moodle code backup complete: $CODE_SIZE"
else
    log "Step 3: Skipping code backup (not monthly)"
fi

# ============================================================================
# STEP 4: BACKUP CONFIGURATION FILES
# ============================================================================

log "Step 4: Backing up configuration files..."

CONFIG_BACKUP_FILE="$BACKUP_SUBDIR/config-files.tar.gz"

tar czf "$CONFIG_BACKUP_FILE" \
    "$MOODLE_DIR/config.php" \
    /etc/apache2/sites-available/* \
    /etc/mysql/mariadb.conf.d/99-moodle.cnf \
    /etc/php/*/apache2/conf.d/99-moodle.ini \
    /root/.moodle-credentials \
    2>/dev/null || true

CONFIG_SIZE=$(du -h "$CONFIG_BACKUP_FILE" | cut -f1)
log "Configuration files backup complete: $CONFIG_SIZE"

# ============================================================================
# STEP 5: CREATE BACKUP MANIFEST
# ============================================================================

log "Step 5: Creating backup manifest..."

MANIFEST_FILE="$BACKUP_SUBDIR/BACKUP_MANIFEST.txt"

cat > "$MANIFEST_FILE" << EOF
# ============================================================================
# Moodle Backup Manifest
# Generated: $(date)
# ============================================================================

Backup Type: $BACKUP_TYPE
Backup Date: $(date +'%Y-%m-%d %H:%M:%S')
Timestamp: $TIMESTAMP

Database:
  Name: $MOODLE_DB_NAME
  File: database.sql.gz
  Size: $DB_SIZE

Moodledata:
  Path: $MOODLE_DATA
  File: moodledata.tar.gz
  Size: $MOODLEDATA_SIZE

Configuration:
  File: config-files.tar.gz
  Size: $CONFIG_SIZE

$(if [[ "$BACKUP_TYPE" == "monthly" ]]; then
    echo "Moodle Code:"
    echo "  Path: $MOODLE_DIR"
    echo "  File: moodle-code.tar.gz"
    echo "  Size: $CODE_SIZE"
fi)

System Info:
  Hostname: $(hostname)
  OS: $(lsb_release -d | cut -f2)
  Kernel: $(uname -r)
  PHP: $(php -v | head -n1)
  MariaDB: $(mysql --version | awk '{print $5}' | cut -d- -f1)

Restore Instructions:
  See restore-vm.sh script in /opt/moodle-deployment/
EOF

log "Manifest created"

# ============================================================================
# STEP 6: CALCULATE TOTAL BACKUP SIZE
# ============================================================================

TOTAL_SIZE=$(du -sh "$BACKUP_SUBDIR" | cut -f1)
BACKUP_END_TIME=$(date +%s)
BACKUP_DURATION=$((BACKUP_END_TIME - BACKUP_START_TIME))
BACKUP_DURATION_MIN=$((BACKUP_DURATION / 60))

log "Total backup size: $TOTAL_SIZE"
log "Backup duration: ${BACKUP_DURATION_MIN}m ${BACKUP_DURATION}s"

# ============================================================================
# STEP 7: UPLOAD TO GOOGLE CLOUD STORAGE (OFFSITE BACKUP)
# ============================================================================

if [[ -n "$GCS_BUCKET" ]]; then
    log "Step 7: Uploading to Google Cloud Storage..."

    # Check if gsutil is installed
    if command -v gsutil &> /dev/null; then
        # Create bucket if it doesn't exist
        if ! gsutil ls "gs://$GCS_BUCKET" &> /dev/null; then
            log "Creating GCS bucket: $GCS_BUCKET"
            gsutil mb -l "$GCS_REGION" "gs://$GCS_BUCKET"
            gsutil lifecycle set - "gs://$GCS_BUCKET" << 'LIFECYCLE_EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["daily/", "weekly/"]
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 365,
          "matchesPrefix": ["monthly/"]
        }
      }
    ]
  }
}
LIFECYCLE_EOF
        fi

        # Upload backup directory
        gsutil -m rsync -r "$BACKUP_SUBDIR" "gs://$GCS_BUCKET/$BACKUP_TYPE/backup_$TIMESTAMP/"

        log "Backup uploaded to gs://$GCS_BUCKET/$BACKUP_TYPE/backup_$TIMESTAMP/"
    else
        log "WARNING: gsutil not installed, skipping cloud backup"
    fi
else
    log "Step 7: Skipping cloud backup (GCS_BUCKET not configured)"
fi

# ============================================================================
# STEP 8: CLEANUP OLD BACKUPS
# ============================================================================

log "Step 8: Cleaning up old backups..."

# Daily backups
OLD_DAILY_COUNT=$(find "$BACKUP_DIR_DAILY" -maxdepth 1 -type d -mtime +$RETENTION_DAILY -name "backup_*" | wc -l)
if [[ $OLD_DAILY_COUNT -gt 0 ]]; then
    find "$BACKUP_DIR_DAILY" -maxdepth 1 -type d -mtime +$RETENTION_DAILY -name "backup_*" -exec rm -rf {} \;
    log "Deleted $OLD_DAILY_COUNT old daily backup(s)"
fi

# Weekly backups
OLD_WEEKLY_COUNT=$(find "$BACKUP_DIR_WEEKLY" -maxdepth 1 -type d -mtime +$RETENTION_WEEKLY -name "backup_*" | wc -l)
if [[ $OLD_WEEKLY_COUNT -gt 0 ]]; then
    find "$BACKUP_DIR_WEEKLY" -maxdepth 1 -type d -mtime +$RETENTION_WEEKLY -name "backup_*" -exec rm -rf {} \;
    log "Deleted $OLD_WEEKLY_COUNT old weekly backup(s)"
fi

# Monthly backups
OLD_MONTHLY_COUNT=$(find "$BACKUP_DIR_MONTHLY" -maxdepth 1 -type d -mtime +$RETENTION_MONTHLY -name "backup_*" | wc -l)
if [[ $OLD_MONTHLY_COUNT -gt 0 ]]; then
    find "$BACKUP_DIR_MONTHLY" -maxdepth 1 -type d -mtime +$RETENTION_MONTHLY -name "backup_*" -exec rm -rf {} \;
    log "Deleted $OLD_MONTHLY_COUNT old monthly backup(s)"
fi

# ============================================================================
# STEP 9: SEND NOTIFICATION (OPTIONAL)
# ============================================================================

if [[ -n "$NOTIFICATION_EMAIL" ]] && command -v sendmail &> /dev/null; then
    log "Step 9: Sending notification email..."

    sendmail "$NOTIFICATION_EMAIL" << EOF
Subject: Moodle Backup Complete - $(hostname)
From: moodle-backup@$(hostname)
To: $NOTIFICATION_EMAIL

Moodle backup completed successfully.

Backup Type: $BACKUP_TYPE
Date: $(date +'%Y-%m-%d %H:%M:%S')
Duration: ${BACKUP_DURATION_MIN} minutes

Backup Size: $TOTAL_SIZE
Location: $BACKUP_SUBDIR
$(if [[ -n "$GCS_BUCKET" ]]; then echo "Cloud Backup: gs://$GCS_BUCKET/$BACKUP_TYPE/backup_$TIMESTAMP/"; fi)

Database: $DB_SIZE
Moodledata: $MOODLEDATA_SIZE
Config: $CONFIG_SIZE

Status: SUCCESS
EOF

    log "Notification sent to $NOTIFICATION_EMAIL"
else
    log "Step 9: Skipping email notification (not configured)"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Backup Complete!"
log "============================================"
log "Backup type: $BACKUP_TYPE"
log "Location: $BACKUP_SUBDIR"
log "Total size: $TOTAL_SIZE"
log "Duration: ${BACKUP_DURATION_MIN}m ${BACKUP_DURATION}s"
log ""
log "Backup Contents:"
log "  - Database: $DB_SIZE"
log "  - Moodledata: $MOODLEDATA_SIZE"
log "  - Config files: $CONFIG_SIZE"
if [[ "$BACKUP_TYPE" == "monthly" ]]; then
    log "  - Moodle code: $CODE_SIZE"
fi
log ""
if [[ -n "$GCS_BUCKET" ]]; then
    log "Cloud backup: gs://$GCS_BUCKET/$BACKUP_TYPE/backup_$TIMESTAMP/"
fi
log "============================================"

exit 0
