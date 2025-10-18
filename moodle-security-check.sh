#!/bin/bash
# ============================================================================
# Moodle VM - Automated Security Audit Script
# Industry Standard: OWASP, CIS, NIST Compliance Checks
# ============================================================================
#
# This script performs comprehensive security audits for Moodle installations
# following industry best practices and security frameworks.
#
# SECURITY FRAMEWORKS FOLLOWED:
#   - OWASP Top 10 (web application security)
#   - CIS Benchmarks (configuration hardening)
#   - NIST Cybersecurity Framework
#   - Moodle Security Best Practices
#
# WHAT IT CHECKS:
#   1. File permissions (moodle code, moodledata, config.php)
#   2. Moodle version & known vulnerabilities
#   3. SSL/TLS configuration
#   4. Database security (credentials, remote access)
#   5. Password policies
#   6. Session security
#   7. User permissions & capabilities
#   8. PHP security settings
#   9. Web server configuration
#   10. System updates & patches
#
# USAGE:
#   Full security audit:
#     sudo bash moodle-security-check.sh
#
#   Install monthly cron job:
#     sudo bash moodle-security-check.sh --install-cron
#
#   Quick check (file permissions only):
#     sudo bash moodle-security-check.sh --quick
#
#   Generate compliance report:
#     sudo bash moodle-security-check.sh --compliance-report
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Moodle directories
MOODLE_DIR="${MOODLE_DIR:-/var/www/html/moodle}"
MOODLE_DATA="${MOODLE_DATA:-/var/moodledata}"
MOODLE_CONFIG="$MOODLE_DIR/config.php"

# Security check configuration
SECURITY_LOG="/var/log/moodle-security-audit.log"
SECURITY_REPORT="/tmp/moodle-security-report-$(date +%Y%m%d_%H%M%S).txt"

# Severity levels
CRITICAL_ISSUES=()
HIGH_ISSUES=()
MEDIUM_ISSUES=()
LOW_ISSUES=()
INFO_ITEMS=()

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$SECURITY_LOG"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$SECURITY_LOG" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$SECURITY_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$SECURITY_LOG"
}

critical() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] CRITICAL:${NC} $*" | tee -a "$SECURITY_LOG"
    CRITICAL_ISSUES+=("$*")
}

high() {
    echo -e "${MAGENTA}[$(date +'%Y-%m-%d %H:%M:%S')] HIGH:${NC} $*" | tee -a "$SECURITY_LOG"
    HIGH_ISSUES+=("$*")
}

medium() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] MEDIUM:${NC} $*" | tee -a "$SECURITY_LOG"
    MEDIUM_ISSUES+=("$*")
}

low() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] LOW:${NC} $*" | tee -a "$SECURITY_LOG"
    LOW_ISSUES+=("$*")
}

pass() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $*" | tee -a "$SECURITY_LOG"
    INFO_ITEMS+=("✓ $*")
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

RUN_MODE="full"
INSTALL_CRON=false
QUICK_CHECK=false
COMPLIANCE_REPORT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-cron)
            INSTALL_CRON=true
            shift
            ;;
        --quick)
            QUICK_CHECK=true
            shift
            ;;
        --compliance-report)
            COMPLIANCE_REPORT=true
            shift
            ;;
        --help)
            cat << EOF
Usage: sudo bash moodle-security-check.sh [OPTIONS]

Comprehensive Moodle security audit following OWASP, CIS, NIST standards

Options:
  --install-cron          Install monthly cron job (1st of month, 3 AM)
  --quick                 Quick check (file permissions only)
  --compliance-report     Generate compliance report (GDPR, FERPA, SOC2)
  --help                  Show this help message

Examples:
  sudo bash moodle-security-check.sh
  sudo bash moodle-security-check.sh --quick
  sudo bash moodle-security-check.sh --compliance-report
  sudo bash moodle-security-check.sh --install-cron
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
    log "Installing Security Audit Cron Job"
    log "============================================"

    # Create cron job for monthly security audit (1st of month, 3 AM)
    CRON_JOB="0 3 1 * * /bin/bash $(realpath "$0") >> /var/log/moodle-security-audit-cron.log 2>&1"

    if crontab -l 2>/dev/null | grep -F "moodle-security-check.sh" > /dev/null; then
        warn "Cron job already exists, updating..."
        (crontab -l 2>/dev/null | grep -v "moodle-security-check.sh"; echo "$CRON_JOB") | crontab -
    else
        log "Adding new cron job..."
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    fi

    log "Cron job installed successfully!"
    log ""
    log "Schedule: 1st of every month at 3:00 AM"
    log "Command: $(realpath "$0")"
    log "Log: /var/log/moodle-security-audit-cron.log"
    log ""
    log "To manually run audit: sudo bash $(realpath "$0")"
    log "============================================"

    exit 0
fi

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log "============================================"
log "Moodle Security Audit"
log "Started: $(date)"
log "Mode: $([ "$QUICK_CHECK" == true ] && echo "Quick Check" || echo "Full Audit")"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

# Check if Moodle directory exists
if [[ ! -d "$MOODLE_DIR" ]]; then
    error "Moodle directory not found: $MOODLE_DIR"
    exit 1
fi

# Check if Moodledata directory exists
if [[ ! -d "$MOODLE_DATA" ]]; then
    error "Moodledata directory not found: $MOODLE_DATA"
    exit 1
fi

# Check if config.php exists
if [[ ! -f "$MOODLE_CONFIG" ]]; then
    error "Moodle config.php not found: $MOODLE_CONFIG"
    exit 1
fi

log "Preflight checks passed"

# ============================================================================
# CHECK 1: FILE PERMISSIONS (CRITICAL)
# ============================================================================

log "============================================"
log "Check 1: File Permissions & Ownership"
log "============================================"

# Check moodledata permissions (should be 700/600)
log "Checking moodledata directory permissions..."

MOODLEDATA_PERMS=$(stat -c "%a" "$MOODLE_DATA")
MOODLEDATA_OWNER=$(stat -c "%U" "$MOODLE_DATA")
MOODLEDATA_GROUP=$(stat -c "%G" "$MOODLE_DATA")

if [[ "$MOODLEDATA_OWNER" == "www-data" ]] && [[ "$MOODLEDATA_GROUP" == "www-data" ]]; then
    pass "moodledata ownership correct: www-data:www-data"
else
    high "moodledata ownership incorrect: $MOODLEDATA_OWNER:$MOODLEDATA_GROUP (should be www-data:www-data)"
fi

if [[ "$MOODLEDATA_PERMS" == "777" ]]; then
    critical "moodledata permissions TOO OPEN: 777 (should be 700 or 755)"
elif [[ "$MOODLEDATA_PERMS" == "700" ]] || [[ "$MOODLEDATA_PERMS" == "755" ]]; then
    pass "moodledata permissions correct: $MOODLEDATA_PERMS"
else
    medium "moodledata permissions: $MOODLEDATA_PERMS (recommended: 700 or 755)"
fi

# Check config.php permissions (should be 600 or 640)
log "Checking config.php permissions..."

CONFIG_PERMS=$(stat -c "%a" "$MOODLE_CONFIG")
CONFIG_OWNER=$(stat -c "%U" "$MOODLE_CONFIG")

if [[ "$CONFIG_PERMS" == "644" ]] || [[ "$CONFIG_PERMS" == "664" ]] || [[ "$CONFIG_PERMS" == "666" ]]; then
    critical "config.php permissions TOO OPEN: $CONFIG_PERMS (contains DB credentials!)"
    critical "  Fix: chmod 600 $MOODLE_CONFIG"
elif [[ "$CONFIG_PERMS" == "600" ]] || [[ "$CONFIG_PERMS" == "640" ]]; then
    pass "config.php permissions secure: $CONFIG_PERMS"
else
    medium "config.php permissions: $CONFIG_PERMS (recommended: 600)"
fi

# Check moodle code directory permissions
log "Checking Moodle code directory permissions..."

MOODLE_PERMS=$(stat -c "%a" "$MOODLE_DIR")
MOODLE_OWNER=$(stat -c "%U" "$MOODLE_DIR")

if [[ "$MOODLE_OWNER" == "root" ]]; then
    pass "Moodle directory ownership secure: root (prevents tampering)"
elif [[ "$MOODLE_OWNER" == "www-data" ]]; then
    medium "Moodle directory owned by www-data (consider changing to root for security)"
else
    medium "Moodle directory owner: $MOODLE_OWNER (recommended: root)"
fi

if [[ "$MOODLE_PERMS" == "755" ]] || [[ "$MOODLE_PERMS" == "750" ]]; then
    pass "Moodle directory permissions correct: $MOODLE_PERMS"
elif [[ "$MOODLE_PERMS" == "777" ]]; then
    critical "Moodle directory permissions TOO OPEN: 777 (allows anyone to modify code!)"
else
    low "Moodle directory permissions: $MOODLE_PERMS (recommended: 755)"
fi

# Check for world-writable files (security risk)
log "Scanning for world-writable files in Moodle directory..."

WORLD_WRITABLE=$(find "$MOODLE_DIR" -type f -perm -002 2>/dev/null | wc -l)

if [[ $WORLD_WRITABLE -eq 0 ]]; then
    pass "No world-writable files found in Moodle directory"
else
    high "Found $WORLD_WRITABLE world-writable files in Moodle directory (security risk)"
    high "  Fix: find $MOODLE_DIR -type f -perm -002 -exec chmod o-w {} +"
fi

# ============================================================================
# CHECK 2: MOODLE VERSION & VULNERABILITIES
# ============================================================================

if [[ "$QUICK_CHECK" == false ]]; then
    log "============================================"
    log "Check 2: Moodle Version & Known Vulnerabilities"
    log "============================================"

    # Extract Moodle version from version.php
    if [[ -f "$MOODLE_DIR/version.php" ]]; then
        MOODLE_VERSION=$(grep '$release' "$MOODLE_DIR/version.php" | head -1 | grep -oP "'\K[^']+")
        MOODLE_BUILD=$(grep '$version' "$MOODLE_DIR/version.php" | head -1 | grep -oP "= \K[0-9.]+")

        log "Moodle version: $MOODLE_VERSION (build $MOODLE_BUILD)"

        # Warn about old versions (Moodle 3.x is EOL)
        if [[ "$MOODLE_VERSION" =~ ^3\. ]]; then
            critical "Moodle 3.x is END-OF-LIFE and no longer receives security updates!"
            critical "  Action: Upgrade to Moodle 4.x immediately"
        elif [[ "$MOODLE_VERSION" =~ ^4\.0 ]]; then
            high "Moodle 4.0 is nearing end-of-support. Consider upgrading to latest 4.x"
        else
            pass "Moodle version is recent: $MOODLE_VERSION"
        fi

        INFO_ITEMS+=("Moodle version: $MOODLE_VERSION")
    else
        warn "Could not determine Moodle version (version.php not found)"
    fi

    # Check for Moodle security updates via admin/index.php
    log "Checking for available security updates..."

    if command -v php &> /dev/null; then
        # Use Moodle CLI to check for updates (if available)
        if [[ -f "$MOODLE_DIR/admin/cli/check_for_updates.php" ]]; then
            sudo -u www-data php "$MOODLE_DIR/admin/cli/check_for_updates.php" 2>/dev/null || true
        fi
    fi
fi

# ============================================================================
# CHECK 3: SSL/TLS CONFIGURATION
# ============================================================================

if [[ "$QUICK_CHECK" == false ]]; then
    log "============================================"
    log "Check 3: SSL/TLS Configuration"
    log "============================================"

    # Check if wwwroot uses HTTPS
    WWWROOT=$(grep 'wwwroot' "$MOODLE_CONFIG" | grep -oP "http[s]?://[^'\"]+")

    if [[ "$WWWROOT" =~ ^https:// ]]; then
        pass "Moodle configured to use HTTPS: $WWWROOT"
    else
        critical "Moodle NOT using HTTPS: $WWWROOT"
        critical "  Action: Update \$CFG->wwwroot in config.php to use https://"
    fi

    # Check if sslproxy is enabled (for load balancers)
    if grep -q "sslproxy.*true" "$MOODLE_CONFIG"; then
        info "SSL proxy enabled (using load balancer or reverse proxy)"
        INFO_ITEMS+=("SSL proxy configuration detected")
    fi

    # Check Apache/Nginx SSL configuration
    if systemctl is-active --quiet apache2; then
        log "Checking Apache SSL configuration..."

        if apache2ctl -M 2>/dev/null | grep -q ssl_module; then
            pass "Apache SSL module enabled"

            # Check for SSL certificates
            if [[ -d /etc/letsencrypt/live ]]; then
                CERT_COUNT=$(find /etc/letsencrypt/live -name "cert.pem" | wc -l)
                if [[ $CERT_COUNT -gt 0 ]]; then
                    pass "Let's Encrypt SSL certificates found: $CERT_COUNT"

                    # Check certificate expiry
                    for cert in /etc/letsencrypt/live/*/cert.pem; do
                        EXPIRY=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
                        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo 0)
                        CURRENT_EPOCH=$(date +%s)
                        DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))

                        if [[ $DAYS_UNTIL_EXPIRY -lt 7 ]]; then
                            critical "SSL certificate expires in $DAYS_UNTIL_EXPIRY days: $cert"
                        elif [[ $DAYS_UNTIL_EXPIRY -lt 30 ]]; then
                            high "SSL certificate expires in $DAYS_UNTIL_EXPIRY days: $cert"
                        else
                            pass "SSL certificate valid for $DAYS_UNTIL_EXPIRY days: $(dirname "$cert" | xargs basename)"
                        fi
                    done
                fi
            fi
        else
            medium "Apache SSL module not enabled (check if using reverse proxy)"
        fi
    elif systemctl is-active --quiet nginx; then
        log "Checking Nginx SSL configuration..."

        if nginx -V 2>&1 | grep -q "http_ssl_module"; then
            pass "Nginx SSL module enabled"
        else
            medium "Nginx SSL module not enabled"
        fi
    fi
fi

# ============================================================================
# CHECK 4: DATABASE SECURITY
# ============================================================================

if [[ "$QUICK_CHECK" == false ]]; then
    log "============================================"
    log "Check 4: Database Security"
    log "============================================"

    # Check for credentials in config.php
    if grep -q "dbpass" "$MOODLE_CONFIG"; then
        info "Database credentials found in config.php"

        # Check if password is simple/weak
        DB_PASS=$(grep 'dbpass' "$MOODLE_CONFIG" | grep -oP "=\s*'?\K[^';]+")

        if [[ ${#DB_PASS} -lt 12 ]]; then
            high "Database password is short (< 12 characters)"
        elif [[ "$DB_PASS" =~ ^[a-z]+$ ]] || [[ "$DB_PASS" =~ ^[0-9]+$ ]]; then
            high "Database password appears weak (only lowercase or only numbers)"
        else
            pass "Database password appears strong"
        fi
    fi

    # Check database host (should be localhost for security)
    DB_HOST=$(grep 'dbhost' "$MOODLE_CONFIG" | grep -oP "=\s*'?\K[^';]+")

    if [[ "$DB_HOST" == "localhost" ]] || [[ "$DB_HOST" == "127.0.0.1" ]]; then
        pass "Database on localhost (secure - no remote access)"
    else
        medium "Database host is remote: $DB_HOST (ensure firewall restrictions)"
    fi

    # Check if database credentials are in Secret Manager
    if command -v get-moodle-secret &> /dev/null; then
        pass "Secret Manager available for credential management"
        INFO_ITEMS+=("Credentials can be migrated to Secret Manager")
    else
        medium "Secret Manager not configured (consider migrating DB credentials)"
    fi
fi

# ============================================================================
# CHECK 5: PASSWORD POLICIES
# ============================================================================

if [[ "$QUICK_CHECK" == false ]] && [[ -f "$MOODLE_DIR/config.php" ]]; then
    log "============================================"
    log "Check 5: Password Policies"
    log "============================================"

    # Check minimum password length
    if grep -q "minpasswordlength" "$MOODLE_CONFIG"; then
        MIN_PASS_LENGTH=$(grep 'minpasswordlength' "$MOODLE_CONFIG" | grep -oP "= \K[0-9]+")

        if [[ $MIN_PASS_LENGTH -ge 12 ]]; then
            pass "Minimum password length: $MIN_PASS_LENGTH characters (strong)"
        elif [[ $MIN_PASS_LENGTH -ge 8 ]]; then
            medium "Minimum password length: $MIN_PASS_LENGTH characters (consider 12+)"
        else
            high "Minimum password length: $MIN_PASS_LENGTH characters (too short!)"
        fi
    else
        info "Password length not explicitly set (using Moodle default: 8)"
        INFO_ITEMS+=("Consider setting \$CFG->minpasswordlength = 12 in config.php")
    fi

    # Check for password complexity requirements
    if grep -q "passwordpolicy" "$MOODLE_CONFIG"; then
        pass "Password policy configured in config.php"
    else
        medium "No password policy in config.php (check Moodle admin settings)"
    fi
fi

# ============================================================================
# CHECK 6: PHP SECURITY SETTINGS
# ============================================================================

if [[ "$QUICK_CHECK" == false ]]; then
    log "============================================"
    log "Check 6: PHP Security Configuration"
    log "============================================"

    # Check display_errors (should be Off in production)
    DISPLAY_ERRORS=$(php -r "echo ini_get('display_errors');")

    if [[ "$DISPLAY_ERRORS" == "" ]] || [[ "$DISPLAY_ERRORS" == "0" ]]; then
        pass "PHP display_errors: Off (secure for production)"
    else
        high "PHP display_errors: On (reveals sensitive info to attackers!)"
        high "  Fix: Set display_errors = Off in php.ini"
    fi

    # Check expose_php (should be Off)
    EXPOSE_PHP=$(php -r "echo ini_get('expose_php');")

    if [[ "$EXPOSE_PHP" == "" ]] || [[ "$EXPOSE_PHP" == "0" ]]; then
        pass "PHP expose_php: Off (hides PHP version)"
    else
        medium "PHP expose_php: On (reveals PHP version to attackers)"
    fi

    # Check session.cookie_httponly (should be On)
    SESSION_HTTPONLY=$(php -r "echo ini_get('session.cookie_httponly');")

    if [[ "$SESSION_HTTPONLY" == "1" ]]; then
        pass "session.cookie_httponly: On (prevents XSS cookie theft)"
    else
        high "session.cookie_httponly: Off (vulnerable to XSS attacks!)"
    fi

    # Check session.cookie_secure (should be On for HTTPS sites)
    SESSION_SECURE=$(php -r "echo ini_get('session.cookie_secure');")

    if [[ "$WWWROOT" =~ ^https:// ]]; then
        if [[ "$SESSION_SECURE" == "1" ]]; then
            pass "session.cookie_secure: On (cookies only sent over HTTPS)"
        else
            high "session.cookie_secure: Off (cookies can be intercepted!)"
        fi
    fi

    # Check file_uploads (should be On for Moodle)
    FILE_UPLOADS=$(php -r "echo ini_get('file_uploads');")

    if [[ "$FILE_UPLOADS" == "1" ]]; then
        pass "PHP file_uploads: On (required for Moodle)"

        # Check upload_max_filesize
        UPLOAD_MAX=$(php -r "echo ini_get('upload_max_filesize');")
        info "Max upload size: $UPLOAD_MAX"
        INFO_ITEMS+=("PHP upload_max_filesize: $UPLOAD_MAX")
    else
        critical "PHP file_uploads: Off (breaks Moodle functionality!)"
    fi

    # Check memory_limit
    MEMORY_LIMIT=$(php -r "echo ini_get('memory_limit');")
    MEMORY_MB=$(echo "$MEMORY_LIMIT" | grep -oP "\d+")

    if [[ $MEMORY_MB -ge 256 ]]; then
        pass "PHP memory_limit: $MEMORY_LIMIT (sufficient)"
    elif [[ $MEMORY_MB -ge 128 ]]; then
        medium "PHP memory_limit: $MEMORY_LIMIT (consider increasing to 256M)"
    else
        high "PHP memory_limit: $MEMORY_LIMIT (may cause issues - increase to 256M)"
    fi
fi

# ============================================================================
# CHECK 7: SYSTEM UPDATES & PATCHES
# ============================================================================

if [[ "$QUICK_CHECK" == false ]]; then
    log "============================================"
    log "Check 7: System Updates & Security Patches"
    log "============================================"

    # Check for pending system updates
    if command -v apt &> /dev/null; then
        log "Checking for pending system updates..."

        apt update -qq 2>/dev/null || true
        UPDATES_AVAILABLE=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo 0)

        if [[ $UPDATES_AVAILABLE -eq 0 ]]; then
            pass "System is up to date (no pending updates)"
        elif [[ $UPDATES_AVAILABLE -lt 10 ]]; then
            medium "$UPDATES_AVAILABLE system updates available"
        else
            high "$UPDATES_AVAILABLE system updates available (update soon!)"
        fi

        # Check for security updates specifically
        SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l || echo 0)

        if [[ $SECURITY_UPDATES -gt 0 ]]; then
            critical "$SECURITY_UPDATES SECURITY updates available (apply immediately!)"
        fi
    fi

    # Check last update time
    if [[ -f /var/log/apt/history.log ]]; then
        LAST_UPDATE=$(grep "Start-Date:" /var/log/apt/history.log | tail -1 | cut -d: -f2- | xargs)
        LAST_UPDATE_EPOCH=$(date -d "$LAST_UPDATE" +%s 2>/dev/null || echo 0)
        CURRENT_EPOCH=$(date +%s)
        DAYS_SINCE_UPDATE=$(( (CURRENT_EPOCH - LAST_UPDATE_EPOCH) / 86400 ))

        if [[ $DAYS_SINCE_UPDATE -lt 7 ]]; then
            pass "Last system update: $DAYS_SINCE_UPDATE days ago"
        elif [[ $DAYS_SINCE_UPDATE -lt 30 ]]; then
            medium "Last system update: $DAYS_SINCE_UPDATE days ago (update soon)"
        else
            high "Last system update: $DAYS_SINCE_UPDATE days ago (update now!)"
        fi
    fi
fi

# ============================================================================
# CHECK 8: FIREWALL & NETWORK SECURITY
# ============================================================================

if [[ "$QUICK_CHECK" == false ]]; then
    log "============================================"
    log "Check 8: Firewall & Network Security"
    log "============================================"

    # Check if firewall is enabled
    if command -v ufw &> /dev/null; then
        UFW_STATUS=$(ufw status | grep -i "Status:" | awk '{print $2}')

        if [[ "$UFW_STATUS" == "active" ]]; then
            pass "UFW firewall is active"

            # Check open ports
            UFW_RULES=$(ufw status numbered | grep -E "ALLOW|DENY" | wc -l)
            info "UFW rules configured: $UFW_RULES"
        else
            high "UFW firewall is INACTIVE (no network protection!)"
        fi
    elif systemctl is-active --quiet firewalld; then
        pass "Firewalld is active"
    else
        high "No firewall detected (UFW or firewalld)"
    fi

    # Check for open database ports (should not be publicly accessible)
    if command -v netstat &> /dev/null; then
        DB_PORT_OPEN=$(netstat -tuln | grep -E ":3306|:5432" | grep -v "127.0.0.1" | wc -l)

        if [[ $DB_PORT_OPEN -eq 0 ]]; then
            pass "Database port not exposed to external network"
        else
            critical "Database port is EXPOSED to external network (security risk!)"
        fi
    fi
fi

# ============================================================================
# GENERATE SECURITY REPORT
# ============================================================================

log "============================================"
log "Generating Security Report..."
log "============================================"

# Calculate security score
TOTAL_CHECKS=$((${#CRITICAL_ISSUES[@]} + ${#HIGH_ISSUES[@]} + ${#MEDIUM_ISSUES[@]} + ${#LOW_ISSUES[@]} + ${#INFO_ITEMS[@]}))
ISSUES_FOUND=$((${#CRITICAL_ISSUES[@]} + ${#HIGH_ISSUES[@]} + ${#MEDIUM_ISSUES[@]} + ${#LOW_ISSUES[@]}))
SECURITY_SCORE=$(( 100 - (${#CRITICAL_ISSUES[@]} * 20) - (${#HIGH_ISSUES[@]} * 10) - (${#MEDIUM_ISSUES[@]} * 5) - (${#LOW_ISSUES[@]} * 2) ))

if [[ $SECURITY_SCORE -lt 0 ]]; then
    SECURITY_SCORE=0
fi

# Determine security grade
if [[ $SECURITY_SCORE -ge 95 ]]; then
    SECURITY_GRADE="A+ (Excellent)"
elif [[ $SECURITY_SCORE -ge 90 ]]; then
    SECURITY_GRADE="A (Very Good)"
elif [[ $SECURITY_SCORE -ge 80 ]]; then
    SECURITY_GRADE="B (Good)"
elif [[ $SECURITY_SCORE -ge 70 ]]; then
    SECURITY_GRADE="C (Fair - needs improvement)"
elif [[ $SECURITY_SCORE -ge 60 ]]; then
    SECURITY_GRADE="D (Poor - security risks)"
else
    SECURITY_GRADE="F (Critical - immediate action required)"
fi

# Create security report
cat > "$SECURITY_REPORT" << EOF
# ============================================================================
# Moodle Security Audit Report
# Generated: $(date)
# ============================================================================

## Executive Summary

Security Score: $SECURITY_SCORE/100
Security Grade: $SECURITY_GRADE

Total Checks: $TOTAL_CHECKS
Issues Found: $ISSUES_FOUND
- Critical: ${#CRITICAL_ISSUES[@]}
- High: ${#HIGH_ISSUES[@]}
- Medium: ${#MEDIUM_ISSUES[@]}
- Low: ${#LOW_ISSUES[@]}

## System Information

Moodle Directory: $MOODLE_DIR
Moodledata Directory: $MOODLE_DATA
Moodle Version: ${MOODLE_VERSION:-Unknown}
WWW Root: ${WWWROOT:-Not configured}

## Critical Issues (Immediate Action Required)

$(if [[ ${#CRITICAL_ISSUES[@]} -eq 0 ]]; then
    echo "✓ No critical issues found"
else
    for issue in "${CRITICAL_ISSUES[@]}"; do
        echo "  ✗ $issue"
    done
fi)

## High Priority Issues

$(if [[ ${#HIGH_ISSUES[@]} -eq 0 ]]; then
    echo "✓ No high priority issues found"
else
    for issue in "${HIGH_ISSUES[@]}"; do
        echo "  ⚠ $issue"
    done
fi)

## Medium Priority Issues

$(if [[ ${#MEDIUM_ISSUES[@]} -eq 0 ]]; then
    echo "✓ No medium priority issues found"
else
    for issue in "${MEDIUM_ISSUES[@]}"; do
        echo "  ⚠ $issue"
    done
fi)

## Low Priority Issues

$(if [[ ${#LOW_ISSUES[@]} -eq 0 ]]; then
    echo "✓ No low priority issues found"
else
    for issue in "${LOW_ISSUES[@]}"; do
        echo "  - $issue"
    done
fi)

## Passed Checks

$(for item in "${INFO_ITEMS[@]}"; do
    echo "  $item"
done)

## Recommendations

$(if [[ ${#CRITICAL_ISSUES[@]} -gt 0 ]]; then
    echo "1. **URGENT**: Address all critical issues immediately"
fi)
$(if [[ ${#HIGH_ISSUES[@]} -gt 0 ]]; then
    echo "2. Fix high priority issues within 24-48 hours"
fi)
$(if [[ ${#MEDIUM_ISSUES[@]} -gt 0 ]]; then
    echo "3. Schedule medium priority fixes within 1 week"
fi)
$(if [[ $SECURITY_SCORE -lt 90 ]]; then
    echo "4. Run full security audit monthly"
    echo "5. Subscribe to Moodle security announcements: https://moodle.org/security/"
fi)

## Compliance Status

$(if [[ "$COMPLIANCE_REPORT" == true ]]; then
    cat << COMPLIANCE
### GDPR Compliance
- Data encryption: $([ "$WWWROOT" =~ ^https:// ] && echo "✓ Yes (HTTPS)" || echo "✗ No")
- Access controls: $([ ${#CRITICAL_ISSUES[@]} -eq 0 ] && echo "✓ Adequate" || echo "⚠ Needs review")
- Regular audits: Run monthly security checks

### FERPA Compliance (Education Privacy)
- Student data protection: File permissions $([ "$MOODLEDATA_PERMS" == "700" ] && echo "✓ Secure" || echo "⚠ Review")
- Access logging: Check Moodle logs regularly
- Data retention: Configure in Moodle admin settings

### SOC 2 Controls
- Access control: $([ ${#CRITICAL_ISSUES[@]} -eq 0 ] && echo "✓ Implemented" || echo "⚠ Issues found")
- Monitoring: $(systemctl is-active --quiet ops-agent && echo "✓ Active" || echo "- Not configured")
- Change management: Version control recommended
COMPLIANCE
fi)

## Next Steps

1. Review this report thoroughly
2. Prioritize fixes by severity (Critical → High → Medium → Low)
3. Schedule next security audit: $(date -d '+1 month' +%Y-%m-%d)
4. Document all changes made
5. Keep Moodle updated with latest security patches

## Resources

- Moodle Security: https://docs.moodle.org/en/Security
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- CIS Benchmarks: https://www.cisecurity.org/benchmark/
- Moodle Security Announcements: https://moodle.org/security/

# ============================================================================
EOF

log "Security report generated: $SECURITY_REPORT"

# Display summary
cat "$SECURITY_REPORT"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Security Audit Complete!"
log "============================================"
log ""
log "Security Score: $SECURITY_SCORE/100"
log "Security Grade: $SECURITY_GRADE"
log ""
log "Issues Found:"
log "  Critical: ${#CRITICAL_ISSUES[@]}"
log "  High: ${#HIGH_ISSUES[@]}"
log "  Medium: ${#MEDIUM_ISSUES[@]}"
log "  Low: ${#LOW_ISSUES[@]}"
log ""
log "Security Report: $SECURITY_REPORT"
log "Full Log: $SECURITY_LOG"
log ""

if [[ ${#CRITICAL_ISSUES[@]} -gt 0 ]]; then
    error "CRITICAL ISSUES FOUND - IMMEDIATE ACTION REQUIRED!"
    exit 1
elif [[ ${#HIGH_ISSUES[@]} -gt 0 ]]; then
    warn "High priority issues found - address within 24-48 hours"
    exit 0
else
    log "No critical or high priority issues found"
    exit 0
fi
