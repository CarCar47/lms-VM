#!/bin/bash
# ============================================================================
# Moodle VM - Automated Database Maintenance Script
# Industry Standard: MySQL/MariaDB Optimization & Health Checks
# ============================================================================
#
# This script performs automated database maintenance following MySQL/MariaDB
# and Moodle best practices for optimal performance and data integrity.
#
# WHAT IT DOES:
#   1. Checks database health and integrity (CHECK TABLE)
#   2. Updates table statistics for query optimizer (ANALYZE TABLE)
#   3. Optimizes/defragments tables (OPTIMIZE TABLE - when needed)
#   4. Repairs corrupted tables if issues found (REPAIR TABLE)
#   5. Cleans Moodle temporary data and old logs
#   6. Provides performance recommendations
#
# INDUSTRY STANDARDS FOLLOWED:
#   - MySQL Performance Best Practices (mysqlcheck, mysqltuner)
#   - Moodle Performance Recommendations (docs.moodle.org)
#   - Database maintenance order: CHECK → ANALYZE → OPTIMIZE → REPAIR
#   - Weekly schedule during low-activity periods
#
# WHEN TO RUN:
#   - Automatically: Weekly (Sunday 4 AM via cron)
#   - Manually: After large data deletions, after Moodle upgrades
#   - On-demand: When performance degrades
#
# USAGE:
#   Install cron job (automatic weekly maintenance):
#     sudo bash database-maintenance.sh --install-cron
#
#   Run maintenance now (interactive):
#     sudo bash database-maintenance.sh
#
#   Run maintenance now (non-interactive):
#     sudo bash database-maintenance.sh --run-now
#
#   Check only (no optimization):
#     sudo bash database-maintenance.sh --check-only
#
#   Full optimization (force optimize all tables):
#     sudo bash database-maintenance.sh --force-optimize
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Database credentials (from Secret Manager or credentials file)
# Try Secret Manager first (industry standard), fall back to file if unavailable
if command -v get-moodle-secret &> /dev/null; then
    # Use Secret Manager (preferred)
    MOODLE_DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
    MOODLE_DB_USER="${MOODLE_DB_USER:-moodle_user}"
    DB_ROOT_PASSWORD=$(get-moodle-secret db-root-password 2>/dev/null || echo "${DB_ROOT_PASSWORD:-}")
elif [[ -f /root/.moodle-credentials ]]; then
    # Fallback to credentials file (legacy)
    source /root/.moodle-credentials
else
    # Fallback to environment variables
    DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-}"
    MOODLE_DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
    MOODLE_DB_USER="${MOODLE_DB_USER:-moodle_user}"
fi

# Maintenance configuration
MAINTENANCE_LOG="/var/log/moodle-database-maintenance.log"
MAINTENANCE_REPORT="/tmp/moodle-db-maintenance-report-$(date +%Y%m%d_%H%M%S).txt"

# Performance thresholds
FRAGMENTATION_THRESHOLD=10  # Optimize if fragmentation > 10%
TABLE_SIZE_THRESHOLD=1048576  # Skip optimize for tables > 1GB (takes too long)

# Moodle directories
MOODLE_DIR="${MOODLE_DIR:-/var/www/html/moodle}"
MOODLE_DATA="${MOODLE_DATA:-/var/moodledata}"

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$MAINTENANCE_LOG"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$MAINTENANCE_LOG" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$MAINTENANCE_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$MAINTENANCE_LOG"
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

RUN_MODE="interactive"
CHECK_ONLY=false
FORCE_OPTIMIZE=false
INSTALL_CRON=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-cron)
            INSTALL_CRON=true
            shift
            ;;
        --run-now)
            RUN_MODE="automatic"
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --force-optimize)
            FORCE_OPTIMIZE=true
            shift
            ;;
        --help)
            cat << EOF
Usage: sudo bash database-maintenance.sh [OPTIONS]

Automated database maintenance for Moodle MySQL/MariaDB

Options:
  --install-cron      Install weekly cron job (Sunday 4 AM)
  --run-now           Run maintenance immediately (non-interactive)
  --check-only        Only check database health, no optimization
  --force-optimize    Force optimize all tables (regardless of fragmentation)
  --help              Show this help message

Examples:
  sudo bash database-maintenance.sh --install-cron
  sudo bash database-maintenance.sh --run-now
  sudo bash database-maintenance.sh --check-only
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
    log "Installing Database Maintenance Cron Job"
    log "============================================"

    # Create cron job for weekly maintenance (Sunday 4 AM)
    CRON_JOB="0 4 * * 0 /bin/bash $(realpath "$0") --run-now >> /var/log/moodle-database-maintenance-cron.log 2>&1"

    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -F "database-maintenance.sh" > /dev/null; then
        warn "Cron job already exists, updating..."
        (crontab -l 2>/dev/null | grep -v "database-maintenance.sh"; echo "$CRON_JOB") | crontab -
    else
        log "Adding new cron job..."
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    fi

    log "Cron job installed successfully!"
    log ""
    log "Schedule: Every Sunday at 4:00 AM"
    log "Command: $(realpath "$0") --run-now"
    log "Log: /var/log/moodle-database-maintenance-cron.log"
    log ""
    log "Current crontab:"
    crontab -l
    log ""
    log "To manually run maintenance: sudo bash $(realpath "$0") --run-now"
    log "============================================"

    exit 0
fi

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log "============================================"
log "Moodle Database Maintenance"
log "Started: $(date)"
log "Mode: $RUN_MODE"
log "============================================"

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

# Check database credentials
if [[ -z "$DB_ROOT_PASSWORD" ]]; then
    error "Database root password not found"
    error "Run 'sudo bash secrets-manager-setup.sh' or check /root/.moodle-credentials"
    exit 1
fi

# Test database connection
if ! mysql -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1" &> /dev/null; then
    error "Cannot connect to database with provided credentials"
    exit 1
fi

log "Preflight checks passed"

# ============================================================================
# ENABLE MAINTENANCE MODE (MOODLE)
# ============================================================================

log "============================================"
log "Enabling Moodle maintenance mode..."
log "============================================"

MAINTENANCE_MODE_ENABLED=false

if [[ -f "$MOODLE_DIR/admin/cli/maintenance.php" ]]; then
    if php "$MOODLE_DIR/admin/cli/maintenance.php" --enable 2>/dev/null; then
        log "Moodle maintenance mode enabled"
        MAINTENANCE_MODE_ENABLED=true
    else
        warn "Could not enable maintenance mode (Moodle may not be installed yet)"
    fi
else
    warn "Maintenance mode script not found (Moodle may not be installed yet)"
fi

# ============================================================================
# STEP 1: DATABASE HEALTH CHECK
# ============================================================================

log "============================================"
log "Step 1: Checking database health..."
log "============================================"

HEALTH_CHECK_START=$(date +%s)
CORRUPTED_TABLES=()

log "Running CHECK TABLE on all Moodle tables..."

# Get list of all tables
TABLES=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MOODLE_DB_NAME'")

TOTAL_TABLES=$(echo "$TABLES" | wc -l)
CHECKED_TABLES=0

while IFS= read -r table; do
    CHECKED_TABLES=$((CHECKED_TABLES + 1))

    if [[ $((CHECKED_TABLES % 10)) -eq 0 ]]; then
        info "Progress: $CHECKED_TABLES/$TOTAL_TABLES tables checked"
    fi

    # Check table for corruption
    CHECK_RESULT=$(mysql -u root -p"$DB_ROOT_PASSWORD" "$MOODLE_DB_NAME" -e "CHECK TABLE \`$table\`" 2>&1)

    if ! echo "$CHECK_RESULT" | grep -q "OK"; then
        warn "Table $table has issues: $CHECK_RESULT"
        CORRUPTED_TABLES+=("$table")
    fi
done <<< "$TABLES"

HEALTH_CHECK_END=$(date +%s)
HEALTH_CHECK_DURATION=$((HEALTH_CHECK_END - HEALTH_CHECK_START))

if [[ ${#CORRUPTED_TABLES[@]} -eq 0 ]]; then
    log "✓ Health check completed: All $TOTAL_TABLES tables are healthy (${HEALTH_CHECK_DURATION}s)"
else
    warn "Health check completed: ${#CORRUPTED_TABLES[@]} tables need repair (${HEALTH_CHECK_DURATION}s)"
    warn "Corrupted tables: ${CORRUPTED_TABLES[*]}"
fi

# ============================================================================
# STEP 2: REPAIR CORRUPTED TABLES (IF NEEDED)
# ============================================================================

if [[ ${#CORRUPTED_TABLES[@]} -gt 0 ]]; then
    log "============================================"
    log "Step 2: Repairing corrupted tables..."
    log "============================================"

    REPAIR_START=$(date +%s)
    REPAIRED_COUNT=0

    for table in "${CORRUPTED_TABLES[@]}"; do
        log "Repairing table: $table"

        REPAIR_RESULT=$(mysql -u root -p"$DB_ROOT_PASSWORD" "$MOODLE_DB_NAME" -e "REPAIR TABLE \`$table\`" 2>&1)

        if echo "$REPAIR_RESULT" | grep -q "OK"; then
            log "  ✓ Repaired successfully"
            REPAIRED_COUNT=$((REPAIRED_COUNT + 1))
        else
            error "  ✗ Repair failed: $REPAIR_RESULT"
        fi
    done

    REPAIR_END=$(date +%s)
    REPAIR_DURATION=$((REPAIR_END - REPAIR_START))

    log "Repair completed: $REPAIRED_COUNT/${#CORRUPTED_TABLES[@]} tables repaired (${REPAIR_DURATION}s)"
else
    log "Step 2: No repairs needed - all tables healthy"
fi

# ============================================================================
# STEP 3: ANALYZE TABLES (UPDATE STATISTICS)
# ============================================================================

log "============================================"
log "Step 3: Analyzing tables (updating statistics)..."
log "============================================"

ANALYZE_START=$(date +%s)

log "Running ANALYZE TABLE to update query optimizer statistics..."

# Use mysqlcheck for efficiency (analyzes all tables in one command)
if mysqlcheck -u root -p"$DB_ROOT_PASSWORD" --analyze "$MOODLE_DB_NAME" >> "$MAINTENANCE_LOG" 2>&1; then
    ANALYZE_END=$(date +%s)
    ANALYZE_DURATION=$((ANALYZE_END - ANALYZE_START))
    log "✓ Analysis completed: Table statistics updated (${ANALYZE_DURATION}s)"
else
    warn "Analysis completed with warnings (check log for details)"
fi

# ============================================================================
# STEP 4: OPTIMIZE TABLES (IF NEEDED)
# ============================================================================

if [[ "$CHECK_ONLY" == false ]]; then
    log "============================================"
    log "Step 4: Optimizing tables (defragmentation)..."
    log "============================================"

    OPTIMIZE_START=$(date +%s)
    OPTIMIZED_COUNT=0
    SKIPPED_COUNT=0

    # Get table fragmentation info
    FRAGMENTATION_QUERY="
    SELECT
        TABLE_NAME,
        ROUND(DATA_LENGTH/1024/1024, 2) AS data_mb,
        ROUND(DATA_FREE/1024/1024, 2) AS free_mb,
        ROUND((DATA_FREE/DATA_LENGTH)*100, 2) AS fragmentation
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA='$MOODLE_DB_NAME'
        AND DATA_FREE > 0
        AND ENGINE IN ('InnoDB', 'MyISAM')
    "

    if [[ "$FORCE_OPTIMIZE" == true ]]; then
        log "Force optimize enabled: Optimizing ALL tables..."

        if mysqlcheck -u root -p"$DB_ROOT_PASSWORD" --optimize "$MOODLE_DB_NAME" >> "$MAINTENANCE_LOG" 2>&1; then
            OPTIMIZED_COUNT=$TOTAL_TABLES
            log "✓ All tables optimized"
        else
            warn "Optimization completed with warnings"
        fi
    else
        log "Smart optimize: Only optimizing fragmented tables (>${FRAGMENTATION_THRESHOLD}% fragmentation)..."

        # Get tables that need optimization
        TABLES_TO_OPTIMIZE=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "$FRAGMENTATION_QUERY" | awk -v threshold="$FRAGMENTATION_THRESHOLD" '$4 > threshold {print $1}')

        if [[ -z "$TABLES_TO_OPTIMIZE" ]]; then
            log "No tables need optimization (fragmentation < ${FRAGMENTATION_THRESHOLD}%)"
        else
            while IFS= read -r table; do
                # Get table size
                TABLE_SIZE=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT DATA_LENGTH FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MOODLE_DB_NAME' AND TABLE_NAME='$table'")

                if [[ $TABLE_SIZE -gt $TABLE_SIZE_THRESHOLD ]]; then
                    warn "Skipping large table: $table ($(($TABLE_SIZE / 1024 / 1024)) MB - would take too long)"
                    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                    continue
                fi

                log "Optimizing table: $table"

                if mysql -u root -p"$DB_ROOT_PASSWORD" "$MOODLE_DB_NAME" -e "OPTIMIZE TABLE \`$table\`" >> "$MAINTENANCE_LOG" 2>&1; then
                    log "  ✓ Optimized"
                    OPTIMIZED_COUNT=$((OPTIMIZED_COUNT + 1))
                else
                    warn "  ✗ Optimization failed"
                fi
            done <<< "$TABLES_TO_OPTIMIZE"

            log "Optimization completed: $OPTIMIZED_COUNT tables optimized, $SKIPPED_COUNT skipped"
        fi
    fi

    OPTIMIZE_END=$(date +%s)
    OPTIMIZE_DURATION=$((OPTIMIZE_END - OPTIMIZE_START))

    log "✓ Optimization phase completed (${OPTIMIZE_DURATION}s)"
else
    log "Step 4: Skipped (--check-only mode)"
fi

# ============================================================================
# STEP 5: CLEAN MOODLE TEMPORARY DATA
# ============================================================================

log "============================================"
log "Step 5: Cleaning Moodle temporary data..."
log "============================================"

CLEANUP_START=$(date +%s)

# Clear Moodle cache directories
if [[ -d "$MOODLE_DATA/cache" ]]; then
    CACHE_SIZE_BEFORE=$(du -sm "$MOODLE_DATA/cache" 2>/dev/null | cut -f1)

    log "Clearing Moodle cache directories..."
    find "$MOODLE_DATA/cache" -type f -delete 2>/dev/null || true

    CACHE_SIZE_AFTER=$(du -sm "$MOODLE_DATA/cache" 2>/dev/null | cut -f1)
    CACHE_FREED=$((CACHE_SIZE_BEFORE - CACHE_SIZE_AFTER))

    log "  ✓ Cache cleared: ${CACHE_FREED} MB freed"
fi

# Clear old session files (older than 7 days)
if [[ -d "$MOODLE_DATA/sessions" ]]; then
    SESSION_COUNT_BEFORE=$(find "$MOODLE_DATA/sessions" -type f 2>/dev/null | wc -l)

    log "Cleaning old session files (>7 days)..."
    find "$MOODLE_DATA/sessions" -type f -mtime +7 -delete 2>/dev/null || true

    SESSION_COUNT_AFTER=$(find "$MOODLE_DATA/sessions" -type f 2>/dev/null | wc -l)
    SESSION_DELETED=$((SESSION_COUNT_BEFORE - SESSION_COUNT_AFTER))

    log "  ✓ Sessions cleaned: $SESSION_DELETED old sessions deleted"
fi

# Clear temp directory
if [[ -d "$MOODLE_DATA/temp" ]]; then
    TEMP_SIZE_BEFORE=$(du -sm "$MOODLE_DATA/temp" 2>/dev/null | cut -f1)

    log "Clearing temporary files..."
    find "$MOODLE_DATA/temp" -type f -mtime +1 -delete 2>/dev/null || true

    TEMP_SIZE_AFTER=$(du -sm "$MOODLE_DATA/temp" 2>/dev/null | cut -f1)
    TEMP_FREED=$((TEMP_SIZE_BEFORE - TEMP_SIZE_AFTER))

    log "  ✓ Temp files cleared: ${TEMP_FREED} MB freed"
fi

CLEANUP_END=$(date +%s)
CLEANUP_DURATION=$((CLEANUP_END - CLEANUP_START))

log "✓ Cleanup completed (${CLEANUP_DURATION}s)"

# ============================================================================
# STEP 6: GENERATE MAINTENANCE REPORT
# ============================================================================

log "============================================"
log "Step 6: Generating maintenance report..."
log "============================================"

# Get database statistics
DB_SIZE=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT ROUND(SUM(DATA_LENGTH + INDEX_LENGTH)/1024/1024, 2) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MOODLE_DB_NAME'")
DB_DATA_SIZE=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT ROUND(SUM(DATA_LENGTH)/1024/1024, 2) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MOODLE_DB_NAME'")
DB_INDEX_SIZE=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT ROUND(SUM(INDEX_LENGTH)/1024/1024, 2) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MOODLE_DB_NAME'")
DB_FREE_SIZE=$(mysql -u root -p"$DB_ROOT_PASSWORD" -N -B -e "SELECT ROUND(SUM(DATA_FREE)/1024/1024, 2) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$MOODLE_DB_NAME'")

# Create maintenance report
cat > "$MAINTENANCE_REPORT" << EOF
# ============================================================================
# Moodle Database Maintenance Report
# Generated: $(date)
# ============================================================================

## Summary

Database: $MOODLE_DB_NAME
Total Tables: $TOTAL_TABLES
Mode: $RUN_MODE
Check Only: $CHECK_ONLY
Force Optimize: $FORCE_OPTIMIZE

## Database Statistics

Total Size: ${DB_SIZE} MB
  - Data: ${DB_DATA_SIZE} MB
  - Indexes: ${DB_INDEX_SIZE} MB
  - Free Space: ${DB_FREE_SIZE} MB

## Maintenance Results

### Health Check
- Duration: ${HEALTH_CHECK_DURATION} seconds
- Tables Checked: $TOTAL_TABLES
- Corrupted Tables: ${#CORRUPTED_TABLES[@]}
- Status: $([ ${#CORRUPTED_TABLES[@]} -eq 0 ] && echo "✓ HEALTHY" || echo "⚠ ISSUES FOUND")

### Repairs
- Tables Repaired: $REPAIRED_COUNT
- Status: $([ ${#CORRUPTED_TABLES[@]} -eq 0 ] && echo "✓ NOT NEEDED" || echo "✓ COMPLETED")

### Analysis
- Duration: ${ANALYZE_DURATION} seconds
- Status: ✓ COMPLETED

### Optimization
- Duration: ${OPTIMIZE_DURATION:-0} seconds
- Tables Optimized: ${OPTIMIZED_COUNT:-0}
- Tables Skipped: ${SKIPPED_COUNT:-0}
- Status: $([ "$CHECK_ONLY" == true ] && echo "- SKIPPED" || echo "✓ COMPLETED")

### Cleanup
- Duration: ${CLEANUP_DURATION} seconds
- Cache Freed: ${CACHE_FREED:-0} MB
- Sessions Deleted: ${SESSION_DELETED:-0}
- Temp Freed: ${TEMP_FREED:-0} MB
- Status: ✓ COMPLETED

## Next Maintenance

Recommended: $(date -d '+7 days' +%Y-%m-%d)
Frequency: Weekly (every Sunday at 4 AM)

## Notes

$([ ${#CORRUPTED_TABLES[@]} -gt 0 ] && echo "⚠ Warning: $(<${#CORRUPTED_TABLES[@]}) tables were corrupted and repaired" || echo "✓ No issues found")
$([ $OPTIMIZED_COUNT -gt 0 ] && echo "✓ $OPTIMIZED_COUNT tables were optimized" || echo "- No tables needed optimization")
$([ $SKIPPED_COUNT -gt 0 ] && echo "- $SKIPPED_COUNT large tables were skipped from optimization" || echo "")

## Recommendations

1. Monitor database size growth
2. Review slow query log: /var/log/mysql/mysql-slow.log
3. Check Moodle performance: http://yoursite.com/admin/dbperformance.php
4. Consider archiving old course data if size exceeds 10 GB

# ============================================================================
EOF

log "Maintenance report generated: $MAINTENANCE_REPORT"

# Display report
cat "$MAINTENANCE_REPORT"

# ============================================================================
# DISABLE MAINTENANCE MODE (MOODLE)
# ============================================================================

if [[ "$MAINTENANCE_MODE_ENABLED" == true ]]; then
    log "============================================"
    log "Disabling Moodle maintenance mode..."
    log "============================================"

    if php "$MOODLE_DIR/admin/cli/maintenance.php" --disable 2>/dev/null; then
        log "Moodle maintenance mode disabled"
    else
        warn "Could not disable maintenance mode (check manually)"
    fi
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - HEALTH_CHECK_START))

log "============================================"
log "Database Maintenance Complete!"
log "============================================"
log ""
log "Total Duration: ${TOTAL_DURATION} seconds"
log "Database: $MOODLE_DB_NAME"
log "Tables: $TOTAL_TABLES"
log ""
log "Results:"
log "  ✓ Health Check: ${#CORRUPTED_TABLES[@]} issues found"
log "  ✓ Repairs: $REPAIRED_COUNT tables repaired"
log "  ✓ Analysis: Statistics updated"
log "  ✓ Optimization: ${OPTIMIZED_COUNT:-0} tables optimized"
log "  ✓ Cleanup: ${CACHE_FREED:-0} MB cache + ${TEMP_FREED:-0} MB temp freed"
log ""
log "Maintenance Report: $MAINTENANCE_REPORT"
log "Full Log: $MAINTENANCE_LOG"
log ""
log "Next maintenance: $(date -d '+7 days' +%Y-%m-%d) (automatic if cron installed)"
log "============================================"

exit 0
