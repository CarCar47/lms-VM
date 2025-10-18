#!/bin/bash
# ============================================================================
# Moodle 5.1 - Google Cloud VM Deployment Script
# Automated Compute Engine VM Creation and Configuration
# Industry Standard Deployment
# ============================================================================
#
# This script automates the creation and initial configuration of a
# Google Compute Engine VM for Moodle 5.1 deployment.
#
# What it does:
#   1. Creates a Compute Engine VM instance
#   2. Configures persistent disk storage
#   3. Sets up firewall rules
#   4. Uploads Moodle files and configuration
#   5. Runs setup script on the VM
#   6. Configures automated backups
#
# Prerequisites:
#   - gcloud CLI installed and authenticated
#   - Active Google Cloud project
#   - Billing enabled
#   - Compute Engine API enabled
#
# Usage:
#   bash deploy-to-gcp.sh [environment] [instance-name]
#
# Examples:
#   bash deploy-to-gcp.sh production moodle-prod-vm
#   bash deploy-to-gcp.sh staging moodle-staging-vm
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default values (can be overridden by environment variables or arguments)
ENVIRONMENT="${1:-production}"
INSTANCE_NAME="${2:-moodle-vm}"
PROJECT_ID="${GCP_PROJECT_ID:-sms-edu-47}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"

# VM Configuration
# For 40-200 students: e2-medium (2 vCPU, 4GB RAM) = $18-20/month
# For 200-500 students: e2-standard-2 (2 vCPU, 8GB RAM) = $35-40/month
MACHINE_TYPE="${GCP_MACHINE_TYPE:-e2-medium}"
BOOT_DISK_SIZE="${GCP_BOOT_DISK_SIZE:-30GB}"  # OS + Moodle files
DATA_DISK_SIZE="${GCP_DATA_DISK_SIZE:-50GB}"  # Moodle data + backups
DISK_TYPE="pd-standard"  # pd-standard (HDD) or pd-ssd (SSD)

# Network
NETWORK="default"
SUBNET="default"

# OS Image
OS_IMAGE="ubuntu-2204-lts"
OS_IMAGE_PROJECT="ubuntu-os-cloud"

# Service Account - Industry Standard: Use custom least-privilege service account
# SECURITY WARNING: Default service account has Editor role (too broad)
# Run: bash service-account-setup.sh to create custom service account
#
# Override with environment variable:
#   export MOODLE_VM_SERVICE_ACCOUNT="your-service-account@project.iam.gserviceaccount.com"
#
# Custom service account name (will be checked during deployment)
CUSTOM_SERVICE_ACCOUNT_NAME="moodle-vm-service-account"
CUSTOM_SERVICE_ACCOUNT="${CUSTOM_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Allow environment variable override
SERVICE_ACCOUNT="${MOODLE_VM_SERVICE_ACCOUNT:-}"

# Tags
NETWORK_TAGS="http-server,https-server,moodle-vm"

# Backup configuration
BACKUP_SCHEDULE="0 2 * * *"  # Daily at 2 AM
BACKUP_RETENTION_DAYS=7

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
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $*"
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log "============================================"
log "Moodle VM Deployment to Google Cloud"
log "Environment: $ENVIRONMENT"
log "Instance: $INSTANCE_NAME"
log "Project: $PROJECT_ID"
log "============================================"

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed. Install from: https://cloud.google.com/sdk"
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
    error "Not authenticated with gcloud. Run: gcloud auth login"
fi

# Set project
log "Setting project to $PROJECT_ID..."
gcloud config set project "$PROJECT_ID" || error "Failed to set project"

# Check if Compute Engine API is enabled
log "Checking if Compute Engine API is enabled..."
if ! gcloud services list --enabled --filter="name:compute.googleapis.com" | grep -q "compute.googleapis.com"; then
    warn "Compute Engine API is not enabled. Enabling now..."
    gcloud services enable compute.googleapis.com || error "Failed to enable Compute Engine API"
fi

# Check if instance already exists
if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &> /dev/null; then
    error "Instance '$INSTANCE_NAME' already exists in zone '$ZONE'. Choose a different name or delete the existing instance."
fi

log "Preflight checks passed"

# ============================================================================
# VALIDATE SERVICE ACCOUNT (SECURITY BEST PRACTICE)
# ============================================================================

log "============================================"
log "Validating service account configuration..."
log "============================================"

# Check if custom service account exists
if [[ -z "$SERVICE_ACCOUNT" ]]; then
    # No environment variable override, check if custom service account exists
    if gcloud iam service-accounts describe "$CUSTOM_SERVICE_ACCOUNT" &> /dev/null; then
        SERVICE_ACCOUNT="$CUSTOM_SERVICE_ACCOUNT"
        log "✓ Using custom service account: $SERVICE_ACCOUNT"
        info "  Service account created with least-privilege permissions"
    else
        # Custom service account doesn't exist, use default with warning
        warn "============================================"
        warn "SECURITY WARNING: Custom service account not found!"
        warn "============================================"
        warn ""
        warn "Using default Compute Engine service account."
        warn "This account has Editor role (overly broad permissions)."
        warn ""
        warn "RECOMMENDED: Create custom least-privilege service account"
        warn "  1. Run: bash service-account-setup.sh"
        warn "  2. Re-run deployment"
        warn ""
        warn "Proceeding with default service account in 10 seconds..."
        warn "Press Ctrl+C to cancel"
        warn ""

        sleep 10

        SERVICE_ACCOUNT="default"
        warn "Using default service account (not recommended for production)"
    fi
else
    # Environment variable override provided
    log "Using service account from environment: $SERVICE_ACCOUNT"

    # Verify it exists
    if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" &> /dev/null; then
        error "Service account does not exist: $SERVICE_ACCOUNT"
        exit 1
    fi
fi

log "Service account: $SERVICE_ACCOUNT"

# ============================================================================
# GENERATE SSH KEY PAIR
# ============================================================================

log "Generating SSH key pair for VM access..."

SSH_KEY_DIR="$HOME/.ssh/moodle-vm"
mkdir -p "$SSH_KEY_DIR"

if [[ ! -f "$SSH_KEY_DIR/id_rsa" ]]; then
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_DIR/id_rsa" -N "" -C "moodle-vm-key"
    log "SSH key generated: $SSH_KEY_DIR/id_rsa"
else
    info "SSH key already exists: $SSH_KEY_DIR/id_rsa"
fi

# ============================================================================
# CREATE FIREWALL RULES
# ============================================================================

log "Creating firewall rules..."

# HTTP (port 80)
if ! gcloud compute firewall-rules describe allow-http-moodle &> /dev/null; then
    gcloud compute firewall-rules create allow-http-moodle \
        --project="$PROJECT_ID" \
        --network="$NETWORK" \
        --allow=tcp:80 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=http-server \
        --description="Allow HTTP traffic for Moodle"
    log "HTTP firewall rule created"
else
    info "HTTP firewall rule already exists"
fi

# HTTPS (port 443)
if ! gcloud compute firewall-rules describe allow-https-moodle &> /dev/null; then
    gcloud compute firewall-rules create allow-https-moodle \
        --project="$PROJECT_ID" \
        --network="$NETWORK" \
        --allow=tcp:443 \
        --source-ranges=0.0.0.0/0 \
        --target-tags=https-server \
        --description="Allow HTTPS traffic for Moodle"
    log "HTTPS firewall rule created"
else
    info "HTTPS firewall rule already exists"
fi

# ============================================================================
# RESERVE STATIC EXTERNAL IP ADDRESS
# ============================================================================

log "Reserving static external IP address..."

STATIC_IP_NAME="${INSTANCE_NAME}-ip"

# Check if static IP already exists
if gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" &> /dev/null; then
    warn "Static IP already exists: $STATIC_IP_NAME"
    STATIC_IP=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" --format="get(address)")
    log "Using existing static IP: $STATIC_IP"
else
    # Reserve new static IP
    gcloud compute addresses create "$STATIC_IP_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --network-tier=PREMIUM \
        --description="Static IP for Moodle VM - ${INSTANCE_NAME}"

    STATIC_IP=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" --format="get(address)")
    log "Static IP reserved: $STATIC_IP"
fi

info "Static IP Cost: ~\$2.92/month (in-use)"
info "IMPORTANT: Configure DNS A record pointing $STATIC_IP to your domain before SSL setup"

# ============================================================================
# CREATE PERSISTENT DATA DISK
# ============================================================================

log "Creating persistent data disk for Moodle data..."

DATA_DISK_NAME="${INSTANCE_NAME}-data"

if ! gcloud compute disks describe "$DATA_DISK_NAME" --zone="$ZONE" &> /dev/null; then
    gcloud compute disks create "$DATA_DISK_NAME" \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        --size="$DATA_DISK_SIZE" \
        --type="$DISK_TYPE" \
        --description="Moodle data disk - persistent storage for moodledata and backups"
    log "Data disk created: $DATA_DISK_NAME ($DATA_DISK_SIZE)"
else
    warn "Data disk already exists: $DATA_DISK_NAME"
fi

# ============================================================================
# CREATE STARTUP SCRIPT
# ============================================================================

log "Creating startup script..."

STARTUP_SCRIPT=$(cat <<'EOF'
#!/bin/bash
# Startup script for Moodle VM

# Mount data disk
if ! grep -q "/dev/sdb" /etc/fstab; then
    # Format disk if not already formatted
    if ! lsblk -f /dev/sdb | grep -q ext4; then
        mkfs.ext4 -F /dev/sdb
    fi

    # Create mount point
    mkdir -p /mnt/moodle-data

    # Add to fstab
    echo "/dev/sdb /mnt/moodle-data ext4 defaults,nofail 0 2" >> /etc/fstab

    # Mount
    mount /mnt/moodle-data
fi

# Create symlinks for Moodle directories
mkdir -p /mnt/moodle-data/moodledata
mkdir -p /mnt/moodle-data/backups
ln -sf /mnt/moodle-data/moodledata /var/moodledata
ln -sf /mnt/moodle-data/backups /var/backups/moodle

# Set permissions
chown -R www-data:www-data /mnt/moodle-data
chmod -R 755 /mnt/moodle-data

# Enable Google Cloud Monitoring
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install

# Run LAMP setup script in background (survives boot, no SSH dependency)
# This is the INDUSTRY STANDARD approach - runs during boot via cloud-init
# Firewall configuration won't break deployment since there's no SSH session
if [[ -f /opt/moodle-deployment/setup-vm.sh ]]; then
    echo "Starting LAMP setup script..."
    cd /opt/moodle-deployment || exit 1
    nohup bash setup-vm.sh > /var/log/moodle-setup.log 2>&1 &
    echo "LAMP setup started at $(date). Check /var/log/moodle-setup.log for progress."
fi

echo "Moodle VM startup complete"
EOF
)

# ============================================================================
# CREATE VM INSTANCE
# ============================================================================

log "Creating VM instance: $INSTANCE_NAME..."

# Write startup script to temporary file (industry standard for complex scripts)
STARTUP_SCRIPT_FILE="/tmp/moodle-startup-script-$$.sh"
echo "$STARTUP_SCRIPT" > "$STARTUP_SCRIPT_FILE"

gcloud compute instances create "$INSTANCE_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --network-interface="network-tier=PREMIUM,subnet=$SUBNET,address=$STATIC_IP" \
    --metadata-from-file=startup-script="$STARTUP_SCRIPT_FILE" \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --service-account="$SERVICE_ACCOUNT" \
    --scopes=cloud-platform \
    --tags="$NETWORK_TAGS" \
    --create-disk="auto-delete=yes,boot=yes,device-name=$INSTANCE_NAME,image=projects/$OS_IMAGE_PROJECT/global/images/family/$OS_IMAGE,mode=rw,size=$BOOT_DISK_SIZE,type=projects/$PROJECT_ID/zones/$ZONE/diskTypes/$DISK_TYPE" \
    --disk="name=$DATA_DISK_NAME,device-name=$DATA_DISK_NAME,mode=rw,boot=no" \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels="environment=$ENVIRONMENT,application=moodle,managed-by=script,static-ip=$STATIC_IP_NAME,service-account=$CUSTOM_SERVICE_ACCOUNT_NAME" \
    --reservation-affinity=any

# Clean up temporary file
rm -f "$STARTUP_SCRIPT_FILE"

log "VM instance created successfully!"

# ============================================================================
# WAIT FOR VM TO BE READY
# ============================================================================

log "Waiting for VM to be ready..."
sleep 30  # Give VM time to start

# Verify VM is using the static IP
EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

if [[ "$EXTERNAL_IP" == "$STATIC_IP" ]]; then
    log "VM External IP: $EXTERNAL_IP (static)"
else
    warn "VM IP ($EXTERNAL_IP) does not match reserved static IP ($STATIC_IP)"
fi

# Wait for SSH to be ready
log "Waiting for SSH to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=0
while ! gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="echo 'SSH ready'" &> /dev/null; do
    ATTEMPT=$((ATTEMPT + 1))
    if [[ $ATTEMPT -ge $MAX_ATTEMPTS ]]; then
        error "SSH connection timeout after $MAX_ATTEMPTS attempts"
    fi
    info "Attempt $ATTEMPT/$MAX_ATTEMPTS - waiting for SSH..."
    sleep 10
done

log "SSH connection established"

# ============================================================================
# UPLOAD MOODLE FILES AND SCRIPTS
# ============================================================================

log "Uploading Moodle files and configuration..."

# Create temporary directory for upload
UPLOAD_DIR="/tmp/moodle-upload-$$"
mkdir -p "$UPLOAD_DIR"

# Copy files to upload directory
# Note: Adjust paths based on your local structure
log "Preparing files for upload..."

# Create upload package
tar czf "$UPLOAD_DIR/moodle-vm.tar.gz" \
    -C "$(dirname "$0")" \
    --exclude='*.tar.gz' \
    --exclude='.git' \
    --exclude='node_modules' \
    .

# Upload to VM
log "Uploading files to VM..."
gcloud compute scp "$UPLOAD_DIR/moodle-vm.tar.gz" \
    "$INSTANCE_NAME:/tmp/" \
    --zone="$ZONE"

# Extract on VM
log "Extracting files on VM..."
gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    sudo mkdir -p /opt/moodle-deployment
    sudo tar xzf /tmp/moodle-vm.tar.gz -C /opt/moodle-deployment
    sudo chown -R root:root /opt/moodle-deployment
    sudo chmod +x /opt/moodle-deployment/*.sh
    rm /tmp/moodle-vm.tar.gz
"

# Cleanup
rm -rf "$UPLOAD_DIR"

log "Files uploaded successfully"

# ============================================================================
# MONITOR SETUP SCRIPT COMPLETION
# ============================================================================
# INDUSTRY STANDARD: Monitor startup script completion instead of synchronous SSH
# The setup script runs via startup script (cloud-init), not over SSH
# This prevents firewall configuration from breaking deployment

log "Monitoring LAMP setup completion (runs via startup script)..."
log "This may take 15-20 minutes (15 steps including firewall configuration)..."
info "Setup logs: /var/log/moodle-setup.log on VM"

# Poll for completion marker
MAX_WAIT=1200  # 20 minutes max wait
ELAPSED=0
POLL_INTERVAL=30

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    # Check if setup completed (completion marker exists)
    if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
        --command="test -f /opt/moodle-deployment/.setup-complete" &> /dev/null; then
        log "LAMP setup completed successfully!"
        break
    fi

    # Show progress update every 2 minutes
    if [[ $((ELAPSED % 120)) -eq 0 ]] && [[ $ELAPSED -gt 0 ]]; then
        info "Still running... ($((ELAPSED / 60)) minutes elapsed)"
        info "You can monitor progress: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command='tail -f /var/log/moodle-setup.log'"
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# Check if setup completed or timed out
if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    error "Setup script timeout after $((MAX_WAIT / 60)) minutes. Check /var/log/moodle-setup.log on VM for details."
fi

log "LAMP stack setup completed (all 15 steps)"

# ============================================================================
# COPY MOODLE FILES TO WEB DIRECTORY
# ============================================================================

log "Copying Moodle files to web directory..."

gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    sudo cp -r /opt/moodle-deployment/public /var/www/html/moodle/
    sudo cp /opt/moodle-deployment/config.php /var/www/html/moodle/
    sudo chown -R www-data:www-data /var/www/html/moodle
    sudo chmod -R 755 /var/www/html/moodle
"

log "Moodle files copied"

# ============================================================================
# CONFIGURE AUTOMATED BACKUPS
# ============================================================================

log "Configuring automated backups..."

gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    sudo bash /opt/moodle-deployment/backup-vm.sh --install-cron
"

log "Automated backups configured"

# ============================================================================
# CREATE SNAPSHOT SCHEDULE (OPTIONAL)
# ============================================================================

log "Creating snapshot schedule for disaster recovery..."

SNAPSHOT_SCHEDULE_NAME="moodle-daily-snapshots"

if ! gcloud compute resource-policies describe "$SNAPSHOT_SCHEDULE_NAME" --region="$REGION" &> /dev/null; then
    gcloud compute resource-policies create snapshot-schedule "$SNAPSHOT_SCHEDULE_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --max-retention-days="$BACKUP_RETENTION_DAYS" \
        --on-source-disk-delete=keep-auto-snapshots \
        --daily-schedule \
        --start-time=03:00 \
        --storage-location="$REGION"

    # Attach to disks
    gcloud compute disks add-resource-policies "$DATA_DISK_NAME" \
        --zone="$ZONE" \
        --resource-policies="$SNAPSHOT_SCHEDULE_NAME"

    log "Snapshot schedule created and attached"
else
    info "Snapshot schedule already exists"
fi

# ============================================================================
# SAVE DEPLOYMENT INFO
# ============================================================================

log "Saving deployment information..."

DEPLOYMENT_INFO_FILE="$HOME/.moodle-vm-deployments/${INSTANCE_NAME}.txt"
mkdir -p "$(dirname "$DEPLOYMENT_INFO_FILE")"

cat > "$DEPLOYMENT_INFO_FILE" << EOF
# ============================================================================
# Moodle VM Deployment Information
# Generated: $(date)
# ============================================================================

Environment: $ENVIRONMENT
Instance Name: $INSTANCE_NAME
Project ID: $PROJECT_ID
Zone: $ZONE
Machine Type: $MACHINE_TYPE
Service Account: $SERVICE_ACCOUNT

External IP: $STATIC_IP (STATIC - permanent)
Static IP Name: $STATIC_IP_NAME
Internal IP: $(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="get(networkInterfaces[0].networkIP)")

Boot Disk: $BOOT_DISK_SIZE ($DISK_TYPE)
Data Disk: $DATA_DISK_NAME ($DATA_DISK_SIZE)

# ============================================================================
# SERVICE ACCOUNT SECURITY
# ============================================================================

Service Account: $SERVICE_ACCOUNT
Access Scope: cloud-platform (broad scope, IAM role restrictions apply)

IAM Roles Granted (if using custom service account):
  - roles/logging.logWriter (Cloud Logging)
  - roles/monitoring.metricWriter (Cloud Monitoring)
  - roles/secretmanager.secretAccessor (Secret Manager)
  - roles/storage.objectAdmin (Cloud Storage backups)

Security Note: Custom service account uses least-privilege principle.
              Default service account has Editor role (not recommended).

SSH Access:
  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE
  ssh -i $SSH_KEY_DIR/id_rsa [username]@$STATIC_IP

Moodle URL:
  http://$STATIC_IP/moodle (temporary - use domain after DNS/SSL setup)

# ============================================================================
# DNS CONFIGURATION REQUIRED
# ============================================================================

IMPORTANT: Before SSL setup, configure DNS:

1. Go to your DNS provider (GoDaddy, Cloudflare, Route53, etc.)
2. Create an A record:
   - Name: @ (or yourdomain.com)
   - Type: A
   - Value: $STATIC_IP
   - TTL: 3600 (or automatic)

3. Create www subdomain A record:
   - Name: www
   - Type: A
   - Value: $STATIC_IP
   - TTL: 3600

4. Wait 5-30 minutes for DNS propagation
5. Verify DNS: dig yourdomain.com +short (should return $STATIC_IP)

# ============================================================================
# NEXT STEPS
# ============================================================================

Next Steps:
  1. Access Moodle installer: http://$STATIC_IP/moodle/install.php
  2. Complete Moodle installation wizard
  3. Configure DNS (see above)
  4. Run SSL setup: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="sudo bash /opt/moodle-deployment/ssl-setup.sh yourdomain.com admin@yourdomain.com"
  5. Run security hardening: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="sudo bash /opt/moodle-deployment/security-hardening.sh"
  6. Configure monitoring: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="sudo bash /opt/moodle-deployment/monitoring-setup.sh"
  7. Migrate to Secret Manager: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="sudo bash /opt/moodle-deployment/secrets-manager-setup.sh"

# ============================================================================
# COST BREAKDOWN
# ============================================================================

Estimated Monthly Cost: \$21-25

Components:
  - e2-medium VM (2 vCPU, 4GB RAM): \$18-20
  - Static IP (in-use): \$2.92
  - Storage (80GB total): \$13
  - Snapshots (7-day retention): \$3
  - Secrets Manager: \$0.20
  TOTAL: ~\$21-25/month

Note: Static IP is only charged when VM is running. If VM is stopped,
      static IP costs \$7.30/month but will be available when VM restarts.

# ============================================================================
# DATABASE CREDENTIALS
# ============================================================================

Database Credentials:
  - Temporary location: /root/.moodle-credentials on VM
  - For production: Run 'sudo bash /opt/moodle-deployment/secrets-manager-setup.sh' to migrate to Secret Manager

# ============================================================================
# RESOURCE MANAGEMENT
# ============================================================================

View static IP:
  gcloud compute addresses describe $STATIC_IP_NAME --region=$REGION

Release static IP (when deleting VM):
  gcloud compute addresses delete $STATIC_IP_NAME --region=$REGION

WARNING: Do NOT release the static IP while VM is in use, or DNS will break!
EOF

log "Deployment info saved to: $DEPLOYMENT_INFO_FILE"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Moodle VM Deployment Complete!"
log "============================================"
log ""
log "Instance: $INSTANCE_NAME"
log "Zone: $ZONE"
log "Service Account: $SERVICE_ACCOUNT"
log ""
log "Static IP Address: $STATIC_IP (PERMANENT)"
log "  Name: $STATIC_IP_NAME"
log "  Cost: ~\$2.92/month (in-use)"
log ""
warn "============================================"
warn "IMPORTANT: DNS CONFIGURATION REQUIRED"
warn "============================================"
warn ""
warn "Before accessing Moodle with a domain:"
warn "  1. Configure DNS A record at your DNS provider"
warn "  2. Point your domain to: $STATIC_IP"
warn "  3. Wait 5-30 minutes for DNS propagation"
warn ""
warn "See detailed DNS setup instructions in:"
warn "  $DEPLOYMENT_INFO_FILE"
warn ""
log "============================================"
log ""
log "Temporary Access (IP-based):"
log "  http://$STATIC_IP/moodle/install.php"
log ""
log "SSH Access:"
log "  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
log ""
log "Estimated Monthly Cost: \$21-25"
log "  - VM (e2-medium): \$18-20"
log "  - Static IP: \$2.92"
log "  - Storage: \$13"
log "  - Snapshots: \$3"
log "  - Secrets Manager: \$0.20"
log ""
log "Next Steps:"
log "  1. Complete Moodle installation wizard (http://$STATIC_IP/moodle/install.php)"
log "  2. Configure DNS A record (see deployment info file)"
log "  3. Run SSL setup after DNS propagation"
log "  4. Run security hardening script"
log "  5. Configure monitoring"
log "  6. Migrate credentials to Secret Manager"
log ""
log "Full deployment details: $DEPLOYMENT_INFO_FILE"
log "============================================"

exit 0
