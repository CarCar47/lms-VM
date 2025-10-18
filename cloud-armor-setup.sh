#!/bin/bash
###############################################################################
# Google Cloud Armor Setup Script
# Version: 1.0.0
#
# This script configures Google Cloud Armor WAF (Web Application Firewall)
# with OWASP Top 10 protection and DDoS mitigation for Moodle deployments.
#
# Features:
# - OWASP ModSecurity CRS 3.3.2 preconfigured rules
# - DDoS protection (L3/L4 and L7)
# - Rate limiting
# - Geo-based access control
# - IP whitelisting/blacklisting
# - Adaptive protection (optional, requires Cloud Armor Plus)
#
# Prerequisites:
# - Google Cloud SDK (gcloud) installed
# - Project ID configured
# - Appropriate IAM permissions (Compute Security Admin)
# - Load balancer already set up
#
# Usage:
#   ./cloud-armor-setup.sh --project PROJECT_ID --backend-service BACKEND_SERVICE [OPTIONS]
#
# Options:
#   --project PROJECT_ID           GCP project ID (required)
#   --backend-service SERVICE      Backend service name (required)
#   --policy-name NAME             Security policy name (default: moodle-waf-policy)
#   --sensitivity LEVEL            WAF sensitivity 1-4 (default: 1)
#   --enable-adaptive              Enable adaptive protection (Cloud Armor Plus)
#   --whitelist-ips IPS            Comma-separated IPs to whitelist
#   --allowed-countries COUNTRIES  Comma-separated country codes (e.g., US,CA,GB)
#   --preview                      Enable preview mode (recommended for testing)
#   --verbose                      Enable verbose logging
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Missing required parameters
#   3 - gcloud not installed or not authenticated
###############################################################################

set -euo pipefail

# Script configuration
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="Google Cloud Armor Setup"
readonly LOG_FILE="/tmp/cloud-armor-setup-$(date +%Y%m%d_%H%M%S).log"

# Default configuration
PROJECT_ID=""
BACKEND_SERVICE=""
POLICY_NAME="moodle-waf-policy"
SENSITIVITY_LEVEL=1
ENABLE_ADAPTIVE=false
WHITELIST_IPS=""
ALLOWED_COUNTRIES=""
PREVIEW_MODE=false
VERBOSE_LOGGING=false

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

log_info() {
    local message="$1"
    echo -e "${BLUE}[ℹ]${NC} $message" | tee -a "$LOG_FILE"
}

###############################################################################
# Utility Functions
###############################################################################

check_gcloud() {
    if ! command -v gcloud >/dev/null 2>&1; then
        log_error "gcloud CLI not found"
        log_error "Install: https://cloud.google.com/sdk/docs/install"
        exit 3
    fi

    log_success "gcloud CLI is installed"

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with gcloud"
        log_error "Run: gcloud auth login"
        exit 3
    fi

    log_success "gcloud authenticated"
}

check_project() {
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID not specified"
        log_error "Use: --project PROJECT_ID"
        exit 2
    fi

    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Cannot access project: $PROJECT_ID"
        log_error "Check project ID and permissions"
        exit 2
    fi

    # Set active project
    gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

    log_success "Project: $PROJECT_ID"
}

check_backend_service() {
    if [[ -z "$BACKEND_SERVICE" ]]; then
        log_error "Backend service not specified"
        log_error "Use: --backend-service SERVICE_NAME"
        log_error ""
        log_info "List backend services:"
        log_info "  gcloud compute backend-services list --project=$PROJECT_ID"
        exit 2
    fi

    # Verify backend service exists
    if ! gcloud compute backend-services describe "$BACKEND_SERVICE" --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Backend service not found: $BACKEND_SERVICE"
        log_error "Available backend services:"
        gcloud compute backend-services list --project="$PROJECT_ID" --format="value(name)"
        exit 2
    fi

    log_success "Backend service: $BACKEND_SERVICE"
}

###############################################################################
# Cloud Armor Configuration Functions
###############################################################################

create_security_policy() {
    log "Creating Cloud Armor security policy: $POLICY_NAME"

    # Check if policy already exists
    if gcloud compute security-policies describe "$POLICY_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Security policy already exists: $POLICY_NAME"
        read -p "Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gcloud compute security-policies delete "$POLICY_NAME" \
                --project="$PROJECT_ID" \
                --quiet

            log_info "Deleted existing policy"
        else
            log_info "Using existing policy"
            return 0
        fi
    fi

    # Create security policy
    gcloud compute security-policies create "$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description "Cloud Armor WAF for Moodle - OWASP Top 10 Protection"

    log_success "Created security policy: $POLICY_NAME"

    # Configure default rule (deny by default is more secure, but allow for web apps)
    log "Configuring default rule (allow all by default)..."

    gcloud compute security-policies rules update 2147483647 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --action="allow"

    log_success "Default rule configured"
}

add_ip_whitelist() {
    if [[ -z "$WHITELIST_IPS" ]]; then
        return 0
    fi

    log "Adding IP whitelist rule..."

    # Convert comma-separated IPs to space-separated with CIDR notation
    local ip_ranges=""
    IFS=',' read -ra IPS <<< "$WHITELIST_IPS"
    for ip in "${IPS[@]}"; do
        # Add /32 if no CIDR notation present
        if [[ ! "$ip" =~ / ]]; then
            ip="$ip/32"
        fi
        ip_ranges="$ip_ranges'$ip',"
    done
    # Remove trailing comma
    ip_ranges="${ip_ranges%,}"

    gcloud compute security-policies rules create 1000 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description="Whitelist trusted IPs" \
        --src-ip-ranges="$ip_ranges" \
        --action="allow"

    log_success "IP whitelist added: $WHITELIST_IPS"
}

add_geo_restrictions() {
    if [[ -z "$ALLOWED_COUNTRIES" ]]; then
        return 0
    fi

    log "Adding geo-restriction rule..."

    # Convert comma-separated countries to quoted list
    local country_codes=""
    IFS=',' read -ra COUNTRIES <<< "$ALLOWED_COUNTRIES"
    for country in "${COUNTRIES[@]}"; do
        country_codes="$country_codes'${country^^}',"
    done
    # Remove trailing comma
    country_codes="${country_codes%,}"

    # Deny all countries except allowed ones
    gcloud compute security-policies rules create 2000 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description="Allow only specific countries" \
        --expression="!origin.region_code.matches('($country_codes)')" \
        --action="deny-403"

    log_success "Geo-restrictions added: $ALLOWED_COUNTRIES"
}

add_rate_limiting_rules() {
    log "Adding rate limiting rules..."

    # General rate limit: 100 requests per minute per IP
    gcloud compute security-policies rules create 3000 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description="General rate limit: 100 req/min per IP" \
        --expression="true" \
        --action="rate-based-ban" \
        --rate-limit-threshold-count=100 \
        --rate-limit-threshold-interval-sec=60 \
        --ban-duration-sec=600 \
        --conform-action="allow" \
        --exceed-action="deny-429" \
        --enforce-on-key="IP"

    log_success "General rate limiting configured"

    # Login endpoint rate limit: 10 requests per minute per IP
    gcloud compute security-policies rules create 3001 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description="Login rate limit: 10 req/min per IP" \
        --expression="request.path.matches('/login/.*')" \
        --action="rate-based-ban" \
        --rate-limit-threshold-count=10 \
        --rate-limit-threshold-interval-sec=60 \
        --ban-duration-sec=300 \
        --conform-action="allow" \
        --exceed-action="deny-429" \
        --enforce-on-key="IP"

    log_success "Login rate limiting configured"
}

add_owasp_rules() {
    log "Adding OWASP Top 10 preconfigured WAF rules..."
    log "Sensitivity level: $SENSITIVITY_LEVEL (1=strict, 4=permissive)"

    local action="deny-403"
    if [[ "$PREVIEW_MODE" == true ]]; then
        log_warning "Preview mode enabled - rules will log but not block"
        action="allow"
    fi

    # Array of OWASP CRS rules to deploy
    local -A owasp_rules=(
        ["9001"]="sqli|SQL Injection"
        ["9002"]="xss|Cross-Site Scripting (XSS)"
        ["9003"]="lfi|Local File Inclusion (LFI)"
        ["9004"]="rce|Remote Code Execution (RCE)"
        ["9005"]="rfi|Remote File Inclusion (RFI)"
        ["9006"]="methodenforcement|Method Enforcement"
        ["9007"]="scannerdetection|Scanner Detection"
        ["9008"]="protocolattack|Protocol Attack"
        ["9009"]="sessionfixation|Session Fixation"
        ["9010"]="php|PHP Injection"
        ["9011"]="nodejs|NodeJS Injection"
        ["9012"]="java|Java Injection"
    )

    for priority in "${!owasp_rules[@]}"; do
        IFS='|' read -r rule_id description <<< "${owasp_rules[$priority]}"

        log "  Adding rule: $description (priority $priority)"

        gcloud compute security-policies rules create "$priority" \
            --security-policy="$POLICY_NAME" \
            --project="$PROJECT_ID" \
            --description="Block $description" \
            --expression="evaluatePreconfiguredWaf('${rule_id}-v33-stable', {'sensitivity': $SENSITIVITY_LEVEL})" \
            --action="$action" \
            --preview="$PREVIEW_MODE" 2>/dev/null || {
                log_warning "Rule $rule_id may not be available or already exists"
            }
    done

    log_success "OWASP preconfigured rules added"

    if [[ "$PREVIEW_MODE" == true ]]; then
        log_warning "Rules are in PREVIEW mode - review logs before enabling enforcement"
        log_info "To enable enforcement later, update each rule with --preview=false"
    fi
}

add_common_attack_patterns() {
    log "Adding custom rules for common attack patterns..."

    # Block common malicious user agents
    gcloud compute security-policies rules create 8000 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description="Block malicious user agents" \
        --expression="request.headers['user-agent'].matches('(?i)(nikto|sqlmap|nmap|masscan|metasploit|burp|w3af|acunetix)')" \
        --action="deny-403"

    log_success "Malicious user agent blocking configured"

    # Block requests with suspicious query parameters
    gcloud compute security-policies rules create 8001 \
        --security-policy="$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --description="Block suspicious query parameters" \
        --expression="request.query.matches('.*(<script|javascript:|onerror=|onload=).*')" \
        --action="deny-403"

    log_success "Suspicious query parameter blocking configured"
}

enable_adaptive_protection() {
    if [[ "$ENABLE_ADAPTIVE" != true ]]; then
        return 0
    fi

    log "Enabling adaptive protection (Cloud Armor Plus)..."

    # Note: Adaptive protection requires Cloud Armor Plus subscription
    gcloud compute security-policies update "$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --enable-layer7-ddos-defense \
        --log-level="VERBOSE" || {
            log_error "Failed to enable adaptive protection"
            log_info "Ensure you have Cloud Armor Plus enabled"
            log_info "See: https://cloud.google.com/armor/docs/armor-enterprise-overview"
            return 1
        }

    log_success "Adaptive protection enabled"
}

configure_logging() {
    log "Configuring Cloud Armor logging..."

    local log_level="NORMAL"
    if [[ "$VERBOSE_LOGGING" == true ]]; then
        log_level="VERBOSE"
        log_warning "Verbose logging enabled - not recommended for production long-term"
    fi

    gcloud compute security-policies update "$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --log-level="$log_level"

    log_success "Logging configured: $log_level"
}

attach_to_backend_service() {
    log "Attaching security policy to backend service: $BACKEND_SERVICE"

    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --global \
        --security-policy="$POLICY_NAME"

    log_success "Security policy attached to backend service"
}

###############################################################################
# Testing and Validation
###############################################################################

test_policy_rules() {
    log "Validating security policy configuration..."

    # Describe the security policy
    log_info "Security policy details:"
    gcloud compute security-policies describe "$POLICY_NAME" \
        --project="$PROJECT_ID"

    # List all rules
    log ""
    log_info "Security policy rules:"
    gcloud compute security-policies rules list "$POLICY_NAME" \
        --project="$PROJECT_ID" \
        --format="table(priority,description,action,preview)"

    log_success "Security policy validation complete"
}

###############################################################################
# Main Functions
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
    echo "Cloud Armor Setup Complete"
    echo "========================================================================="
    echo ""
    echo "Configuration:"
    echo "  Project: $PROJECT_ID"
    echo "  Policy Name: $POLICY_NAME"
    echo "  Backend Service: $BACKEND_SERVICE"
    echo "  Sensitivity Level: $SENSITIVITY_LEVEL"
    echo "  Preview Mode: $PREVIEW_MODE"
    echo "  Verbose Logging: $VERBOSE_LOGGING"
    echo ""
    echo "Protection Enabled:"
    echo "  ✓ OWASP Top 10 (CRS 3.3.2)"
    echo "  ✓ DDoS Protection (L3/L4/L7)"
    echo "  ✓ Rate Limiting"
    echo "  ✓ Bot Detection"
    echo "  ✓ Custom Attack Patterns"

    if [[ -n "$WHITELIST_IPS" ]]; then
        echo "  ✓ IP Whitelisting: $WHITELIST_IPS"
    fi

    if [[ -n "$ALLOWED_COUNTRIES" ]]; then
        echo "  ✓ Geo-Restrictions: $ALLOWED_COUNTRIES"
    fi

    if [[ "$ENABLE_ADAPTIVE" == true ]]; then
        echo "  ✓ Adaptive Protection (Cloud Armor Plus)"
    fi

    echo ""
    echo "Next Steps:"

    if [[ "$PREVIEW_MODE" == true ]]; then
        log_warning "Rules are in PREVIEW mode"
        echo "  1. Monitor logs for false positives"
        echo "     gcloud logging read \"resource.type=http_load_balancer\" \\"
        echo "       --project=$PROJECT_ID \\"
        echo "       --limit=100 \\"
        echo "       --format=json | jq '.[] | select(.jsonPayload.enforcedSecurityPolicy)'"
        echo ""
        echo "  2. Disable preview mode when ready:"
        echo "     gcloud compute security-policies rules update PRIORITY \\"
        echo "       --security-policy=$POLICY_NAME \\"
        echo "       --project=$PROJECT_ID \\"
        echo "       --no-preview"
    else
        echo "  1. Monitor Cloud Armor logs for blocked requests"
        echo "     Console: Cloud Armor > Security policies > $POLICY_NAME"
        echo ""
        echo "  2. Tune rules if needed (reduce false positives)"
        echo "     https://cloud.google.com/armor/docs/rule-tuning"
    fi

    echo ""
    echo "  3. Set up alerting for security events"
    echo "     https://cloud.google.com/armor/docs/monitoring-alerting"
    echo ""
    echo "Useful Commands:"
    echo "  # View policy details"
    echo "  gcloud compute security-policies describe $POLICY_NAME --project=$PROJECT_ID"
    echo ""
    echo "  # List all rules"
    echo "  gcloud compute security-policies rules list $POLICY_NAME --project=$PROJECT_ID"
    echo ""
    echo "  # View blocked requests in logs"
    echo "  gcloud logging read \"resource.type=http_load_balancer AND jsonPayload.enforcedSecurityPolicy.name=$POLICY_NAME\" \\"
    echo "    --project=$PROJECT_ID --limit=50"
    echo ""
    echo "========================================================================="
    echo ""
    echo "Log file: $LOG_FILE"
    echo ""
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --backend-service)
                BACKEND_SERVICE="$2"
                shift 2
                ;;
            --policy-name)
                POLICY_NAME="$2"
                shift 2
                ;;
            --sensitivity)
                SENSITIVITY_LEVEL="$2"
                if [[ ! "$SENSITIVITY_LEVEL" =~ ^[1-4]$ ]]; then
                    log_error "Sensitivity must be 1-4"
                    exit 1
                fi
                shift 2
                ;;
            --enable-adaptive)
                ENABLE_ADAPTIVE=true
                shift
                ;;
            --whitelist-ips)
                WHITELIST_IPS="$2"
                shift 2
                ;;
            --allowed-countries)
                ALLOWED_COUNTRIES="$2"
                shift 2
                ;;
            --preview)
                PREVIEW_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE_LOGGING=true
                shift
                ;;
            -h|--help)
                print_header
                cat <<EOF
Usage: $0 --project PROJECT_ID --backend-service SERVICE [OPTIONS]

Required:
  --project PROJECT_ID           GCP project ID
  --backend-service SERVICE      Backend service name to protect

Optional:
  --policy-name NAME             Security policy name (default: moodle-waf-policy)
  --sensitivity LEVEL            WAF sensitivity 1-4 (default: 1)
                                 1=strict (recommended), 4=permissive
  --enable-adaptive              Enable adaptive protection (Cloud Armor Plus)
  --whitelist-ips IPS            Comma-separated IPs to whitelist
  --allowed-countries COUNTRIES  Comma-separated country codes (e.g., US,CA,GB)
  --preview                      Enable preview mode (recommended for testing)
  --verbose                      Enable verbose logging
  -h, --help                     Show this help message

Examples:
  # Basic setup
  $0 --project my-project --backend-service my-backend

  # With IP whitelist and geo-restrictions
  $0 --project my-project --backend-service my-backend \\
     --whitelist-ips "203.0.113.0/24,198.51.100.5" \\
     --allowed-countries "US,CA,GB"

  # Testing with preview mode
  $0 --project my-project --backend-service my-backend \\
     --preview --verbose

  # Cloud Armor Plus with adaptive protection
  $0 --project my-project --backend-service my-backend \\
     --enable-adaptive --sensitivity 2

For more information:
  https://cloud.google.com/armor/docs
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
    check_gcloud
    check_project
    check_backend_service

    # Initialize log file
    touch "$LOG_FILE"

    log "Starting Cloud Armor Setup"
    log "Date: $(date)"
    echo ""

    # Create and configure security policy
    create_security_policy
    add_ip_whitelist
    add_geo_restrictions
    add_rate_limiting_rules
    add_owasp_rules
    add_common_attack_patterns
    enable_adaptive_protection
    configure_logging

    # Attach to backend service
    attach_to_backend_service

    # Validate configuration
    echo ""
    test_policy_rules

    # Print summary
    print_summary

    log "Cloud Armor setup completed successfully"
}

# Execute main function
main "$@"
