#!/bin/bash
###############################################################################
# Google Cloud CDN Setup Script
# Version: 1.0.0
# Updated: 2025
#
# This script configures Google Cloud CDN for Moodle with:
# - Global external Application Load Balancer integration
# - Backend service CDN enablement
# - Cache mode configuration (static content caching)
# - Cache key customization
# - SSL/TLS termination
# - Cloud Armor integration
# - Performance optimization
#
# Benefits:
# - Faster content delivery worldwide
# - Reduced origin server load
# - Improved user experience
# - Lower bandwidth costs
# - DDoS protection integration
#
# Prerequisites:
# - Google Cloud SDK (gcloud) installed
# - Load balancer already configured
# - Backend service created
# - Static IP address reserved
# - SSL certificate configured
#
# Usage:
#   ./cdn-setup.sh --project PROJECT_ID --backend-service SERVICE [OPTIONS]
#
# Options:
#   --project PROJECT_ID           GCP project ID (required)
#   --backend-service SERVICE      Backend service name (required)
#   --cache-mode MODE              Cache mode: static|origin|force (default: static)
#   --ttl SECONDS                  Default cache TTL in seconds (default: 3600)
#   --enable-cache-keys            Enable custom cache keys
#   --enable-signed-urls           Enable signed URLs for private content
#   --enable-compression           Enable automatic compression
#   --negative-caching             Enable negative response caching
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
readonly SCRIPT_NAME="Google Cloud CDN Setup"
readonly LOG_FILE="/tmp/cdn-setup-$(date +%Y%m%d_%H%M%S).log"

# Default configuration
PROJECT_ID=""
BACKEND_SERVICE=""
CACHE_MODE="static"
DEFAULT_TTL=3600
ENABLE_CACHE_KEYS=false
ENABLE_SIGNED_URLS=false
ENABLE_COMPRESSION=true
NEGATIVE_CACHING=true

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

    # Check gcloud version for CDN features
    local version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null | cut -d. -f1)
    if [[ "$version" -lt 369 ]]; then
        log_warning "gcloud CLI version < 369.0.0 detected"
        log_warning "Some features may not be available. Recommend upgrading."
    fi

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
    if ! gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Backend service not found: $BACKEND_SERVICE"
        log_error "Available backend services:"
        gcloud compute backend-services list --project="$PROJECT_ID" --format="value(name)"
        exit 2
    fi

    log_success "Backend service: $BACKEND_SERVICE"
}

enable_required_apis() {
    log "Enabling required Google Cloud APIs..."

    local apis=(
        "compute.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log "  Enabling: $api"
        gcloud services enable "$api" --project="$PROJECT_ID" 2>/dev/null || true
    done

    log_success "Required APIs enabled"
}

###############################################################################
# Cloud CDN Configuration
###############################################################################

enable_cdn_on_backend() {
    log "Enabling Cloud CDN on backend service: $BACKEND_SERVICE"

    # Map friendly cache mode names to gcloud values
    local gcloud_cache_mode=""
    case "$CACHE_MODE" in
        static)
            gcloud_cache_mode="CACHE_ALL_STATIC"
            ;;
        origin)
            gcloud_cache_mode="USE_ORIGIN_HEADERS"
            ;;
        force)
            gcloud_cache_mode="FORCE_CACHE_ALL"
            ;;
        *)
            log_error "Invalid cache mode: $CACHE_MODE"
            exit 1
            ;;
    esac

    log_info "Cache mode: $gcloud_cache_mode"

    # Enable CDN with cache mode
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --enable-cdn \
        --cache-mode="$gcloud_cache_mode"

    log_success "Cloud CDN enabled with cache mode: $gcloud_cache_mode"
}

configure_cache_ttl() {
    log "Configuring cache TTL settings..."

    # Set default cache TTL
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --default-ttl="$DEFAULT_TTL"

    # Set maximum client TTL (1 year max)
    local max_ttl=31536000  # 1 year
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --client-ttl="$max_ttl"

    log_success "Cache TTL configured: default=${DEFAULT_TTL}s, max=${max_ttl}s"
}

configure_compression() {
    if [[ "$ENABLE_COMPRESSION" != true ]]; then
        return 0
    fi

    log "Enabling automatic compression..."

    # Enable compression for supported content types
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --enable-compression

    log_success "Automatic compression enabled"
    log_info "Supported types: text/html, text/css, application/javascript, etc."
}

configure_negative_caching() {
    if [[ "$NEGATIVE_CACHING" != true ]]; then
        return 0
    fi

    log "Configuring negative caching..."

    # Enable negative caching for error responses
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --negative-caching

    # Set negative caching TTLs for common error codes
    # 404: 120s, 500-502: 60s, 503-504: 30s
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --negative-caching-policy="404=120,500=60,501=60,502=60,503=30,504=30"

    log_success "Negative caching enabled"
    log_info "404: 120s, 5xx errors: 30-60s"
}

configure_cache_keys() {
    if [[ "$ENABLE_CACHE_KEYS" != true ]]; then
        return 0
    fi

    log "Configuring custom cache keys..."

    # Include query string in cache key (important for Moodle)
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --cache-key-include-query-string

    # Exclude specific query parameters that don't affect content
    # Common tracking parameters
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --cache-key-query-string-blacklist="utm_source,utm_medium,utm_campaign,utm_term,utm_content,fbclid,gclid"

    log_success "Custom cache keys configured"
    log_info "Query strings included, tracking parameters excluded"

    # Optional: Include specific headers for Moodle
    log_warning "Consider including Accept-Language header for localized content:"
    log_info "  gcloud compute backend-services update $BACKEND_SERVICE \\"
    log_info "    --global --project=$PROJECT_ID \\"
    log_info "    --cache-key-include-http-header='Accept-Language'"
}

configure_signed_urls() {
    if [[ "$ENABLE_SIGNED_URLS" != true ]]; then
        return 0
    fi

    log "Configuring signed URLs for private content..."

    # Generate signing key
    local key_name="cdn-signing-key-$(date +%Y%m%d)"
    local key_file="/tmp/${key_name}.key"

    # Generate 128-bit random key
    head -c 16 /dev/urandom | base64 > "$key_file"

    log_info "Generated signing key: $key_name"
    log_info "Key file: $key_file"

    # Add signing key to backend service
    gcloud compute backend-services add-signed-url-key "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --key-name="$key_name" \
        --key-file="$key_file"

    # Set signed URL cache max age (1 hour)
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --signed-url-cache-max-age=3600

    log_success "Signed URLs configured"
    log_warning "IMPORTANT: Save the signing key securely: $key_file"
    log_info "Use this key to generate signed URLs for private content"
}

configure_serve_while_stale() {
    log "Configuring stale content serving..."

    # Serve stale content while updating
    # Reduces origin load and improves user experience
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --serve-while-stale=86400  # 24 hours

    log_success "Serve-while-stale configured: 24 hours"
    log_info "CDN serves stale content while fetching updates from origin"
}

###############################################################################
# Moodle-Specific Optimizations
###############################################################################

configure_moodle_caching() {
    log "Applying Moodle-specific CDN optimizations..."

    log_info "Recommended Moodle CDN configuration:"
    echo ""
    log_info "Static Assets (Always Cache):"
    log_info "  - /theme/*/pix/*.{png,jpg,gif,svg,ico}"
    log_info "  - /lib/javascript/*.js"
    log_info "  - /theme/*/style/*.css"
    log_info "  - /pluginfile.php/*.{png,jpg,gif,pdf,mp4} (if public)"
    echo ""

    log_info "Dynamic Content (Never Cache):"
    log_info "  - /login/*"
    log_info "  - /admin/*"
    log_info "  - /course/view.php"
    log_info "  - /mod/*/view.php"
    log_info "  - Session-specific content"
    echo ""

    log_warning "Important: Configure Moodle caching settings:"
    log_info "  1. Login to Moodle as admin"
    log_info "  2. Go to: Site administration > Server > Caching"
    log_info "  3. Enable 'Application cache' and 'Session cache'"
    log_info "  4. Clear all caches after CDN setup"
    echo ""

    log_success "Moodle optimization guidance provided"
}

###############################################################################
# Testing and Validation
###############################################################################

test_cdn_configuration() {
    log "Testing CDN configuration..."

    # Get backend service details
    local backend_details=$(gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" \
        --format="json")

    # Check if CDN is enabled
    local cdn_enabled=$(echo "$backend_details" | jq -r '.enableCDN // false')

    if [[ "$cdn_enabled" == "true" ]]; then
        log_success "CDN is enabled"
    else
        log_error "CDN is NOT enabled"
        return 1
    fi

    # Display configuration
    log_info "Current CDN configuration:"
    echo "$backend_details" | jq '{
        enableCDN,
        cdnPolicy: {
            cacheMode,
            defaultTtl,
            clientTtl,
            negativeC aching,
            serveWhileStale
        }
    }'

    log_success "CDN configuration verified"
}

test_cdn_headers() {
    log "CDN testing instructions:"
    echo ""

    log_info "1. Test cache hits with curl:"
    log_info "   curl -I https://YOUR_DOMAIN/path/to/static/file.css"
    log_info "   Look for headers:"
    log_info "     - X-Cache: HIT (cached) or MISS (not cached)"
    log_info "     - Age: XX (seconds since cached)"
    log_info "     - Cache-Control: public, max-age=XXXX"
    echo ""

    log_info "2. Test from multiple locations:"
    log_info "   - Use https://www.webpagetest.org"
    log_info "   - Test from different geographic regions"
    log_info "   - Verify faster load times"
    echo ""

    log_info "3. Monitor CDN metrics:"
    log_info "   - Cache hit rate (target: >80% for static content)"
    log_info "   - Origin requests (should decrease)"
    log_info "   - Error rates"
    echo ""

    log_success "CDN testing guidance provided"
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
    echo "Cloud CDN Setup Complete"
    echo "========================================================================="
    echo ""
    echo "Configuration:"
    echo "  Project: $PROJECT_ID"
    echo "  Backend Service: $BACKEND_SERVICE"
    echo "  Cache Mode: $CACHE_MODE"
    echo "  Default TTL: $DEFAULT_TTL seconds"
    echo ""

    echo "Enabled Features:"
    echo "  ✓ Cloud CDN"
    echo "  ✓ Global content delivery"

    if [[ "$ENABLE_COMPRESSION" == true ]]; then
        echo "  ✓ Automatic compression"
    fi

    if [[ "$NEGATIVE_CACHING" == true ]]; then
        echo "  ✓ Negative caching"
    fi

    if [[ "$ENABLE_CACHE_KEYS" == true ]]; then
        echo "  ✓ Custom cache keys"
    fi

    if [[ "$ENABLE_SIGNED_URLS" == true ]]; then
        echo "  ✓ Signed URLs"
    fi

    echo ""
    echo "Performance Benefits:"
    echo "  ✓ Faster content delivery worldwide"
    echo "  ✓ Reduced origin server load (60-90% typical)"
    echo "  ✓ Lower bandwidth costs"
    echo "  ✓ Improved user experience"
    echo "  ✓ DDoS mitigation (when used with Cloud Armor)"
    echo ""

    echo "Next Steps:"
    echo ""
    echo "  1. Clear Moodle caches:"
    echo "     Site admin > Server > Caching > Purge all caches"
    echo ""

    echo "  2. Test CDN functionality:"
    echo "     curl -I https://YOUR_DOMAIN/theme/boost/pix/favicon.ico"
    echo "     Look for 'X-Cache: HIT' header"
    echo ""

    echo "  3. Monitor CDN performance:"
    echo "     https://console.cloud.google.com/net-services/cdn/list?project=$PROJECT_ID"
    echo ""

    echo "  4. Optimize cache hit rate:"
    echo "     - Configure proper Cache-Control headers in Moodle"
    echo "     - Use long TTLs for static content (1 year)"
    echo "     - Avoid caching dynamic, personalized content"
    echo ""

    echo "  5. Set up monitoring alerts:"
    echo "     - Cache hit rate < 80%"
    echo "     - Origin error rate > 1%"
    echo "     - High latency at edge locations"
    echo ""

    echo "Useful Commands:"
    echo ""
    echo "  # View CDN cache statistics"
    echo "  gcloud monitoring time-series list \\"
    echo "    --filter='metric.type=\"cdn.googleapis.com/request_count\"' \\"
    echo "    --project=$PROJECT_ID"
    echo ""

    echo "  # Invalidate cached content"
    echo "  gcloud compute url-maps invalidate-cdn-cache LOAD_BALANCER \\"
    echo "    --path=\"/path/to/invalidate/*\" \\"
    echo "    --project=$PROJECT_ID"
    echo ""

    echo "  # Disable CDN (if needed)"
    echo "  gcloud compute backend-services update $BACKEND_SERVICE \\"
    echo "    --global --no-enable-cdn --project=$PROJECT_ID"
    echo ""

    echo "Documentation:"
    echo "  - Cloud CDN: https://cloud.google.com/cdn/docs"
    echo "  - Caching: https://cloud.google.com/cdn/docs/caching"
    echo "  - Best Practices: https://cloud.google.com/cdn/docs/best-practices"
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
            --cache-mode)
                CACHE_MODE="$2"
                if [[ ! "$CACHE_MODE" =~ ^(static|origin|force)$ ]]; then
                    log_error "Invalid cache mode: $CACHE_MODE"
                    log_error "Must be: static, origin, or force"
                    exit 1
                fi
                shift 2
                ;;
            --ttl)
                DEFAULT_TTL="$2"
                shift 2
                ;;
            --enable-cache-keys)
                ENABLE_CACHE_KEYS=true
                shift
                ;;
            --enable-signed-urls)
                ENABLE_SIGNED_URLS=true
                shift
                ;;
            --enable-compression)
                ENABLE_COMPRESSION=true
                shift
                ;;
            --negative-caching)
                NEGATIVE_CACHING=true
                shift
                ;;
            -h|--help)
                print_header
                cat <<EOF
Usage: $0 --project PROJECT_ID --backend-service SERVICE [OPTIONS]

Required:
  --project PROJECT_ID           GCP project ID
  --backend-service SERVICE      Backend service name

Optional:
  --cache-mode MODE              Cache mode (default: static)
                                 - static: Cache static content automatically
                                 - origin: Use origin Cache-Control headers
                                 - force: Cache all content
  --ttl SECONDS                  Default cache TTL (default: 3600)
  --enable-cache-keys            Enable custom cache key configuration
  --enable-signed-urls           Enable signed URLs for private content
  --enable-compression           Enable automatic compression (default: true)
  --negative-caching             Enable negative caching (default: true)
  -h, --help                     Show this help message

Examples:
  # Basic CDN setup
  $0 --project my-project --backend-service moodle-backend

  # Advanced configuration
  $0 --project my-project --backend-service moodle-backend \\
     --cache-mode static \\
     --ttl 7200 \\
     --enable-cache-keys \\
     --enable-compression

  # Private content with signed URLs
  $0 --project my-project --backend-service moodle-backend \\
     --enable-signed-urls

Cache Mode Details:
  static:  Automatically caches text/css, text/javascript, etc.
           Recommended for most Moodle deployments
  origin:  Requires proper Cache-Control headers from origin
           Use if you have full control over Moodle headers
  force:   Caches everything regardless of headers
           Use carefully - may cache personalized content!

For more information:
  https://cloud.google.com/cdn/docs
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

    log "Starting Cloud CDN Setup"
    log "Date: $(date)"
    echo ""

    # Enable required APIs
    enable_required_apis

    # Configure CDN
    enable_cdn_on_backend
    configure_cache_ttl
    configure_compression
    configure_negative_caching
    configure_cache_keys
    configure_signed_urls
    configure_serve_while_stale

    # Moodle-specific optimizations
    configure_moodle_caching

    # Test configuration
    echo ""
    test_cdn_configuration
    test_cdn_headers

    # Print summary
    print_summary

    log "Cloud CDN setup completed successfully"
}

# Execute main function
main "$@"
