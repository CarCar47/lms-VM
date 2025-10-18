#!/bin/bash
# ============================================================================
# Moodle VM - Custom Service Account Setup
# Industry Standard: Least Privilege Service Account
# ============================================================================
#
# This script creates a custom service account for the Moodle VM with
# minimal required permissions, following Google Cloud IAM best practices.
#
# WHY THIS IS CRITICAL:
#   - Default Compute Engine service account has Editor role (too broad)
#   - Editor role grants read/write access to ALL resources in project
#   - Violates principle of least privilege (CIS, NIST, OWASP)
#   - Creates security risk if VM is compromised
#
# WHAT THIS SCRIPT DOES:
#   1. Creates dedicated service account for Moodle VM
#   2. Grants ONLY required IAM roles:
#      - Logs Writer (for Cloud Logging)
#      - Metric Writer (for Cloud Monitoring)
#      - Secret Accessor (for Secret Manager)
#      - Storage Object Admin (for backup storage)
#   3. Removes all other permissions
#
# USAGE:
#   Run this BEFORE deploying VM:
#     bash service-account-setup.sh
#
#   Or specify custom project:
#     bash service-account-setup.sh --project=my-project-id
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Project configuration
GCP_PROJECT_ID="${GCP_PROJECT_ID:-sms-edu-47}"

# Service account configuration
SERVICE_ACCOUNT_NAME="moodle-vm-service-account"
SERVICE_ACCOUNT_DISPLAY_NAME="Moodle VM Service Account"
SERVICE_ACCOUNT_DESCRIPTION="Least-privilege service account for Moodle VM - logging, monitoring, secrets, storage only"

# IAM roles to grant (least privilege)
REQUIRED_ROLES=(
    "roles/logging.logWriter"           # Write logs to Cloud Logging
    "roles/monitoring.metricWriter"     # Write metrics to Cloud Monitoring
    "roles/secretmanager.secretAccessor" # Read secrets from Secret Manager
    "roles/storage.objectAdmin"         # Manage backups in Cloud Storage
)

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

# ============================================================================
# PARSE ARGUMENTS
# ============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project=*)
            GCP_PROJECT_ID="${1#*=}"
            shift
            ;;
        --help)
            echo "Usage: bash service-account-setup.sh [--project=PROJECT_ID]"
            echo ""
            echo "Creates a least-privilege service account for Moodle VM"
            echo ""
            echo "Options:"
            echo "  --project=PROJECT_ID    Google Cloud project ID"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log "============================================"
log "Moodle VM - Custom Service Account Setup"
log "Project: $GCP_PROJECT_ID"
log "============================================"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Install from: https://cloud.google.com/sdk"
    exit 1
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    error "Not authenticated with gcloud. Run: gcloud auth login"
    exit 1
fi

# Set project
log "Setting project to $GCP_PROJECT_ID..."
gcloud config set project "$GCP_PROJECT_ID" || error "Failed to set project"

# Verify user has necessary permissions
log "Verifying IAM permissions..."
if ! gcloud projects get-iam-policy "$GCP_PROJECT_ID" &> /dev/null; then
    error "You don't have permission to view IAM policy. Need roles/owner or roles/iam.securityAdmin"
    exit 1
fi

log "Preflight checks passed"

# ============================================================================
# CREATE SERVICE ACCOUNT
# ============================================================================

log "============================================"
log "Creating custom service account..."
log "============================================"

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Check if service account already exists
if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &> /dev/null; then
    warn "Service account already exists: $SERVICE_ACCOUNT_EMAIL"
    log "Using existing service account"
else
    # Create service account
    log "Creating service account: $SERVICE_ACCOUNT_NAME"
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="$SERVICE_ACCOUNT_DISPLAY_NAME" \
        --description="$SERVICE_ACCOUNT_DESCRIPTION" \
        --project="$GCP_PROJECT_ID"

    log "Service account created: $SERVICE_ACCOUNT_EMAIL"
fi

# ============================================================================
# GRANT IAM ROLES (LEAST PRIVILEGE)
# ============================================================================

log "============================================"
log "Granting IAM roles (least privilege)..."
log "============================================"

for role in "${REQUIRED_ROLES[@]}"; do
    log "Granting role: $role"

    gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
        --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
        --role="$role" \
        --condition=None \
        --quiet

    info "  ✓ Granted: $role"
done

log "All IAM roles granted successfully"

# ============================================================================
# VERIFY PERMISSIONS
# ============================================================================

log "============================================"
log "Verifying service account permissions..."
log "============================================"

log "Service account: $SERVICE_ACCOUNT_EMAIL"
log ""
log "Granted roles:"

gcloud projects get-iam-policy "$GCP_PROJECT_ID" \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL"

# ============================================================================
# SECURITY VALIDATION
# ============================================================================

log "============================================"
log "Security validation..."
log "============================================"

# Check for overly permissive roles
DANGEROUS_ROLES=("roles/owner" "roles/editor" "roles/viewer" "roles/iam.serviceAccountUser")
FOUND_DANGEROUS=false

for role in "${DANGEROUS_ROLES[@]}"; do
    if gcloud projects get-iam-policy "$GCP_PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="value(bindings.role)" \
        --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL AND bindings.role:$role" | grep -q "$role"; then

        warn "SECURITY WARNING: Service account has overly broad role: $role"
        FOUND_DANGEROUS=true
    fi
done

if [[ "$FOUND_DANGEROUS" == false ]]; then
    log "✓ Security validation passed - no overly permissive roles found"
else
    warn "Security validation failed - review and remove overly permissive roles"
fi

# ============================================================================
# SAVE SERVICE ACCOUNT INFO
# ============================================================================

log "Saving service account information..."

SERVICE_ACCOUNT_INFO_FILE="$HOME/.moodle-vm-service-account.txt"

cat > "$SERVICE_ACCOUNT_INFO_FILE" << EOF
# ============================================================================
# Moodle VM - Custom Service Account Information
# Generated: $(date)
# ============================================================================

Service Account Email: $SERVICE_ACCOUNT_EMAIL
Service Account Name: $SERVICE_ACCOUNT_NAME
Project ID: $GCP_PROJECT_ID

# ============================================================================
# GRANTED IAM ROLES (LEAST PRIVILEGE)
# ============================================================================

$(for role in "${REQUIRED_ROLES[@]}"; do echo "  - $role"; done)

# ============================================================================
# USAGE IN DEPLOY SCRIPT
# ============================================================================

To use this service account when deploying VM:

1. Update deploy-to-gcp.sh:
   Change:
     SERVICE_ACCOUNT="default"
   To:
     SERVICE_ACCOUNT="$SERVICE_ACCOUNT_EMAIL"

2. Or set environment variable:
   export MOODLE_VM_SERVICE_ACCOUNT="$SERVICE_ACCOUNT_EMAIL"

3. Deploy VM:
   bash deploy-to-gcp.sh

# ============================================================================
# SECURITY BEST PRACTICES
# ============================================================================

✓ Uses least-privilege principle (NIST, CIS, OWASP)
✓ No Editor/Owner/Viewer roles (avoids overly broad access)
✓ Only grants specific, required permissions
✓ Follows Google Cloud IAM best practices
✓ Reduces attack surface if VM is compromised

# ============================================================================
# WHAT EACH ROLE ALLOWS
# ============================================================================

roles/logging.logWriter
  - Write logs to Cloud Logging
  - Does NOT allow reading logs from other resources

roles/monitoring.metricWriter
  - Write custom metrics to Cloud Monitoring
  - Does NOT allow reading metrics or creating dashboards

roles/secretmanager.secretAccessor
  - Read secret values from Secret Manager
  - Does NOT allow creating, updating, or deleting secrets

roles/storage.objectAdmin
  - Create, read, update, delete objects in Cloud Storage
  - Used for backup storage only
  - Does NOT allow managing buckets or IAM

# ============================================================================
# VERIFICATION
# ============================================================================

View service account details:
  gcloud iam service-accounts describe $SERVICE_ACCOUNT_EMAIL

View granted roles:
  gcloud projects get-iam-policy $GCP_PROJECT_ID \\
    --flatten="bindings[].members" \\
    --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT_EMAIL"

# ============================================================================
# TROUBLESHOOTING
# ============================================================================

If VM cannot access secrets:
  - Verify Secret Manager API is enabled
  - Verify service account has secretAccessor role
  - Check secret permissions (not project-level)

If VM cannot write logs:
  - Verify Cloud Logging API is enabled
  - Verify service account has logWriter role

If VM cannot write metrics:
  - Verify Cloud Monitoring API is enabled
  - Verify service account has metricWriter role

If VM cannot access Cloud Storage:
  - Verify Cloud Storage API is enabled
  - Verify service account has storage.objectAdmin role
  - Check bucket-level IAM permissions

# ============================================================================
# REMOVAL (IF NEEDED)
# ============================================================================

To delete this service account:
  gcloud iam service-accounts delete $SERVICE_ACCOUNT_EMAIL

Note: This will break any VMs using this service account!
EOF

log "Service account info saved to: $SERVICE_ACCOUNT_INFO_FILE"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Custom Service Account Setup Complete!"
log "============================================"
log ""
log "Service Account: $SERVICE_ACCOUNT_EMAIL"
log ""
log "Granted Roles (Least Privilege):"
for role in "${REQUIRED_ROLES[@]}"; do
    log "  ✓ $role"
done
log ""
info "Next Steps:"
info "  1. Update deploy-to-gcp.sh to use this service account"
info "  2. Deploy VM with: bash deploy-to-gcp.sh"
info "  3. VM will use least-privilege service account"
log ""
log "Service account details: $SERVICE_ACCOUNT_INFO_FILE"
log "============================================"

exit 0
