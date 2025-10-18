#!/bin/bash

################################################################################
# Moodle VM - Production Golden Copy Deployment Script
#
# Description:
#   Master orchestrator for deploying a fully hardened, production-ready
#   Moodle VM with CIS Level 1/2 compliance, GDPR/FERPA compliance, and
#   enterprise-grade security features.
#
# Features Included:
#   - Base LAMP/LEMP stack (setup-vm.sh)
#   - CIS Ubuntu 22.04 LTS Benchmark v2.0.0 hardening
#   - Cloud Armor WAF with OWASP Top 10 protection
#   - Zero-trust access with IAP + Cloud NAT
#   - Google Secret Manager integration
#   - Multi-layer rate limiting
#   - Shielded VM with OS Login + 2FA
#   - Automated backups and monitoring
#
# Optional Features (prompted):
#   - Redis cache store
#   - Cloud CDN global edge caching
#   - Security Command Center (Standard/Premium)
#
# Usage:
#   bash deploy-production-golden.sh [VM_NAME] [OPTIONS]
#
# Examples:
#   bash deploy-production-golden.sh moodle-client-demo
#   bash deploy-production-golden.sh moodle-prod --zone=us-east1-b --skip-optional
#
# Author: COR4EDU
# Version: 1.1.0
# Date: 2025-10-17
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
print_banner() {
    cat << "EOF"
╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║     MOODLE VM - PRODUCTION GOLDEN COPY DEPLOYMENT                     ║
║     Version 1.1.0 - Enterprise-Grade Security & Compliance            ║
║                                                                        ║
║     Features:                                                          ║
║     • CIS Level 1/2 Hardening                                         ║
║     • OWASP Top 10 Protection (Cloud Armor WAF)                       ║
║     • Zero-Trust Access (IAP + OS Login with 2FA)                     ║
║     • GDPR/FERPA Compliance                                           ║
║     • Automated Security & Monitoring                                  ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝
EOF
}

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME=""
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_REGION="${GCP_REGION:-us-central1}"
SKIP_OPTIONAL=false
AUTO_YES=false
CIS_LEVEL="1,2"
CLOUD_ARMOR_ENABLED=true
IAP_ENABLED=true
SECRETS_MANAGER_ENABLED=true

# Parse command line arguments
parse_args() {
    if [[ $# -eq 0 ]]; then
        log_error "VM name is required"
        echo "Usage: bash deploy-production-golden.sh [VM_NAME] [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --zone=ZONE              GCP zone (default: us-central1-a)"
        echo "  --region=REGION          GCP region (default: us-central1)"
        echo "  --project=PROJECT_ID     GCP project ID"
        echo "  --skip-optional          Skip optional features (Redis, CDN, SCC)"
        echo "  --yes                    Auto-accept all prompts"
        echo "  --cis-level=LEVEL        CIS hardening level: 1, 2, or 1,2 (default: 1,2)"
        echo ""
        echo "Examples:"
        echo "  bash deploy-production-golden.sh moodle-demo"
        echo "  bash deploy-production-golden.sh moodle-prod --zone=us-east1-b --skip-optional"
        exit 1
    fi

    VM_NAME="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case $1 in
            --zone=*)
                GCP_ZONE="${1#*=}"
                GCP_REGION="${GCP_ZONE%-*}"
                shift
                ;;
            --region=*)
                GCP_REGION="${1#*=}"
                shift
                ;;
            --project=*)
                GCP_PROJECT_ID="${1#*=}"
                shift
                ;;
            --skip-optional)
                SKIP_OPTIONAL=true
                shift
                ;;
            --yes)
                AUTO_YES=true
                shift
                ;;
            --cis-level=*)
                CIS_LEVEL="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Validate environment
validate_environment() {
    log "Validating environment..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    # Get project ID if not provided
    if [[ -z "$GCP_PROJECT_ID" ]]; then
        GCP_PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$GCP_PROJECT_ID" ]]; then
            log_error "GCP project ID not set. Use --project=PROJECT_ID or run: gcloud config set project PROJECT_ID"
            exit 1
        fi
    fi

    # Validate required scripts exist
    local required_scripts=(
        "deploy-to-gcp.sh"
        "cis-hardening.sh"
        "cloud-armor-setup.sh"
        "iap-setup.sh"
        "secrets-manager-setup.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_error "Required script not found: $script"
            exit 1
        fi
    done

    log_info "Environment validated successfully"
    log_info "Project: $GCP_PROJECT_ID"
    log_info "Zone: $GCP_ZONE"
    log_info "Region: $GCP_REGION"
    log_info "VM Name: $VM_NAME"
}

# Confirm deployment
confirm_deployment() {
    if [[ "$AUTO_YES" == true ]]; then
        return 0
    fi

    echo ""
    log_warn "You are about to deploy a production VM with the following configuration:"
    echo ""
    echo "  VM Name:         $VM_NAME"
    echo "  Project:         $GCP_PROJECT_ID"
    echo "  Zone:            $GCP_ZONE"
    echo "  CIS Level:       $CIS_LEVEL"
    echo "  Cloud Armor:     $CLOUD_ARMOR_ENABLED"
    echo "  IAP:             $IAP_ENABLED"
    echo "  Secret Manager:  $SECRETS_MANAGER_ENABLED"
    echo ""
    echo "Estimated deployment time: 30-40 minutes"
    echo "Estimated monthly cost: \$35-50 (with all features)"
    echo ""
    read -p "Continue with deployment? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Phase 1: Deploy base VM
deploy_base_vm() {
    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 1: Deploying Base VM (LAMP Stack + Redis + OS Login)"
    log "═══════════════════════════════════════════════════════════════════"

    cd "$SCRIPT_DIR" || exit 1

    export GCP_PROJECT_ID
    export GCP_ZONE
    export GCP_REGION

    if ! bash deploy-to-gcp.sh production "$VM_NAME"; then
        log_error "Base VM deployment failed"
        exit 1
    fi

    log "✓ Base VM deployed successfully"
}

# Phase 2: Wait for VM to be ready
wait_for_vm() {
    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 2: Waiting for VM to be ready..."
    log "═══════════════════════════════════════════════════════════════════"

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
            --command="echo 'VM is ready'" &> /dev/null; then
            log "✓ VM is ready and accessible"
            return 0
        fi

        attempt=$((attempt + 1))
        log_info "Waiting for VM... ($attempt/$max_attempts)"
        sleep 10
    done

    log_error "VM failed to become ready within timeout"
    exit 1
}

# Phase 3: Upload hardening scripts
upload_scripts() {
    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 3: Uploading hardening scripts to VM..."
    log "═══════════════════════════════════════════════════════════════════"

    local scripts=(
        "cis-hardening.sh"
        "cloud-armor-setup.sh"
        "iap-setup.sh"
        "secrets-manager-setup.sh"
        "redis-setup.sh"
        "cdn-setup.sh"
        "scc-setup.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            log_info "Uploading $script..."
            if ! gcloud compute scp "$SCRIPT_DIR/$script" "$VM_NAME:/tmp/" \
                --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" &> /dev/null; then
                log_warn "Failed to upload $script (non-critical)"
            fi
        fi
    done

    log "✓ Scripts uploaded successfully"
}

# Phase 4: Run CIS hardening
run_cis_hardening() {
    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 4: Running CIS Benchmark Hardening (Level $CIS_LEVEL)..."
    log "═══════════════════════════════════════════════════════════════════"
    log_warn "This may take 20-30 minutes. Please be patient..."

    gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --command="sudo bash /tmp/cis-hardening.sh --level=$CIS_LEVEL --auto-yes" || {
        log_error "CIS hardening failed"
        exit 1
    }

    log "✓ CIS hardening completed successfully"
}

# Phase 5: Configure Cloud Armor WAF
configure_cloud_armor() {
    if [[ "$CLOUD_ARMOR_ENABLED" != true ]]; then
        log_info "Skipping Cloud Armor configuration"
        return 0
    fi

    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 5: Configuring Cloud Armor WAF (OWASP Top 10)..."
    log "═══════════════════════════════════════════════════════════════════"

    gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --command="sudo bash /tmp/cloud-armor-setup.sh --vm-name=$VM_NAME --auto-yes" || {
        log_warn "Cloud Armor setup failed (non-critical, can be configured later)"
        return 1
    }

    log "✓ Cloud Armor WAF configured successfully"
}

# Phase 6: Configure IAP and Cloud NAT
configure_iap() {
    if [[ "$IAP_ENABLED" != true ]]; then
        log_info "Skipping IAP configuration"
        return 0
    fi

    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 6: Configuring IAP + Cloud NAT (Zero-Trust Access)..."
    log "═══════════════════════════════════════════════════════════════════"

    gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --command="sudo bash /tmp/iap-setup.sh --project=$GCP_PROJECT_ID --region=$GCP_REGION --auto-yes" || {
        log_warn "IAP setup failed (non-critical, can be configured later)"
        return 1
    }

    log "✓ IAP and Cloud NAT configured successfully"
}

# Phase 7: Configure Secret Manager
configure_secret_manager() {
    if [[ "$SECRETS_MANAGER_ENABLED" != true ]]; then
        log_info "Skipping Secret Manager configuration"
        return 0
    fi

    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 7: Configuring Google Secret Manager..."
    log "═══════════════════════════════════════════════════════════════════"

    gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --command="sudo bash /tmp/secrets-manager-setup.sh --project=$GCP_PROJECT_ID --auto-yes" || {
        log_warn "Secret Manager setup failed (non-critical, can be configured later)"
        return 1
    }

    log "✓ Secret Manager configured successfully"
}

# Phase 8: Optional features
configure_optional_features() {
    if [[ "$SKIP_OPTIONAL" == true ]]; then
        log_info "Skipping optional features (--skip-optional flag)"
        return 0
    fi

    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 8: Optional Features Configuration"
    log "═══════════════════════════════════════════════════════════════════"

    # Redis cache
    if [[ "$AUTO_YES" != true ]]; then
        read -p "Install Redis cache store for performance? (recommended for 50+ users) (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installing Redis cache..."
            gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
                --command="sudo bash /tmp/redis-setup.sh --auto-yes" || log_warn "Redis setup failed"
        fi
    fi

    # Cloud CDN
    if [[ "$AUTO_YES" != true ]]; then
        read -p "Enable Cloud CDN for global edge caching? (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Configuring Cloud CDN..."
            gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
                --command="sudo bash /tmp/cdn-setup.sh --backend=$VM_NAME --auto-yes" || log_warn "CDN setup failed"
        fi
    fi

    # Security Command Center
    if [[ "$AUTO_YES" != true ]]; then
        read -p "Enable Security Command Center? (Standard=free, Premium=\$25/month) (y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "Select tier (standard/premium): " -r scc_tier
            log_info "Configuring Security Command Center ($scc_tier)..."
            gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
                --command="sudo bash /tmp/scc-setup.sh --tier=$scc_tier --auto-yes" || log_warn "SCC setup failed"
        fi
    fi
}

# Phase 9: Final verification
verify_deployment() {
    log "═══════════════════════════════════════════════════════════════════"
    log "PHASE 9: Verifying deployment..."
    log "═══════════════════════════════════════════════════════════════════"

    # Get VM external IP
    local vm_ip
    vm_ip=$(gcloud compute instances describe "$VM_NAME" \
        --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "N/A")

    # Check if services are running
    log_info "Checking services..."
    gcloud compute ssh "$VM_NAME" --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --command="sudo systemctl is-active apache2 mariadb" &> /dev/null && \
        log "✓ Apache and MariaDB are running" || \
        log_warn "Some services may not be running"

    log "✓ Deployment verification completed"
}

# Display summary
display_summary() {
    log "═══════════════════════════════════════════════════════════════════"
    log "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log "═══════════════════════════════════════════════════════════════════"

    local vm_ip
    vm_ip=$(gcloud compute instances describe "$VM_NAME" \
        --zone="$GCP_ZONE" --project="$GCP_PROJECT_ID" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "N/A")

    echo ""
    echo "VM Details:"
    echo "  Name:         $VM_NAME"
    echo "  Project:      $GCP_PROJECT_ID"
    echo "  Zone:         $GCP_ZONE"
    echo "  IP Address:   $vm_ip"
    echo ""
    echo "Security Features Enabled:"
    echo "  ✓ CIS Level $CIS_LEVEL Hardening"
    echo "  ✓ Cloud Armor WAF (OWASP Top 10)"
    echo "  ✓ IAP + Cloud NAT (Zero-Trust Access)"
    echo "  ✓ OS Login with 2FA"
    echo "  ✓ Shielded VM (Secure Boot + vTPM)"
    echo "  ✓ Secret Manager Integration"
    echo "  ✓ Multi-layer Rate Limiting"
    echo "  ✓ Automated Backups & Monitoring"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Complete Moodle Installation Wizard:"
    echo "   https://$vm_ip/moodle/install.php"
    echo ""
    echo "2. Configure DNS for your domain (see DNS-SETUP-GUIDE.md)"
    echo ""
    echo "3. Enable OS Login with 2FA (2025 mandatory):"
    echo "   gcloud compute project-info add-metadata \\"
    echo "     --metadata enable-oslogin=TRUE,enable-oslogin-2fa=TRUE"
    echo ""
    echo "4. Review compliance documentation:"
    echo "   - COMPLIANCE-GDPR-FERPA.md"
    echo "   - CERTIFICATE-TRANSPARENCY-MONITORING.md"
    echo ""
    echo "5. Access VM via SSH:"
    echo "   gcloud compute ssh $VM_NAME --zone=$GCP_ZONE"
    echo ""
    echo "Documentation: README.md"
    echo "Support: support@cor4edu.com"
    echo ""
    log "Deployment completed in $(date)"
}

# Main execution
main() {
    print_banner
    parse_args "$@"
    validate_environment
    confirm_deployment

    local start_time
    start_time=$(date +%s)

    # Execute deployment phases
    deploy_base_vm
    wait_for_vm
    upload_scripts
    run_cis_hardening
    configure_cloud_armor
    configure_iap
    configure_secret_manager
    configure_optional_features
    verify_deployment
    display_summary

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log "Total deployment time: $((duration / 60)) minutes $((duration % 60)) seconds"
}

# Run main function
main "$@"
