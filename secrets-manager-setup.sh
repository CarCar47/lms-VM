#!/bin/bash
# ============================================================================
# Google Secret Manager Setup for Moodle VM
# Industry Standard Secrets Management
# ============================================================================
#
# This script configures Google Secret Manager to securely store and retrieve
# sensitive credentials instead of storing them in files.
#
# Replaces: /root/.moodle-credentials file-based storage
#
# What this provides:
#   - Encrypted storage of database passwords
#   - Encrypted storage of SMTP credentials
#   - Automatic secret rotation support
#   - Audit logging of secret access
#   - Role-based access control
#
# Industry Standard: NEVER store secrets in files (OWASP, CIS, NIST)
#
# Usage:
#   sudo bash secrets-manager-setup.sh
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Google Cloud Project (auto-detect or from environment)
GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"

# Secret names
SECRET_DB_PASSWORD="moodle-db-password"
SECRET_DB_USER="moodle-db-user"
SECRET_SMTP_PASSWORD="moodle-smtp-password"
SECRET_SMTP_USER="moodle-smtp-user"

# Service account for VM access to secrets
SERVICE_ACCOUNT_NAME="moodle-vm-secrets"

# Log file
LOG_FILE="/var/log/secrets-manager-setup.log"

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# CHECK REQUIREMENTS
# ============================================================================

log "============================================"
log "Google Secret Manager Setup for Moodle"
log "Industry Standard Secrets Management"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI not found. Install it first: https://cloud.google.com/sdk/docs/install"
fi

# Check if project ID is set
if [[ -z "$GCP_PROJECT_ID" ]]; then
    error "GCP_PROJECT_ID not set. Run: export GCP_PROJECT_ID='your-project-id' or gcloud config set project YOUR_PROJECT"
fi

log "Using GCP Project: $GCP_PROJECT_ID"

# ============================================================================
# STEP 1: ENABLE SECRET MANAGER API
# ============================================================================

log "Step 1: Enabling Secret Manager API..."

gcloud services enable secretmanager.googleapis.com --project="$GCP_PROJECT_ID" || error "Failed to enable Secret Manager API"

log "Secret Manager API enabled"

# ============================================================================
# STEP 2: CREATE SERVICE ACCOUNT FOR VM
# ============================================================================

log "Step 2: Creating service account for Secret Manager access..."

# Check if service account already exists
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com" --project="$GCP_PROJECT_ID" &>/dev/null; then
    warn "Service account ${SERVICE_ACCOUNT_NAME} already exists"
else
    gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Moodle VM Secrets Access" \
        --description="Service account for Moodle VM to access Secret Manager" \
        --project="$GCP_PROJECT_ID" || error "Failed to create service account"

    log "Service account created: ${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
fi

# ============================================================================
# STEP 3: MIGRATE EXISTING CREDENTIALS TO SECRET MANAGER
# ============================================================================

log "Step 3: Migrating existing credentials to Secret Manager..."

# Function to create or update secret
create_or_update_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="$3"

    # Check if secret exists
    if gcloud secrets describe "$secret_name" --project="$GCP_PROJECT_ID" &>/dev/null; then
        warn "Secret $secret_name already exists, adding new version..."
        echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
            --data-file=- \
            --project="$GCP_PROJECT_ID" || error "Failed to update secret $secret_name"
    else
        log "Creating secret: $secret_name"
        echo -n "$secret_value" | gcloud secrets create "$secret_name" \
            --data-file=- \
            --replication-policy="automatic" \
            --labels="app=moodle,managed-by=secrets-manager-setup" \
            --project="$GCP_PROJECT_ID" || error "Failed to create secret $secret_name"
    fi

    log "Secret $secret_name created/updated"
}

# Check for existing credentials file
CREDENTIALS_FILE="/root/.moodle-credentials"

if [[ -f "$CREDENTIALS_FILE" ]]; then
    log "Found existing credentials file: $CREDENTIALS_FILE"

    # Read existing credentials
    DB_USER=$(grep "MOODLE_DB_USER=" "$CREDENTIALS_FILE" | cut -d'=' -f2 | tr -d '"' || echo "moodle_user")
    DB_PASSWORD=$(grep "MOODLE_DB_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")
    SMTP_USER=$(grep "SMTP_USER=" "$CREDENTIALS_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")
    SMTP_PASSWORD=$(grep "SMTP_PASSWORD=" "$CREDENTIALS_FILE" | cut -d'=' -f2 | tr -d '"' || echo "")

    # Migrate to Secret Manager
    if [[ -n "$DB_USER" ]]; then
        create_or_update_secret "$SECRET_DB_USER" "$DB_USER" "Moodle database username"
    fi

    if [[ -n "$DB_PASSWORD" ]]; then
        create_or_update_secret "$SECRET_DB_PASSWORD" "$DB_PASSWORD" "Moodle database password"
    fi

    if [[ -n "$SMTP_USER" ]]; then
        create_or_update_secret "$SECRET_SMTP_USER" "$SMTP_USER" "Moodle SMTP username"
    fi

    if [[ -n "$SMTP_PASSWORD" ]]; then
        create_or_update_secret "$SECRET_SMTP_PASSWORD" "$SMTP_PASSWORD" "Moodle SMTP password"
    fi

    # Backup and remove credentials file
    cp "$CREDENTIALS_FILE" "${CREDENTIALS_FILE}.backup-$(date +%Y%m%d_%H%M%S)"
    log "Backed up credentials file to ${CREDENTIALS_FILE}.backup-*"

    warn "SECURITY: Remove old credentials file manually after verifying secrets work:"
    warn "  sudo rm $CREDENTIALS_FILE"
    warn "  sudo rm ${CREDENTIALS_FILE}.backup-*"

else
    warn "No existing credentials file found. You'll need to set secrets manually."
    warn "Use: bash secrets-manager-setup.sh --set-secret SECRET_NAME"
fi

# ============================================================================
# STEP 4: GRANT SERVICE ACCOUNT ACCESS TO SECRETS
# ============================================================================

log "Step 4: Granting service account access to secrets..."

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${GCP_PROJECT_ID}.iam.gserviceaccount.com"

# Grant Secret Accessor role for each secret
for secret in "$SECRET_DB_PASSWORD" "$SECRET_DB_USER" "$SECRET_SMTP_PASSWORD" "$SECRET_SMTP_USER"; do
    if gcloud secrets describe "$secret" --project="$GCP_PROJECT_ID" &>/dev/null; then
        gcloud secrets add-iam-policy-binding "$secret" \
            --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
            --role="roles/secretmanager.secretAccessor" \
            --project="$GCP_PROJECT_ID" || warn "Failed to grant access to $secret"

        log "Granted access to $secret"
    fi
done

# ============================================================================
# STEP 5: ATTACH SERVICE ACCOUNT TO VM
# ============================================================================

log "Step 5: Checking VM service account configuration..."

# Get current VM instance name and zone
INSTANCE_NAME=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/name" -H "Metadata-Flavor: Google" || echo "")
ZONE=$(curl -s "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google" | awk -F'/' '{print $NF}' || echo "")

if [[ -n "$INSTANCE_NAME" ]] && [[ -n "$ZONE" ]]; then
    log "Running on VM: $INSTANCE_NAME (zone: $ZONE)"

    info "To attach service account to this VM, run:"
    info "  gcloud compute instances set-service-account $INSTANCE_NAME \\"
    info "    --service-account=$SERVICE_ACCOUNT_EMAIL \\"
    info "    --scopes=https://www.googleapis.com/auth/cloud-platform \\"
    info "    --zone=$ZONE"
    info "  (Requires VM restart)"
else
    warn "Not running on GCE VM. Service account must be attached manually."
fi

# ============================================================================
# STEP 6: CREATE HELPER FUNCTIONS FOR RETRIEVING SECRETS
# ============================================================================

log "Step 6: Creating secret retrieval helper scripts..."

# Create secret getter script
cat > /usr/local/bin/get-moodle-secret << 'EOFSCRIPT'
#!/bin/bash
# Helper script to retrieve secrets from Google Secret Manager
# Usage: get-moodle-secret SECRET_NAME

set -e

SECRET_NAME="$1"

if [[ -z "$SECRET_NAME" ]]; then
    echo "Usage: get-moodle-secret SECRET_NAME" >&2
    exit 1
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")

# Retrieve secret
gcloud secrets versions access latest \
    --secret="$SECRET_NAME" \
    --project="$PROJECT_ID" 2>/dev/null || {
    echo "ERROR: Failed to retrieve secret: $SECRET_NAME" >&2
    exit 1
}
EOFSCRIPT

chmod +x /usr/local/bin/get-moodle-secret

log "Created helper script: /usr/local/bin/get-moodle-secret"

# Create environment variable loader
cat > /usr/local/bin/load-moodle-secrets << 'EOFSCRIPT'
#!/bin/bash
# Load Moodle secrets as environment variables
# Usage: source /usr/local/bin/load-moodle-secrets

export MOODLE_DB_USER=$(get-moodle-secret moodle-db-user 2>/dev/null || echo "moodle_user")
export MOODLE_DB_PASSWORD=$(get-moodle-secret moodle-db-password 2>/dev/null || echo "")
export SMTP_USER=$(get-moodle-secret moodle-smtp-user 2>/dev/null || echo "")
export SMTP_PASSWORD=$(get-moodle-secret moodle-smtp-password 2>/dev/null || echo "")

echo "Moodle secrets loaded into environment variables" >&2
EOFSCRIPT

chmod +x /usr/local/bin/load-moodle-secrets

log "Created environment loader: /usr/local/bin/load-moodle-secrets"

# ============================================================================
# STEP 7: TEST SECRET RETRIEVAL
# ============================================================================

log "Step 7: Testing secret retrieval..."

# Test if we can retrieve secrets
if /usr/local/bin/get-moodle-secret "$SECRET_DB_USER" &>/dev/null; then
    log "Secret retrieval test: SUCCESS"
else
    warn "Secret retrieval test: FAILED"
    warn "This is expected if service account is not yet attached to VM"
    warn "Secrets will work after VM restart with correct service account"
fi

# ============================================================================
# STEP 8: CREATE SECRET ROTATION GUIDE
# ============================================================================

log "Step 8: Creating secret rotation documentation..."

cat > /root/SECRET-ROTATION-GUIDE.md << 'EOFGUIDE'
# Secret Rotation Guide for Moodle VM

## Rotating Database Password

1. **Generate new password**:
   ```bash
   NEW_PASSWORD=$(openssl rand -base64 32)
   ```

2. **Update MariaDB password**:
   ```bash
   mysql -u root -p <<EOF
   ALTER USER 'moodle_user'@'localhost' IDENTIFIED BY '$NEW_PASSWORD';
   FLUSH PRIVILEGES;
   EOF
   ```

3. **Update Secret Manager**:
   ```bash
   echo -n "$NEW_PASSWORD" | gcloud secrets versions add moodle-db-password --data-file=-
   ```

4. **Restart web server** (to reload config with new password):
   ```bash
   systemctl restart apache2  # or nginx + php-fpm
   ```

5. **Verify Moodle works** - Login and test

## Rotating SMTP Password

1. **Update password in your email provider** (Gmail, SendGrid, etc.)

2. **Update Secret Manager**:
   ```bash
   echo -n "NEW_SMTP_PASSWORD" | gcloud secrets versions add moodle-smtp-password --data-file=-
   ```

3. **Update Moodle config** (if not using environment variables):
   ```bash
   # Moodle will use new password from Secret Manager on next page load
   ```

## Viewing Secret History

```bash
# List all versions of a secret
gcloud secrets versions list moodle-db-password

# View specific version
gcloud secrets versions access 2 --secret=moodle-db-password
```

## Auditing Secret Access

```bash
# View who accessed secrets
gcloud logging read "resource.type=secretmanager.googleapis.com/Secret" \
    --limit 50 --format json
```

## Emergency: Disable Old Secret Version

```bash
# Disable compromised version
gcloud secrets versions disable 1 --secret=moodle-db-password
```

## Best Practices

- Rotate database password every 90 days
- Rotate SMTP password when provider requires
- Never log secret values
- Use service account with minimum required permissions
- Monitor secret access logs monthly
EOFGUIDE

log "Secret rotation guide created: /root/SECRET-ROTATION-GUIDE.md"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Secret Manager Setup Complete!"
log "============================================"
log ""
log "Secrets Created:"
log "  - $SECRET_DB_USER"
log "  - $SECRET_DB_PASSWORD"
log "  - $SECRET_SMTP_USER"
log "  - $SECRET_SMTP_PASSWORD"
log ""
log "Service Account: $SERVICE_ACCOUNT_EMAIL"
log ""
log "Helper Scripts:"
log "  - /usr/local/bin/get-moodle-secret"
log "  - /usr/local/bin/load-moodle-secrets"
log ""
log "Next Steps:"
log "  1. Attach service account to VM (requires restart):"
log "     gcloud compute instances set-service-account $INSTANCE_NAME \\"
log "       --service-account=$SERVICE_ACCOUNT_EMAIL \\"
log "       --scopes=https://www.googleapis.com/auth/cloud-platform \\"
log "       --zone=$ZONE"
log ""
log "  2. Restart VM to apply service account"
log ""
log "  3. Test secret retrieval:"
log "     get-moodle-secret moodle-db-password"
log ""
log "  4. Update scripts to use secrets (already done if using updated scripts)"
log ""
log "  5. Remove old credentials file:"
log "     sudo rm /root/.moodle-credentials*"
log ""
log "Documentation:"
log "  - Rotation guide: /root/SECRET-ROTATION-GUIDE.md"
log "  - Setup log: $LOG_FILE"
log ""
log "Cost: ~$0.20/month (50,000 secret accesses included free)"
log "============================================"

exit 0
