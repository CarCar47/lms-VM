#!/bin/bash
# ============================================================================
# Moodle VM - Backup Validation Script
# Industry Standard: 3-2-1 Backup Rule & Disaster Recovery Testing
# ============================================================================
#
# This script validates Moodle backups to ensure they can be successfully
# restored when needed. Following the principle: "Backups are useless if
# you can't restore them."
#
# INDUSTRY STANDARDS FOLLOWED:
#   - 3-2-1 Backup Rule (3 copies, 2 media types, 1 offsite)
#   - Regular restore testing (quarterly minimum)
#   - Backup integrity verification
#   - RTO/RPO monitoring (Recovery Time/Point Objectives)
#
# WHAT IT VALIDATES:
#   1. Backup existence & completeness
#   2. Backup integrity (file corruption check)
#   3. Database dump validity (can be restored)
#   4. File archive integrity (tar.gz corruption check)
#   5. Backup age & retention compliance
#   6. Backup size trends (detect anomalies)
#   7. Offsite backup sync status (if configured)
#   8. Test restore (optional - creates test database)
#
# USAGE:
#   Validate latest backup:
#     sudo bash backup-validation.sh
#
#   Validate specific backup:
#     sudo bash backup-validation.sh --backup=/var/backups/moodle/daily/backup_20250117_020000
#
#   Full validation with test restore:
#     sudo bash backup-validation.sh --test-restore
#
#   Install monthly validation cron:
#     sudo bash backup-validation.sh --install-cron
#
#   Check backup trends (last 30 days):
#     sudo bash backup-validation.sh --trends
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Backup directories
BACKUP_ROOT="/var/backups/moodle"

# Validation configuration
VALIDATION_LOG="/var/log/moodle-backup-validation.log"
VALIDATION_REPORT="/tmp/moodle-backup-validation-$(date +%Y%m%d_%H%M%S).txt"

# Test restore configuration
TEST_DB_NAME="moodle_restore_test_$(date +%Y%m%d_%H%M%S)"
TEST_RESTORE_DIR="/tmp/moodle-restore-test-$$"

# Backup age thresholds (in hours)
MAX_BACKUP_AGE_DAILY=36    # Daily backup should be < 36 hours old
MAX_BACKUP_AGE_WEEKLY=192  # Weekly backup should be < 8 days old

# Database credentials
if command -v get-moodle-secret &> /dev/null; then
    DB_ROOT_PASSWORD=$(get-moodle-secret db-root-password 2>/dev/null || echo "${DB_ROOT_PASSWORD:-}")
elif [[ -f /root/.moodle-credentials ]]; then
    source /root/.moodle-credentials
else
    DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
fi

# Validation results
VALIDATION_PASSED=0
VALIDATION_FAILED=0
VALIDATION_WARNINGS=0

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$VALIDATION_LOG"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$VALIDATION_LOG" >&2
    VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$VALIDATION_LOG"
    VALIDATION_WARNINGS=$((VALIDATION_WARNINGS + 1))
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$VALIDATION_LOG"
}

pass() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*" | tee -a "$VALIDATION_LOG"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

BACKUP_PATH=""
TEST_RESTORE=false
INSTALL_CRON=false
SHOW_TRENDS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup=*)
            BACKUP_PATH="${1#*=}"
            shift
            ;;
        --test-restore)
            TEST_RESTORE=true
            shift
            ;;
        --install-cron)
            INSTALL_CRON=true
            shift
            ;;
        --trends)
            SHOW_TRENDS=true
            shift
            ;;
        --help)
            cat << EOF
Usage: sudo bash backup-validation.sh [OPTIONS]

Validate Moodle backups and test disaster recovery procedures

Options:
  --backup=PATH          Validate specific backup (default: latest)
  --test-restore         Perform full restore test (creates test DB)
  --trends               Show backup size/success trends (last 30 days)
  --install-cron         Install monthly validation cron job
  --help                 Show this help message

Examples:
  sudo bash backup-validation.sh
  sudo bash backup-validation.sh --test-restore
  sudo bash backup-validation.sh --backup=/var/backups/moodle/daily/backup_20250117_020000
  sudo bash backup-validation.sh --trends
EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# INSTALL CRON JOB
# ============================================================================

if [[ "$INSTALL_CRON" == true ]]; then
    log "============================================"
    log "Installing Backup Validation Cron Job"
    log "============================================"

    # Create cron job for monthly backup validation (15th of month, 2 AM)
    CRON_JOB="0 2 15 * * /bin/bash $(realpath "$0") >> /var/log/moodle-backup-validation-cron.log 2>&1"

    if crontab -l 2>/dev/null | grep -F "backup-validation.sh" > /dev/null; then
        warn "Cron job already exists, updating..."
        (crontab -l 2>/dev/null | grep -v "backup-validation.sh"; echo "$CRON_JOB") | crontab -
    else
        log "Adding new cron job..."
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    fi

    log "Cron job installed successfully!"
    log ""
    log "Schedule: 15th of every month at 2:00 AM"
    log "Command: $(realpath "$0")"
    log "Log: /var/log/moodle-backup-validation-cron.log"
    log ""
    log "To manually validate: sudo bash $(realpath "$0")"
    log "============================================"

    exit 0
fi

# ============================================================================
# SHOW BACKUP TRENDS
# ============================================================================

if [[ "$SHOW_TRENDS" == true ]]; then
    log "============================================"
    log "Backup Trends (Last 30 Days)"
    log "============================================"

    # Analyze backup logs for trends
    if [[ -f /var/log/moodle-backup.log ]]; then
        log ""
        log "Backup Success Rate:"

        # Count successful vs failed backups
        TOTAL_BACKUPS=$(grep -c "Backup Complete" /var/log/moodle-backup.log 2>/dev/null || echo 0)
        FAILED_BACKUPS=$(grep -c "ERROR" /var/log/moodle-backup.log 2>/dev/null || echo 0)
        SUCCESS_RATE=$(( (TOTAL_BACKUPS - FAILED_BACKUPS) * 100 / (TOTAL_BACKUPS > 0 ? TOTAL_BACKUPS : 1) ))

        log "  Total backups: $TOTAL_BACKUPS"
        log "  Failed backups: $FAILED_BACKUPS"
        log "  Success rate: $SUCCESS_RATE%"

        if [[ $SUCCESS_RATE -ge 95 ]]; then
            pass "Backup success rate is excellent (≥95%)"
        elif [[ $SUCCESS_RATE -ge 90 ]]; then
            warn "Backup success rate is good but could improve (90-95%)"
        else
            error "Backup success rate is LOW (<90%) - investigate failures!"
        fi
    fi

    # Analyze backup sizes
    log ""
    log "Backup Size Trends:"

    if [[ -d "$BACKUP_ROOT/daily" ]]; then
        log ""
        log "  Recent daily backups:"

        find "$BACKUP_ROOT/daily" -maxdepth 1 -type d -name "backup_*" | sort -r | head -7 | while read -r backup_dir; do
            BACKUP_SIZE=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
            BACKUP_DATE=$(basename "$backup_dir" | sed 's/backup_//')
            log "    $BACKUP_DATE: $BACKUP_SIZE"
        done
    fi

    log ""
    log "Trend analysis complete. Check log for details."
    exit 0
fi

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log "============================================"
log "Moodle Backup Validation"
log "Started: $(date)"
log "Test Restore: $([ "$TEST_RESTORE" == true ] && echo "Enabled" || echo "Disabled")"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if backup directory exists
if [[ ! -d "$BACKUP_ROOT" ]]; then
    error "Backup root directory not found: $BACKUP_ROOT"
    exit 1
fi

# Check database credentials if test restore enabled
if [[ "$TEST_RESTORE" == true ]] && [[ -z "$DB_ROOT_PASSWORD" ]]; then
    error "Database root password not found (required for test restore)"
    error "Run 'sudo bash secrets-manager-setup.sh' or check /root/.moodle-credentials"
    exit 1
fi

log "Preflight checks passed"

# ============================================================================
# STEP 1: FIND BACKUP TO VALIDATE
# ============================================================================

log "============================================"
log "Step 1: Locating backup to validate..."
log "============================================"

if [[ -z "$BACKUP_PATH" ]]; then
    # Find latest backup
    log "Finding latest backup..."

    LATEST_BACKUP=$(find "$BACKUP_ROOT" -maxdepth 2 -type d -name "backup_*" | sort -r | head -1)

    if [[ -z "$LATEST_BACKUP" ]]; then
        error "No backups found in $BACKUP_ROOT"
        exit 1
    fi

    BACKUP_PATH="$LATEST_BACKUP"
    log "Latest backup found: $BACKUP_PATH"
else
    log "Using specified backup: $BACKUP_PATH"

    if [[ ! -d "$BACKUP_PATH" ]]; then
        error "Backup directory not found: $BACKUP_PATH"
        exit 1
    fi
fi

# ============================================================================
# STEP 2: VALIDATE BACKUP COMPLETENESS
# ============================================================================

log "============================================"
log "Step 2: Checking backup completeness..."
log "============================================"

# Check for required files
REQUIRED_FILES=(
    "BACKUP_MANIFEST.txt"
    "database.sql.gz"
    "moodledata.tar.gz"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$BACKUP_PATH/$file" ]]; then
        pass "Required file present: $file"
    else
        error "Missing required file: $file"
    fi
done

# Check manifest content
if [[ -f "$BACKUP_PATH/BACKUP_MANIFEST.txt" ]]; then
    log "Reading backup manifest..."

    BACKUP_DATE=$(grep "Backup Date:" "$BACKUP_PATH/BACKUP_MANIFEST.txt" | cut -d: -f2- | xargs)
    BACKUP_TYPE=$(grep "Backup Type:" "$BACKUP_PATH/BACKUP_MANIFEST.txt" | cut -d: -f2- | xargs)
    BACKUP_SIZE=$(grep "Total Size:" "$BACKUP_PATH/BACKUP_MANIFEST.txt" | cut -d: -f2- | xargs)

    log "  Backup Date: $BACKUP_DATE"
    log "  Backup Type: $BACKUP_TYPE"
    log "  Total Size: $BACKUP_SIZE"

    # Check backup age
    BACKUP_EPOCH=$(date -d "$BACKUP_DATE" +%s 2>/dev/null || echo 0)
    CURRENT_EPOCH=$(date +%s)
    BACKUP_AGE_HOURS=$(( (CURRENT_EPOCH - BACKUP_EPOCH) / 3600 ))

    log "  Backup Age: $BACKUP_AGE_HOURS hours"

    if [[ "$BACKUP_TYPE" == "daily" ]] && [[ $BACKUP_AGE_HOURS -gt $MAX_BACKUP_AGE_DAILY ]]; then
        warn "Daily backup is older than $MAX_BACKUP_AGE_DAILY hours (may be stale)"
    elif [[ "$BACKUP_TYPE" == "weekly" ]] && [[ $BACKUP_AGE_HOURS -gt $MAX_BACKUP_AGE_WEEKLY ]]; then
        warn "Weekly backup is older than $MAX_BACKUP_AGE_WEEKLY hours (may be stale)"
    else
        pass "Backup age is acceptable"
    fi
fi

# ============================================================================
# STEP 3: VALIDATE DATABASE DUMP INTEGRITY
# ============================================================================

log "============================================"
log "Step 3: Validating database dump integrity..."
log "============================================"

DB_DUMP_FILE="$BACKUP_PATH/database.sql.gz"

if [[ -f "$DB_DUMP_FILE" ]]; then
    # Check if gzip file is corrupted
    log "Testing gzip integrity..."

    if gzip -t "$DB_DUMP_FILE" 2>/dev/null; then
        pass "Database dump gzip integrity OK"

        # Check file size (should not be empty or suspiciously small)
        DB_SIZE=$(stat -c%s "$DB_DUMP_FILE")
        DB_SIZE_MB=$((DB_SIZE / 1024 / 1024))

        log "Database dump size: ${DB_SIZE_MB} MB"

        if [[ $DB_SIZE_MB -lt 1 ]]; then
            error "Database dump is suspiciously small (< 1 MB) - may be incomplete"
        elif [[ $DB_SIZE_MB -lt 5 ]]; then
            warn "Database dump is small (< 5 MB) - verify Moodle installation is not empty"
        else
            pass "Database dump size appears normal"
        fi

        # Check SQL content validity
        log "Checking SQL content..."

        SQL_LINES=$(gunzip < "$DB_DUMP_FILE" | head -100 | wc -l)

        if [[ $SQL_LINES -gt 10 ]]; then
            pass "Database dump contains SQL statements"

            # Check for Moodle-specific tables
            if gunzip < "$DB_DUMP_FILE" | head -1000 | grep -q "mdl_"; then
                pass "Moodle tables detected in dump (mdl_ prefix)"
            else
                warn "No Moodle tables detected in first 1000 lines (may be valid)"
            fi
        else
            error "Database dump appears empty or corrupted"
        fi
    else
        error "Database dump gzip file is corrupted!"
    fi
else
    error "Database dump file not found: $DB_DUMP_FILE"
fi

# ============================================================================
# STEP 4: VALIDATE MOODLEDATA ARCHIVE INTEGRITY
# ============================================================================

log "============================================"
log "Step 4: Validating moodledata archive integrity..."
log "============================================"

MOODLEDATA_FILE="$BACKUP_PATH/moodledata.tar.gz"

if [[ -f "$MOODLEDATA_FILE" ]]; then
    # Check tar.gz integrity
    log "Testing tar.gz integrity..."

    if tar -tzf "$MOODLEDATA_FILE" >/dev/null 2>&1; then
        pass "Moodledata tar.gz integrity OK"

        # Check file size
        DATA_SIZE=$(stat -c%s "$MOODLEDATA_FILE")
        DATA_SIZE_MB=$((DATA_SIZE / 1024 / 1024))

        log "Moodledata archive size: ${DATA_SIZE_MB} MB"

        if [[ $DATA_SIZE_MB -lt 10 ]]; then
            warn "Moodledata archive is small (< 10 MB) - verify not empty"
        else
            pass "Moodledata archive size appears normal"
        fi

        # Check archive contents
        log "Checking archive contents..."

        FILE_COUNT=$(tar -tzf "$MOODLEDATA_FILE" | wc -l)

        log "  Files in archive: $FILE_COUNT"

        if [[ $FILE_COUNT -lt 10 ]]; then
            warn "Very few files in moodledata archive ($FILE_COUNT)"
        else
            pass "Moodledata archive contains files: $FILE_COUNT"
        fi

        # Check for required directories
        if tar -tzf "$MOODLEDATA_FILE" | grep -q "filedir/"; then
            pass "Required directory present: filedir/"
        else
            warn "Missing filedir/ directory in moodledata archive"
        fi
    else
        error "Moodledata tar.gz file is corrupted!"
    fi
else
    error "Moodledata archive file not found: $MOODLEDATA_FILE"
fi

# ============================================================================
# STEP 5: TEST RESTORE (OPTIONAL)
# ============================================================================

if [[ "$TEST_RESTORE" == true ]]; then
    log "============================================"
    log "Step 5: Performing test restore..."
    log "============================================"

    warn "Test restore will create temporary test database: $TEST_DB_NAME"

    # Create test restore directory
    mkdir -p "$TEST_RESTORE_DIR"

    log "Extracting database dump to test database..."

    # Create test database
    if mysql -u root -p"$DB_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $TEST_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1; then
        log "Test database created: $TEST_DB_NAME"

        # Restore database dump to test database
        RESTORE_START=$(date +%s)

        if gunzip < "$DB_DUMP_FILE" | mysql -u root -p"$DB_ROOT_PASSWORD" "$TEST_DB_NAME" 2>&1; then
            RESTORE_END=$(date +%s)
            RESTORE_DURATION=$((RESTORE_END - RESTORE_START))

            pass "Database restore successful (${RESTORE_DURATION}s)"

            # Verify restored data
            log "Verifying restored data..."

            TABLE_COUNT=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$TEST_DB_NAME'")

            log "  Tables restored: $TABLE_COUNT"

            if [[ $TABLE_COUNT -gt 100 ]]; then
                pass "Restored database contains expected number of tables ($TABLE_COUNT)"
            else
                warn "Restored database has few tables ($TABLE_COUNT) - verify backup is complete"
            fi
        else
            error "Database restore FAILED - backup may be corrupted!"
        fi

        # Cleanup test database
        log "Cleaning up test database..."
        mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $TEST_DB_NAME;" 2>&1
        log "Test database removed"
    else
        error "Could not create test database"
    fi

    # Cleanup test directory
    rm -rf "$TEST_RESTORE_DIR"
else
    log "Step 5: Test restore skipped (use --test-restore to enable)"
fi

# ============================================================================
# STEP 6: CHECK BACKUP RETENTION COMPLIANCE
# ============================================================================

log "============================================"
log "Step 6: Checking backup retention compliance..."
log "============================================"

# Count backups by type
DAILY_COUNT=$(find "$BACKUP_ROOT/daily" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l)
WEEKLY_COUNT=$(find "$BACKUP_ROOT/weekly" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l)
MONTHLY_COUNT=$(find "$BACKUP_ROOT/monthly" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | wc -l)

log "Backup retention status:"
log "  Daily backups: $DAILY_COUNT (expected: 7)"
log "  Weekly backups: $WEEKLY_COUNT (expected: 4)"
log "  Monthly backups: $MONTHLY_COUNT (expected: 12)"

if [[ $DAILY_COUNT -ge 7 ]]; then
    pass "Daily backup retention met (≥7 days)"
elif [[ $DAILY_COUNT -gt 0 ]]; then
    warn "Daily backup retention low ($DAILY_COUNT/7 days)"
else
    error "No daily backups found!"
fi

if [[ $WEEKLY_COUNT -ge 4 ]]; then
    pass "Weekly backup retention met (≥4 weeks)"
elif [[ $WEEKLY_COUNT -gt 0 ]]; then
    warn "Weekly backup retention low ($WEEKLY_COUNT/4 weeks)"
fi

if [[ $MONTHLY_COUNT -ge 3 ]]; then
    pass "Monthly backup retention good (≥3 months)"
fi

# ============================================================================
# STEP 7: CHECK OFFSITE BACKUP (IF CONFIGURED)
# ============================================================================

log "============================================"
log "Step 7: Checking offsite backup sync..."
log "============================================"

# Check if Google Cloud Storage is configured
if [[ -n "${MOODLE_BACKUP_BUCKET:-}" ]] && command -v gsutil &> /dev/null; then
    log "Checking Google Cloud Storage bucket: $MOODLE_BACKUP_BUCKET"

    if gsutil ls "gs://$MOODLE_BACKUP_BUCKET" &> /dev/null; then
        pass "GCS bucket accessible: $MOODLE_BACKUP_BUCKET"

        # Count offsite backups
        OFFSITE_COUNT=$(gsutil ls "gs://$MOODLE_BACKUP_BUCKET/**/BACKUP_MANIFEST.txt" 2>/dev/null | wc -l)

        log "  Offsite backups: $OFFSITE_COUNT"

        if [[ $OFFSITE_COUNT -ge $DAILY_COUNT ]]; then
            pass "Offsite backups in sync with local backups"
        else
            warn "Offsite backups may be out of sync ($OFFSITE_COUNT offsite vs $DAILY_COUNT local)"
        fi
    else
        error "Cannot access GCS bucket: $MOODLE_BACKUP_BUCKET"
    fi
else
    warn "Offsite backup not configured (GCS bucket not set)"
    info "  Consider enabling offsite backups for disaster recovery"
    info "  Set MOODLE_BACKUP_BUCKET in backup-vm.sh"
fi

# ============================================================================
# GENERATE VALIDATION REPORT
# ============================================================================

log "============================================"
log "Generating validation report..."
log "============================================"

# Calculate validation score
TOTAL_CHECKS=$((VALIDATION_PASSED + VALIDATION_FAILED + VALIDATION_WARNINGS))
VALIDATION_SCORE=$(( (VALIDATION_PASSED * 100) / (TOTAL_CHECKS > 0 ? TOTAL_CHECKS : 1) ))

# Create validation report
cat > "$VALIDATION_REPORT" << EOF
# ============================================================================
# Moodle Backup Validation Report
# Generated: $(date)
# ============================================================================

## Summary

Validation Score: $VALIDATION_SCORE/100

Total Checks: $TOTAL_CHECKS
- Passed: $VALIDATION_PASSED
- Failed: $VALIDATION_FAILED
- Warnings: $VALIDATION_WARNINGS

## Backup Information

Backup Path: $BACKUP_PATH
Backup Date: ${BACKUP_DATE:-Unknown}
Backup Type: ${BACKUP_TYPE:-Unknown}
Backup Size: ${BACKUP_SIZE:-Unknown}
Backup Age: ${BACKUP_AGE_HOURS:-Unknown} hours

## Validation Results

### Completeness
$(if [[ $VALIDATION_FAILED -eq 0 ]]; then
    echo "✓ All required files present"
else
    echo "✗ Some files missing - backup may be incomplete"
fi)

### Database Dump
$(if gunzip -t "$DB_DUMP_FILE" 2>/dev/null; then
    echo "✓ Database dump integrity verified"
    echo "✓ Database dump size: ${DB_SIZE_MB:-Unknown} MB"
else
    echo "✗ Database dump failed validation"
fi)

### Moodledata Archive
$(if tar -tzf "$MOODLEDATA_FILE" >/dev/null 2>&1; then
    echo "✓ Moodledata archive integrity verified"
    echo "✓ Moodledata archive size: ${DATA_SIZE_MB:-Unknown} MB"
    echo "✓ Files in archive: ${FILE_COUNT:-Unknown}"
else
    echo "✗ Moodledata archive failed validation"
fi)

### Test Restore
$(if [[ "$TEST_RESTORE" == true ]]; then
    if [[ $VALIDATION_FAILED -eq 0 ]]; then
        echo "✓ Test restore completed successfully"
        echo "✓ Restored tables: ${TABLE_COUNT:-Unknown}"
    else
        echo "✗ Test restore failed"
    fi
else
    echo "- Test restore not performed (use --test-restore to enable)"
fi)

### Retention Compliance
- Daily backups: $DAILY_COUNT/7
- Weekly backups: $WEEKLY_COUNT/4
- Monthly backups: $MONTHLY_COUNT/12

### Offsite Backup
$(if [[ -n "${MOODLE_BACKUP_BUCKET:-}" ]]; then
    if gsutil ls "gs://$MOODLE_BACKUP_BUCKET" &> /dev/null 2>&1; then
        echo "✓ Offsite backup configured: $MOODLE_BACKUP_BUCKET"
        echo "  Offsite backups: ${OFFSITE_COUNT:-Unknown}"
    else
        echo "⚠ Offsite backup configured but inaccessible"
    fi
else
    echo "⚠ Offsite backup not configured"
fi)

## Recommendations

$(if [[ $VALIDATION_FAILED -gt 0 ]]; then
    echo "1. **URGENT**: Fix failed validations immediately"
    echo "2. Investigate backup process for failures"
fi)
$(if [[ $VALIDATION_WARNINGS -gt 0 ]]; then
    echo "3. Review warnings and address potential issues"
fi)
$(if [[ "$TEST_RESTORE" == false ]]; then
    echo "4. Schedule quarterly test restores: sudo bash backup-validation.sh --test-restore"
fi)
$(if [[ -z "${MOODLE_BACKUP_BUCKET:-}" ]]; then
    echo "5. Configure offsite backup to Google Cloud Storage"
fi)
$(if [[ $DAILY_COUNT -lt 7 ]]; then
    echo "6. Increase daily backup retention to 7 days minimum"
fi)

## Next Validation

Scheduled: $(date -d '+1 month' +%Y-%m-%d)
Run: sudo bash $(realpath "$0")

## Disaster Recovery Metrics

- **RTO** (Recovery Time Objective): ${RESTORE_DURATION:-Unknown}s (database only)
- **RPO** (Recovery Point Objective): ${BACKUP_AGE_HOURS:-Unknown} hours
- **Backup Reliability**: $VALIDATION_SCORE%

# ============================================================================
EOF

log "Validation report generated: $VALIDATION_REPORT"

# Display report
cat "$VALIDATION_REPORT"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Backup Validation Complete!"
log "============================================"
log ""
log "Validation Score: $VALIDATION_SCORE/100"
log ""
log "Results:"
log "  Passed: $VALIDATION_PASSED"
log "  Failed: $VALIDATION_FAILED"
log "  Warnings: $VALIDATION_WARNINGS"
log ""
log "Validation Report: $VALIDATION_REPORT"
log "Full Log: $VALIDATION_LOG"
log ""

if [[ $VALIDATION_FAILED -gt 0 ]]; then
    error "Backup validation FAILED - backups may not be restorable!"
    error "Fix issues immediately to ensure disaster recovery capability"
    exit 1
elif [[ $VALIDATION_WARNINGS -gt 0 ]]; then
    warn "Backup validation passed with warnings - review and address"
    exit 0
else
    log "Backup validation PASSED - backups are healthy and restorable"
    exit 0
fi
