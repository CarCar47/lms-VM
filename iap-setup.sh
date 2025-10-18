#!/bin/bash
###############################################################################
# Identity-Aware Proxy (IAP) and Cloud NAT Setup Script
# Version: 1.0.0
# Updated: 2025
#
# This script configures:
# - Cloud NAT for outbound internet access from private VMs
# - Identity-Aware Proxy (IAP) for secure zero-trust SSH/HTTPS access
# - OAuth consent screen and credentials
# - IAP access policies with user/group permissions
#
# Benefits:
# - Zero-trust security model
# - No public IP addresses needed for VMs
# - Centralized access control
# - Audit logging for all access
# - Context-aware access policies
#
# Prerequisites:
# - Google Cloud SDK (gcloud) installed
# - Project ID configured
# - Appropriate IAM permissions (Compute Admin, Security Admin)
# - VPC network and subnet already created
#
# Usage:
#   ./iap-setup.sh --project PROJECT_ID --region REGION [OPTIONS]
#
# Options:
#   --project PROJECT_ID        GCP project ID (required)
#   --region REGION             Region for resources (required)
#   --network NETWORK           VPC network name (default: default)
#   --subnet SUBNET             Subnet name (default: default)
#   --backend-service SERVICE   Backend service for IAP (optional)
#   --allowed-users EMAILS      Comma-separated user emails for IAP access
#   --allowed-groups GROUPS     Comma-separated group emails for IAP access
#   --enable-ssh-iap            Enable IAP for SSH access
#   --enable-https-iap          Enable IAP for HTTPS access
#   --skip-nat                  Skip Cloud NAT setup
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
readonly SCRIPT_NAME="IAP and Cloud NAT Setup"
readonly LOG_FILE="/tmp/iap-setup-$(date +%Y%m%d_%H%M%S).log"

# Default configuration
PROJECT_ID=""
REGION=""
NETWORK="default"
SUBNET="default"
BACKEND_SERVICE=""
ALLOWED_USERS=""
ALLOWED_GROUPS=""
ENABLE_SSH_IAP=false
ENABLE_HTTPS_IAP=false
SKIP_NAT=false

# Resource names
ROUTER_NAME="nat-router"
NAT_NAME="nat-config"
FIREWALL_IAP_SSH="allow-iap-ssh"
FIREWALL_IAP_HTTPS="allow-iap-https"

# IAP IP ranges (Google Cloud IAP proxy IPs)
readonly IAP_IP_RANGE="35.235.240.0/20"

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

check_region() {
    if [[ -z "$REGION" ]]; then
        log_error "Region not specified"
        log_error "Use: --region REGION"
        log_error "Available regions: gcloud compute regions list"
        exit 2
    fi

    # Verify region exists
    if ! gcloud compute regions describe "$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Invalid region: $REGION"
        log_error "List regions: gcloud compute regions list"
        exit 2
    fi

    log_success "Region: $REGION"
}

enable_required_apis() {
    log "Enabling required Google Cloud APIs..."

    local apis=(
        "compute.googleapis.com"
        "iap.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log "  Enabling: $api"
        gcloud services enable "$api" --project="$PROJECT_ID" 2>/dev/null || true
    done

    log_success "Required APIs enabled"
}

###############################################################################
# Cloud NAT Configuration
###############################################################################

setup_cloud_nat() {
    if [[ "$SKIP_NAT" == true ]]; then
        log_warning "Skipping Cloud NAT setup (--skip-nat)"
        return 0
    fi

    log "Setting up Cloud NAT for outbound internet access..."

    # Check if network exists
    if ! gcloud compute networks describe "$NETWORK" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "VPC network not found: $NETWORK"
        log_error "Create network first or specify existing network with --network"
        exit 1
    fi

    # Create Cloud Router (required for Cloud NAT)
    log "Creating Cloud Router: $ROUTER_NAME"

    if gcloud compute routers describe "$ROUTER_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Cloud Router already exists: $ROUTER_NAME"
    else
        gcloud compute routers create "$ROUTER_NAME" \
            --network="$NETWORK" \
            --region="$REGION" \
            --project="$PROJECT_ID"

        log_success "Cloud Router created"
    fi

    # Create NAT configuration
    log "Creating Cloud NAT: $NAT_NAME"

    if gcloud compute routers nats describe "$NAT_NAME" \
        --router="$ROUTER_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Cloud NAT already exists: $NAT_NAME"
    else
        gcloud compute routers nats create "$NAT_NAME" \
            --router="$ROUTER_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --auto-allocate-nat-external-ips \
            --nat-all-subnet-ip-ranges \
            --enable-logging

        log_success "Cloud NAT created and configured"
    fi

    # Display NAT configuration
    log_info "Cloud NAT details:"
    gcloud compute routers nats describe "$NAT_NAME" \
        --router="$ROUTER_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="yaml(name,natIpAllocateOption,sourceSubnetworkIpRangesToNat,logConfig)"
}

###############################################################################
# IAP Configuration
###############################################################################

configure_oauth_consent_screen() {
    log "Configuring OAuth consent screen for IAP..."

    # Note: OAuth consent screen must be configured via Cloud Console UI
    # or using the gcloud alpha/beta commands

    log_warning "OAuth consent screen configuration:"
    log_info "  1. Go to: https://console.cloud.google.com/apis/credentials/consent"
    log_info "  2. Select 'Internal' user type (for Google Workspace)"
    log_info "  3. Fill in app name, support email, and developer contact"
    log_info "  4. Add scopes: email, profile, openid"
    log_info "  5. Save and continue"
    echo ""

    # Check if OAuth consent is already configured
    local brand_exists=false
    if gcloud iap oauth-brands list --project="$PROJECT_ID" 2>/dev/null | grep -q "name:"; then
        brand_exists=true
        log_success "OAuth consent screen already configured"
    else
        log_warning "OAuth consent screen not configured"
        read -p "Have you configured the OAuth consent screen? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Please configure OAuth consent screen first"
            log_info "Visit: https://console.cloud.google.com/apis/credentials/consent?project=$PROJECT_ID"
            exit 1
        fi
    fi
}

setup_iap_firewall_rules() {
    log "Setting up IAP firewall rules..."

    # Allow IAP for SSH (TCP port 22)
    if [[ "$ENABLE_SSH_IAP" == true ]]; then
        log "Creating firewall rule for IAP SSH access"

        if gcloud compute firewall-rules describe "$FIREWALL_IAP_SSH" \
            --project="$PROJECT_ID" >/dev/null 2>&1; then
            log_warning "Firewall rule already exists: $FIREWALL_IAP_SSH"
        else
            gcloud compute firewall-rules create "$FIREWALL_IAP_SSH" \
                --network="$NETWORK" \
                --project="$PROJECT_ID" \
                --direction=INGRESS \
                --action=ALLOW \
                --rules=tcp:22 \
                --source-ranges="$IAP_IP_RANGE" \
                --description="Allow SSH from IAP"

            log_success "IAP SSH firewall rule created"
        fi
    fi

    # Allow IAP for HTTPS (TCP port 443)
    if [[ "$ENABLE_HTTPS_IAP" == true ]]; then
        log "Creating firewall rule for IAP HTTPS access"

        if gcloud compute firewall-rules describe "$FIREWALL_IAP_HTTPS" \
            --project="$PROJECT_ID" >/dev/null 2>&1; then
            log_warning "Firewall rule already exists: $FIREWALL_IAP_HTTPS"
        else
            gcloud compute firewall-rules create "$FIREWALL_IAP_HTTPS" \
                --network="$NETWORK" \
                --project="$PROJECT_ID" \
                --direction=INGRESS \
                --action=ALLOW \
                --rules=tcp:443 \
                --source-ranges="$IAP_IP_RANGE" \
                --description="Allow HTTPS from IAP"

            log_success "IAP HTTPS firewall rule created"
        fi
    fi
}

enable_iap_for_backend_service() {
    if [[ -z "$BACKEND_SERVICE" ]]; then
        log_warning "No backend service specified, skipping IAP enablement"
        log_info "Enable IAP later with:"
        log_info "  gcloud compute backend-services update SERVICE_NAME \\"
        log_info "    --global --iap=enabled --project=$PROJECT_ID"
        return 0
    fi

    log "Enabling IAP for backend service: $BACKEND_SERVICE"

    # Check if backend service exists
    if ! gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --global \
        --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Backend service not found: $BACKEND_SERVICE"
        log_error "Available backend services:"
        gcloud compute backend-services list --project="$PROJECT_ID" --format="value(name)"
        exit 1
    fi

    # Enable IAP
    gcloud compute backend-services update "$BACKEND_SERVICE" \
        --global \
        --iap=enabled \
        --project="$PROJECT_ID"

    log_success "IAP enabled for backend service"
}

configure_iap_access_policies() {
    if [[ -z "$ALLOWED_USERS" ]] && [[ -z "$ALLOWED_GROUPS" ]]; then
        log_warning "No users or groups specified for IAP access"
        log_info "Grant access later with:"
        log_info "  gcloud iap web add-iam-policy-binding \\"
        log_info "    --member='user:email@example.com' \\"
        log_info "    --role='roles/iap.httpsResourceAccessor' \\"
        log_info "    --project=$PROJECT_ID"
        return 0
    fi

    log "Configuring IAP access policies..."

    # Grant access to users
    if [[ -n "$ALLOWED_USERS" ]]; then
        IFS=',' read -ra USERS <<< "$ALLOWED_USERS"
        for user in "${USERS[@]}"; do
            user=$(echo "$user" | xargs) # Trim whitespace

            log "  Granting IAP access to user: $user"

            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="user:$user" \
                --role="roles/iap.httpsResourceAccessor" \
                --condition=None \
                >/dev/null 2>&1 || log_warning "Failed to grant access to $user"

            # Also grant SSH access if enabled
            if [[ "$ENABLE_SSH_IAP" == true ]]; then
                gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                    --member="user:$user" \
                    --role="roles/iap.tunnelResourceAccessor" \
                    --condition=None \
                    >/dev/null 2>&1 || log_warning "Failed to grant SSH access to $user"
            fi
        done

        log_success "User access policies configured"
    fi

    # Grant access to groups
    if [[ -n "$ALLOWED_GROUPS" ]]; then
        IFS=',' read -ra GROUPS <<< "$ALLOWED_GROUPS"
        for group in "${GROUPS[@]}"; do
            group=$(echo "$group" | xargs) # Trim whitespace

            log "  Granting IAP access to group: $group"

            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="group:$group" \
                --role="roles/iap.httpsResourceAccessor" \
                --condition=None \
                >/dev/null 2>&1 || log_warning "Failed to grant access to $group"

            # Also grant SSH access if enabled
            if [[ "$ENABLE_SSH_IAP" == true ]]; then
                gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                    --member="group:$group" \
                    --role="roles/iap.tunnelResourceAccessor" \
                    --condition=None \
                    >/dev/null 2>&1 || log_warning "Failed to grant SSH access to $group"
            fi
        done

        log_success "Group access policies configured"
    fi
}

setup_iap_ssh_wrapper() {
    if [[ "$ENABLE_SSH_IAP" != true ]]; then
        return 0
    fi

    log "Creating IAP SSH wrapper script..."

    # Create helper script for SSH via IAP
    cat > /tmp/iap-ssh.sh << 'EOF'
#!/bin/bash
# IAP SSH Wrapper Script
# Usage: ./iap-ssh.sh INSTANCE_NAME [ZONE] [PROJECT]

INSTANCE_NAME="$1"
ZONE="${2:-us-central1-a}"
PROJECT="${3:-$(gcloud config get-value project)}"

if [[ -z "$INSTANCE_NAME" ]]; then
    echo "Usage: $0 INSTANCE_NAME [ZONE] [PROJECT]"
    echo ""
    echo "Examples:"
    echo "  $0 my-instance"
    echo "  $0 my-instance us-east1-b"
    echo "  $0 my-instance us-east1-b my-project"
    exit 1
fi

echo "Connecting to $INSTANCE_NAME via IAP..."
gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --tunnel-through-iap
EOF

    chmod +x /tmp/iap-ssh.sh

    log_success "IAP SSH wrapper created: /tmp/iap-ssh.sh"
    log_info "Usage: /tmp/iap-ssh.sh INSTANCE_NAME [ZONE] [PROJECT]"
}

###############################################################################
# Testing and Validation
###############################################################################

test_nat_connectivity() {
    if [[ "$SKIP_NAT" == true ]]; then
        return 0
    fi

    log "Cloud NAT connectivity test:"
    log_info "To test NAT from a VM without external IP:"
    log_info "  1. SSH to a VM in the subnet (via IAP or bastion)"
    log_info "  2. Run: curl -s https://api.ipify.org"
    log_info "  3. Verify the returned IP is the NAT gateway IP"
    echo ""
}

test_iap_access() {
    log "IAP access test:"

    if [[ "$ENABLE_SSH_IAP" == true ]]; then
        log_info "Test SSH via IAP:"
        log_info "  gcloud compute ssh INSTANCE_NAME \\"
        log_info "    --zone=ZONE \\"
        log_info "    --tunnel-through-iap \\"
        log_info "    --project=$PROJECT_ID"
        echo ""
    fi

    if [[ "$ENABLE_HTTPS_IAP" == true ]] && [[ -n "$BACKEND_SERVICE" ]]; then
        log_info "Test HTTPS via IAP:"
        log_info "  1. Get the load balancer IP/domain"
        log_info "  2. Access via browser (will redirect to Google login)"
        log_info "  3. Only authorized users can access the application"
        echo ""
    fi
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
    echo "IAP and Cloud NAT Setup Complete"
    echo "========================================================================="
    echo ""
    echo "Configuration:"
    echo "  Project: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Network: $NETWORK"
    echo "  Subnet: $SUBNET"
    echo ""

    if [[ "$SKIP_NAT" != true ]]; then
        echo "Cloud NAT:"
        echo "  ✓ Router: $ROUTER_NAME"
        echo "  ✓ NAT Config: $NAT_NAME"
        echo "  ✓ Auto-allocated external IPs"
        echo "  ✓ Logging enabled"
        echo ""
    fi

    echo "Identity-Aware Proxy (IAP):"

    if [[ "$ENABLE_SSH_IAP" == true ]]; then
        echo "  ✓ SSH access enabled"
        echo "  ✓ Firewall rule: $FIREWALL_IAP_SSH"
    fi

    if [[ "$ENABLE_HTTPS_IAP" == true ]]; then
        echo "  ✓ HTTPS access enabled"
        echo "  ✓ Firewall rule: $FIREWALL_IAP_HTTPS"
    fi

    if [[ -n "$BACKEND_SERVICE" ]]; then
        echo "  ✓ Backend service: $BACKEND_SERVICE"
    fi

    if [[ -n "$ALLOWED_USERS" ]]; then
        echo "  ✓ Authorized users: $ALLOWED_USERS"
    fi

    if [[ -n "$ALLOWED_GROUPS" ]]; then
        echo "  ✓ Authorized groups: $ALLOWED_GROUPS"
    fi

    echo ""
    echo "Security Benefits:"
    echo "  ✓ Zero-trust access control"
    echo "  ✓ No public IPs required on VMs"
    echo "  ✓ Centralized authentication"
    echo "  ✓ Detailed audit logging"
    echo "  ✓ Context-aware access policies"
    echo ""
    echo "Next Steps:"

    if [[ "$ENABLE_SSH_IAP" == true ]]; then
        echo "  1. SSH to instances via IAP:"
        echo "     gcloud compute ssh INSTANCE_NAME \\"
        echo "       --zone=ZONE \\"
        echo "       --tunnel-through-iap \\"
        echo "       --project=$PROJECT_ID"
        echo ""
        echo "     Or use the wrapper script:"
        echo "     /tmp/iap-ssh.sh INSTANCE_NAME ZONE"
        echo ""
    fi

    echo "  2. Monitor IAP access logs:"
    echo "     https://console.cloud.google.com/logs/query;query=resource.type%3D%22gce_backend_service%22?project=$PROJECT_ID"
    echo ""

    echo "  3. Manage IAP access policies:"
    echo "     https://console.cloud.google.com/security/iap?project=$PROJECT_ID"
    echo ""

    if [[ "$SKIP_NAT" != true ]]; then
        echo "  4. View Cloud NAT gateway IPs:"
        echo "     gcloud compute routers nats describe $NAT_NAME \\"
        echo "       --router=$ROUTER_NAME \\"
        echo "       --region=$REGION \\"
        echo "       --project=$PROJECT_ID"
        echo ""
    fi

    echo "Useful Commands:"
    echo ""
    echo "  # Grant IAP access to a user"
    echo "  gcloud projects add-iam-policy-binding $PROJECT_ID \\"
    echo "    --member='user:email@example.com' \\"
    echo "    --role='roles/iap.httpsResourceAccessor'"
    echo ""
    echo "  # Revoke IAP access"
    echo "  gcloud projects remove-iam-policy-binding $PROJECT_ID \\"
    echo "    --member='user:email@example.com' \\"
    echo "    --role='roles/iap.httpsResourceAccessor'"
    echo ""
    echo "  # List IAP access policies"
    echo "  gcloud projects get-iam-policy $PROJECT_ID \\"
    echo "    --flatten='bindings[].members' \\"
    echo "    --filter='bindings.role:roles/iap'"
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
            --region)
                REGION="$2"
                shift 2
                ;;
            --network)
                NETWORK="$2"
                shift 2
                ;;
            --subnet)
                SUBNET="$2"
                shift 2
                ;;
            --backend-service)
                BACKEND_SERVICE="$2"
                shift 2
                ;;
            --allowed-users)
                ALLOWED_USERS="$2"
                shift 2
                ;;
            --allowed-groups)
                ALLOWED_GROUPS="$2"
                shift 2
                ;;
            --enable-ssh-iap)
                ENABLE_SSH_IAP=true
                shift
                ;;
            --enable-https-iap)
                ENABLE_HTTPS_IAP=true
                shift
                ;;
            --skip-nat)
                SKIP_NAT=true
                shift
                ;;
            -h|--help)
                print_header
                cat <<EOF
Usage: $0 --project PROJECT_ID --region REGION [OPTIONS]

Required:
  --project PROJECT_ID        GCP project ID
  --region REGION             Region for Cloud NAT and router

Optional:
  --network NETWORK           VPC network name (default: default)
  --subnet SUBNET             Subnet name (default: default)
  --backend-service SERVICE   Backend service for IAP HTTPS
  --allowed-users EMAILS      Comma-separated user emails for IAP
  --allowed-groups GROUPS     Comma-separated group emails for IAP
  --enable-ssh-iap            Enable IAP for SSH access
  --enable-https-iap          Enable IAP for HTTPS access
  --skip-nat                  Skip Cloud NAT setup
  -h, --help                  Show this help message

Examples:
  # Setup Cloud NAT and IAP for SSH
  $0 --project my-project --region us-central1 --enable-ssh-iap

  # Setup with specific users
  $0 --project my-project --region us-central1 \\
     --enable-ssh-iap \\
     --allowed-users "user1@example.com,user2@example.com"

  # Full setup with HTTPS IAP
  $0 --project my-project --region us-central1 \\
     --enable-ssh-iap --enable-https-iap \\
     --backend-service moodle-backend \\
     --allowed-users "admin@example.com"

  # Skip NAT, only setup IAP
  $0 --project my-project --region us-central1 \\
     --skip-nat --enable-ssh-iap

For more information:
  https://cloud.google.com/iap/docs
  https://cloud.google.com/nat/docs
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
    check_region

    # Initialize log file
    touch "$LOG_FILE"

    log "Starting IAP and Cloud NAT Setup"
    log "Date: $(date)"
    echo ""

    # Enable required APIs
    enable_required_apis

    # Setup Cloud NAT
    setup_cloud_nat

    # Setup IAP
    if [[ "$ENABLE_SSH_IAP" == true ]] || [[ "$ENABLE_HTTPS_IAP" == true ]]; then
        configure_oauth_consent_screen
        setup_iap_firewall_rules

        if [[ -n "$BACKEND_SERVICE" ]]; then
            enable_iap_for_backend_service
        fi

        configure_iap_access_policies
        setup_iap_ssh_wrapper
    else
        log_warning "Neither SSH nor HTTPS IAP enabled"
        log_info "Use --enable-ssh-iap or --enable-https-iap to enable IAP"
    fi

    # Testing guidance
    echo ""
    test_nat_connectivity
    test_iap_access

    # Print summary
    print_summary

    log "IAP and Cloud NAT setup completed successfully"
}

# Execute main function
main "$@"
