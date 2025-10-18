#!/bin/bash
###############################################################################
# Apache Rate Limiting Setup Script
# Version: 1.0.0
#
# This script installs and configures Apache rate limiting using:
# - mod_evasive: DDoS protection and request rate limiting
# - mod_security: Advanced WAF with custom rate limit rules
# - mod_reqtimeout: Slow request protection
#
# Usage:
#   sudo ./setup-apache-ratelimit.sh [--mod-security] [--test]
#
# Options:
#   --mod-security    Install ModSecurity (optional, more comprehensive)
#   --test            Test rate limiting after installation
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Not running as root
#   3 - Apache not installed
###############################################################################

set -euo pipefail

# Script configuration
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="Apache Rate Limiting Setup"
readonly LOG_FILE="/var/log/apache-ratelimit-setup.log"
readonly CONFIG_FILE="apache-ratelimit.conf"
readonly APACHE_CONF_DIR="/etc/apache2/conf-available"

# Options
INSTALL_MODSECURITY=false
RUN_TESTS=false

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

###############################################################################
# Logging Functions
###############################################################################

log() {
    local message="$1"
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[✓]${NC} $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[⚠]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[✗]${NC} $message" | tee -a "$LOG_FILE"
}

###############################################################################
# Utility Functions
###############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 2
    fi
}

check_apache() {
    if ! command -v apache2 >/dev/null 2>&1; then
        log_error "Apache is not installed"
        log_error "Run: apt-get install apache2"
        exit 3
    fi

    log_success "Apache is installed"
}

###############################################################################
# Installation Functions
###############################################################################

install_mod_evasive() {
    log "Installing mod_evasive..."

    # Install package
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y libapache2-mod-evasive

    # Create log directory
    mkdir -p /var/log/mod_evasive
    chown www-data:www-data /var/log/mod_evasive
    chmod 755 /var/log/mod_evasive

    # Enable module
    a2enmod evasive

    log_success "mod_evasive installed and enabled"
}

install_mod_security() {
    log "Installing ModSecurity..."

    # Install packages
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y libapache2-mod-security2

    # Enable module
    a2enmod security2

    # Copy recommended configuration
    if [[ -f /etc/modsecurity/modsecurity.conf-recommended ]]; then
        cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
        log_success "ModSecurity config copied"
    fi

    # Enable rule engine
    sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf

    # Create log directory
    mkdir -p /var/log/apache2
    touch /var/log/apache2/modsec_audit.log
    touch /var/log/apache2/modsec_debug.log
    chown www-data:www-data /var/log/apache2/modsec_*.log

    log_success "ModSecurity installed and enabled"

    # Optional: Install OWASP Core Rule Set
    log "Installing OWASP ModSecurity Core Rule Set (CRS)..."

    if [[ ! -d /usr/share/modsecurity-crs ]]; then
        apt-get install -y modsecurity-crs
        log_success "OWASP CRS installed"
    else
        log_warning "OWASP CRS already installed"
    fi
}

enable_required_modules() {
    log "Enabling required Apache modules..."

    # Required modules
    local modules=(
        "headers"
        "reqtimeout"
        "rewrite"
    )

    for module in "${modules[@]}"; do
        if ! a2query -m "$module" >/dev/null 2>&1; then
            a2enmod "$module"
            log_success "Enabled module: $module"
        else
            log "Module already enabled: $module"
        fi
    done
}

install_rate_limit_config() {
    log "Installing rate limiting configuration..."

    # Check if config file exists in current directory
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Make sure $CONFIG_FILE is in the current directory"
        exit 1
    fi

    # Copy to Apache conf-available
    cp "$CONFIG_FILE" "$APACHE_CONF_DIR/ratelimit.conf"
    chmod 644 "$APACHE_CONF_DIR/ratelimit.conf"

    # Enable configuration
    a2enconf ratelimit

    log_success "Rate limiting configuration installed and enabled"
}

###############################################################################
# Testing Functions
###############################################################################

test_apache_config() {
    log "Testing Apache configuration..."

    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        log_success "Apache configuration syntax OK"
        return 0
    else
        log_error "Apache configuration has errors"
        apache2ctl configtest
        return 1
    fi
}

reload_apache() {
    log "Reloading Apache..."

    if systemctl reload apache2; then
        log_success "Apache reloaded successfully"
    else
        log_error "Failed to reload Apache"
        log_error "Check: systemctl status apache2"
        exit 1
    fi
}

run_rate_limit_tests() {
    log "Running rate limit tests..."

    if ! command -v ab >/dev/null 2>&1; then
        log_warning "Apache Bench (ab) not installed"
        log "Installing apache2-utils..."
        apt-get install -y apache2-utils
    fi

    local test_url="http://localhost/"

    log "Test 1: Normal load (should succeed)"
    ab -n 10 -c 2 "$test_url" 2>&1 | grep "Complete requests" || true

    log ""
    log "Test 2: High load (should trigger rate limiting)"
    log_warning "Some requests should receive 429 errors..."
    ab -n 200 -c 20 "$test_url" 2>&1 | grep -E "(Complete requests|Failed requests|Non-2xx)" || true

    log ""
    log_warning "Check Apache logs for rate limit violations:"
    log "  - tail -f /var/log/apache2/error.log"
    log "  - tail -f /var/log/mod_evasive/*"

    if [[ "$INSTALL_MODSECURITY" == true ]]; then
        log "  - tail -f /var/log/apache2/modsec_audit.log"
    fi
}

###############################################################################
# Main Installation
###############################################################################

print_header() {
    echo ""
    echo "========================================================================="
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "========================================================================="
    echo ""
}

print_summary() {
    echo ""
    echo "========================================================================="
    echo "Installation Complete"
    echo "========================================================================="
    echo ""
    echo "Installed components:"
    echo "  ✓ mod_evasive (DDoS protection)"
    echo "  ✓ mod_reqtimeout (Slow request protection)"

    if [[ "$INSTALL_MODSECURITY" == true ]]; then
        echo "  ✓ ModSecurity (WAF with advanced rate limiting)"
        echo "  ✓ OWASP Core Rule Set"
    fi

    echo ""
    echo "Configuration:"
    echo "  Config file: $APACHE_CONF_DIR/ratelimit.conf"
    echo "  Log file: $LOG_FILE"
    echo ""
    echo "Rate limits configured:"
    echo "  - General: 50 requests/second per IP"
    echo "  - Login: 5 requests/minute per IP"
    echo "  - API: 200 requests/minute per IP"
    echo "  - Uploads: 10 requests/5 minutes per IP"
    echo ""
    echo "Monitoring:"
    echo "  - Apache error log: tail -f /var/log/apache2/error.log"
    echo "  - mod_evasive log: tail -f /var/log/mod_evasive/*"

    if [[ "$INSTALL_MODSECURITY" == true ]]; then
        echo "  - ModSecurity audit: tail -f /var/log/apache2/modsec_audit.log"
    fi

    echo ""
    echo "Testing:"
    echo "  Run: ab -n 200 -c 20 http://your-server/"
    echo ""
    echo "To adjust limits, edit: $APACHE_CONF_DIR/ratelimit.conf"
    echo "Then reload: systemctl reload apache2"
    echo ""
    echo "========================================================================="
    echo ""
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mod-security)
                INSTALL_MODSECURITY=true
                shift
                ;;
            --test)
                RUN_TESTS=true
                shift
                ;;
            -h|--help)
                print_header
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --mod-security    Install ModSecurity (comprehensive WAF)
  --test            Run rate limit tests after installation
  -h, --help        Show this help message

Examples:
  # Basic installation (mod_evasive only)
  sudo $0

  # Full installation with ModSecurity
  sudo $0 --mod-security

  # Install and test
  sudo $0 --mod-security --test

Features:
  - DDoS protection with mod_evasive
  - Slow request protection with mod_reqtimeout
  - Optional WAF with ModSecurity and OWASP CRS
  - Custom rate limiting rules for login, API, uploads

For more information:
  - mod_evasive: https://github.com/jzdziarski/mod_evasive
  - ModSecurity: https://modsecurity.org/
  - OWASP CRS: https://owasp.org/www-project-modsecurity-core-rule-set/
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    print_header

    # Pre-flight checks
    check_root
    check_apache

    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    log "Starting Apache Rate Limiting Setup"
    log "Date: $(date)"
    echo ""

    # Install components
    install_mod_evasive
    enable_required_modules

    if [[ "$INSTALL_MODSECURITY" == true ]]; then
        install_mod_security
    else
        log_warning "ModSecurity not installed (use --mod-security to install)"
    fi

    install_rate_limit_config

    # Test and reload
    if test_apache_config; then
        reload_apache
    else
        log_error "Apache configuration test failed"
        exit 1
    fi

    # Run tests if requested
    if [[ "$RUN_TESTS" == true ]]; then
        echo ""
        run_rate_limit_tests
    fi

    # Print summary
    print_summary

    log "Apache Rate Limiting Setup completed successfully"
}

# Execute main function
main "$@"
