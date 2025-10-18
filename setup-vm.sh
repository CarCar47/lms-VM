#!/bin/bash
# ============================================================================
# Moodle 5.1 STABLE - VM Setup Script
# LAMP Stack Installation for Ubuntu 22.04 LTS
# Industry Standard Configuration
# ============================================================================
#
# This script installs and configures a complete LAMP stack optimized for
# Moodle 5.1 on Ubuntu 22.04 LTS following official Moodle recommendations
# and industry best practices.
#
# Requirements:
#   - Ubuntu 22.04 LTS (fresh installation)
#   - Root or sudo access
#   - Minimum 2GB RAM, 2 vCPU
#   - 30GB+ persistent disk
#
# Usage:
#   sudo bash setup-vm.sh
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION VARIABLES
# ============================================================================

MOODLE_VERSION="5.1"
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"
BACKUP_DIR="/var/backups/moodle"
LOG_FILE="/var/log/moodle-setup.log"

# Database configuration (will be set from environment or prompts)
DB_NAME="${MOODLE_DB_NAME:-moodle_lms}"
DB_USER="${MOODLE_DB_USER:-moodle_user}"
DB_PASSWORD="${MOODLE_DB_PASSWORD:-}"
DB_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"

# PHP version (Moodle 5.1 requires PHP 8.2+)
PHP_VERSION="8.2"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
    exit 1
}

warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# PREFLIGHT CHECKS
# ============================================================================

log "============================================"
log "Moodle 5.1 LAMP Stack Setup"
log "Ubuntu 22.04 LTS"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Check Ubuntu version
if ! grep -q "Ubuntu 22.04" /etc/os-release; then
    error "This script requires Ubuntu 22.04 LTS"
fi

# Check available disk space (minimum 20GB)
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
if [[ $AVAILABLE_SPACE -lt 20000000 ]]; then
    error "Insufficient disk space. Minimum 20GB required."
fi

log "Preflight checks passed"

# ============================================================================
# STEP 1: SYSTEM UPDATE
# ============================================================================

log "Step 1: Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get autoremove -y -qq
log "System updated successfully"

# ============================================================================
# STEP 2: INSTALL APACHE2
# ============================================================================

log "Step 2: Installing Apache2..."
apt-get install -y -qq apache2

# Enable required Apache modules
a2enmod rewrite
a2enmod ssl
a2enmod headers
a2enmod expires
a2enmod deflate
a2enmod http2

# Configure Apache for production
cat > /etc/apache2/conf-available/moodle-security.conf << 'EOF'
# Moodle Security Headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "no-referrer-when-downgrade"
</IfModule>

# Hide Apache version
ServerTokens Prod
ServerSignature Off
EOF

a2enconf moodle-security

systemctl enable apache2
systemctl restart apache2
log "Apache2 installed and configured"

# ============================================================================
# STEP 3: INSTALL MARIADB
# ============================================================================

log "Step 3: Installing MariaDB..."
apt-get install -y -qq mariadb-server mariadb-client

# Start MariaDB
systemctl enable mariadb
systemctl start mariadb

# Prompt for root password if not set
if [[ -z "$DB_ROOT_PASSWORD" ]]; then
    log "Setting up MariaDB root password..."
    DB_ROOT_PASSWORD=$(openssl rand -base64 32)
    log "Generated root password (save this): $DB_ROOT_PASSWORD"
fi

# Secure MariaDB installation (non-interactive)
mysql -e "UPDATE mysql.user SET Password=PASSWORD('${DB_ROOT_PASSWORD}') WHERE User='root';"
mysql -e "DELETE FROM mysql.user WHERE User='';"
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "DROP DATABASE IF EXISTS test;"
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql -e "FLUSH PRIVILEGES;"

log "MariaDB installed and secured"

# ============================================================================
# STEP 4: CREATE MOODLE DATABASE
# ============================================================================

log "Step 4: Creating Moodle database..."

# Prompt for database password if not set
if [[ -z "$DB_PASSWORD" ]]; then
    DB_PASSWORD=$(openssl rand -base64 32)
    log "Generated database password (save this): $DB_PASSWORD"
fi

# Create database and user
mysql -u root -p"${DB_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

log "Database created: ${DB_NAME}"
log "Database user created: ${DB_USER}"

# ============================================================================
# STEP 5: INSTALL PHP 8.2 WITH ALL REQUIRED EXTENSIONS
# ============================================================================

log "Step 5: Installing PHP ${PHP_VERSION} with all Moodle extensions..."

# Add PHP repository
apt-get install -y -qq software-properties-common
add-apt-repository -y ppa:ondrej/php
apt-get update -qq

# Install PHP and all required extensions for Moodle 5.1
# Based on official Moodle documentation
apt-get install -y -qq \
    php${PHP_VERSION} \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-mysqli \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-xmlrpc \
    php${PHP_VERSION}-soap \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-opcache \
    php${PHP_VERSION}-ldap \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-exif \
    php${PHP_VERSION}-fileinfo \
    php${PHP_VERSION}-tokenizer \
    libapache2-mod-php${PHP_VERSION}

# Enable PHP-FPM
systemctl enable php${PHP_VERSION}-fpm
systemctl start php${PHP_VERSION}-fpm

log "PHP ${PHP_VERSION} installed with all required extensions"

# ============================================================================
# STEP 6: CONFIGURE PHP FOR MOODLE
# ============================================================================

log "Step 6: Configuring PHP for Moodle..."

# Backup original php.ini
cp /etc/php/${PHP_VERSION}/apache2/php.ini /etc/php/${PHP_VERSION}/apache2/php.ini.backup

# Configure PHP settings for Moodle (official recommendations)
cat > /etc/php/${PHP_VERSION}/apache2/conf.d/99-moodle.ini << 'EOF'
; ============================================================================
; Moodle 5.1 PHP Configuration
; Based on official Moodle recommendations
; ============================================================================

[PHP]
; Memory and execution limits
memory_limit = 512M
upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
max_input_vars = 5000
max_input_time = 300

; Session configuration
session.save_handler = files
session.save_path = "/var/lib/php/sessions"
session.gc_maxlifetime = 7200

; Timezone
date.timezone = America/New_York

; Error reporting (production)
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/php_errors.log

; Performance optimizations
realpath_cache_size = 4M
realpath_cache_ttl = 600

[opcache]
; OPcache configuration for Moodle 5.1
; Official Moodle recommendation for PHP 8.2
opcache.enable = 1
opcache.memory_consumption = 512
opcache.max_accelerated_files = 16229
opcache.interned_strings_buffer = 16
opcache.validate_timestamps = 1
opcache.revalidate_freq = 2
opcache.save_comments = 1
opcache.enable_cli = 0
opcache.fast_shutdown = 1
EOF

# Copy same config to CLI
cp /etc/php/${PHP_VERSION}/apache2/conf.d/99-moodle.ini /etc/php/${PHP_VERSION}/cli/conf.d/99-moodle.ini

# Restart Apache to apply PHP changes
systemctl restart apache2

log "PHP configured for Moodle"

# ============================================================================
# STEP 7: OPTIMIZE MARIADB FOR MOODLE
# ============================================================================

log "Step 7: Optimizing MariaDB for Moodle..."

# Calculate InnoDB buffer pool size (50% of available RAM, minimum 256M)
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
INNODB_BUFFER=$((TOTAL_RAM / 2))
if [[ $INNODB_BUFFER -lt 256 ]]; then
    INNODB_BUFFER=256
fi

# Create MariaDB optimization config
cat > /etc/mysql/mariadb.conf.d/99-moodle.cnf << EOF
# ============================================================================
# MariaDB Configuration for Moodle 5.1
# Optimized for ${TOTAL_RAM}MB RAM system
# ============================================================================

[mysqld]
# InnoDB settings (recommended for Moodle)
innodb_buffer_pool_size = ${INNODB_BUFFER}M
innodb_log_file_size = 256M
innodb_log_buffer_size = 16M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1

# Query cache (helps with repetitive queries)
query_cache_type = 1
query_cache_size = 32M
query_cache_limit = 2M

# Connection settings
max_connections = 100
max_allowed_packet = 64M

# Performance schema (disable to save RAM on small systems)
performance_schema = OFF

# Character set (required for Moodle)
character_set_server = utf8mb4
collation_server = utf8mb4_unicode_ci

# Binary logging (optional, for point-in-time recovery)
# Uncomment if you need binary logs for backups
# log_bin = /var/log/mysql/mysql-bin.log
# expire_logs_days = 7
# max_binlog_size = 100M

# Slow query log (for debugging)
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2
EOF

# Restart MariaDB to apply changes
systemctl restart mariadb

log "MariaDB optimized for Moodle"

# ============================================================================
# STEP 8: CREATE DIRECTORY STRUCTURE
# ============================================================================

log "Step 8: Creating directory structure..."

# Create Moodle directories
mkdir -p "$MOODLE_DIR"
mkdir -p "$MOODLE_DATA"
mkdir -p "$MOODLE_DATA/sessions"
mkdir -p "$MOODLE_DATA/cache"
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/automated"
mkdir -p "$BACKUP_DIR/manual"
mkdir -p "$BACKUP_DIR/database"

# Set ownership and permissions
chown -R www-data:www-data "$MOODLE_DIR"
chown -R www-data:www-data "$MOODLE_DATA"
chown -R www-data:www-data "$BACKUP_DIR"

chmod -R 755 "$MOODLE_DIR"
chmod -R 777 "$MOODLE_DATA"
chmod -R 755 "$BACKUP_DIR"

log "Directory structure created"

# ============================================================================
# STEP 9: CONFIGURE FIREWALL
# ============================================================================

log "Step 9: Configuring firewall..."

# Install and configure UFW
apt-get install -y -qq ufw

# Default policies
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow SSH (IMPORTANT!)
ufw --force allow 22/tcp

# Allow HTTP and HTTPS
ufw --force allow 80/tcp
ufw --force allow 443/tcp

# Enable firewall
ufw --force enable

log "Firewall configured (SSH, HTTP, HTTPS allowed)"

# ============================================================================
# STEP 10: INSTALL ADDITIONAL TOOLS
# ============================================================================

log "Step 10: Installing additional tools..."

apt-get install -y -qq \
    git \
    curl \
    wget \
    unzip \
    certbot \
    python3-certbot-apache \
    fail2ban \
    logrotate \
    cron

# Configure fail2ban for SSH protection
systemctl enable fail2ban
systemctl start fail2ban

log "Additional tools installed"

# ============================================================================
# STEP 11: SETUP CRON FOR MOODLE
# ============================================================================

log "Step 11: Setting up Moodle cron job..."

# Create cron job to run every minute (Moodle recommendation)
cat > /etc/cron.d/moodle << EOF
# Moodle cron job - runs every minute
# Official Moodle recommendation
* * * * * www-data /usr/bin/php ${MOODLE_DIR}/admin/cli/cron.php > /dev/null 2>&1
EOF

chmod 644 /etc/cron.d/moodle

log "Moodle cron job configured"

# ============================================================================
# STEP 12: CONFIGURE LOG ROTATION
# ============================================================================

log "Step 12: Configuring log rotation..."

cat > /etc/logrotate.d/moodle << 'EOF'
# Moodle log rotation configuration
/var/log/moodle-setup.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}

/var/log/php_errors.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
}
EOF

log "Log rotation configured"

# ============================================================================
# STEP 13: SAVE CREDENTIALS (Temporary File - Migrate to Secret Manager)
# ============================================================================

log "Step 13: Saving credentials..."

# Create temporary credentials file
# SECURITY NOTE: This file should be migrated to Google Secret Manager
# Run: sudo bash secrets-manager-setup.sh after deployment
cat > /root/.moodle-credentials << EOF
# ============================================================================
# Moodle Installation Credentials
# Generated: $(date)
# SECURITY WARNING: Migrate these to Google Secret Manager ASAP
# Run: sudo bash secrets-manager-setup.sh
# ============================================================================

# MariaDB Root
DB_ROOT_USER=root
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}

# Moodle Database
MOODLE_DB_NAME=${DB_NAME}
MOODLE_DB_USER=${DB_USER}
MOODLE_DB_PASSWORD=${DB_PASSWORD}

# Paths
MOODLE_DIR=${MOODLE_DIR}
MOODLE_DATA=${MOODLE_DATA}
BACKUP_DIR=${BACKUP_DIR}

# URLs (update after domain setup)
# MOODLE_WWWROOT=https://yourdomain.com
EOF

chmod 600 /root/.moodle-credentials

warn "Credentials saved to /root/.moodle-credentials (TEMPORARY)"
warn "For production: Run 'sudo bash secrets-manager-setup.sh' to migrate to Secret Manager"

# ============================================================================
# STEP 14: CREATE ENVIRONMENT FILE
# ============================================================================

log "Step 14: Creating environment file..."

cat > /etc/environment.d/moodle.conf << EOF
# Moodle environment variables
MOODLE_DB_NAME=${DB_NAME}
MOODLE_DB_USER=${DB_USER}
MOODLE_DB_PASSWORD=${DB_PASSWORD}
MOODLE_DATAROOT=${MOODLE_DATA}
EOF

chmod 600 /etc/environment.d/moodle.conf

log "Environment file created"

# ============================================================================
# STEP 15: CONFIGURE OS LOGIN WITH 2FA (Google Cloud Best Practice)
# ============================================================================

log "Step 15: Configuring OS Login with 2FA..."

# Install Google Cloud Guest Agent (required for OS Login)
if ! command -v google_guest_agent >/dev/null 2>&1; then
    log "Installing Google Cloud Guest Agent..."

    # Add Google Cloud package repository
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    echo "deb https://packages.cloud.google.com/apt google-compute-engine-bullseye-stable main" | tee /etc/apt/sources.list.d/google-cloud.list

    apt-get update -qq
    apt-get install -y -qq google-compute-engine google-osconfig-agent

    # Enable and start guest agent
    systemctl enable google-guest-agent
    systemctl start google-guest-agent

    log "Google Cloud Guest Agent installed"
else
    log "Google Cloud Guest Agent already installed"
fi

# Install PAM module for OS Login
if ! dpkg -l | grep -q "google-compute-engine-oslogin"; then
    log "Installing OS Login PAM module..."
    apt-get install -y -qq google-compute-engine-oslogin
    log "OS Login PAM module installed"
else
    log "OS Login PAM module already installed"
fi

# Configure NSS for OS Login
log "Configuring NSS for OS Login..."

# Backup NSS configuration
if [[ ! -f /etc/nsswitch.conf.backup ]]; then
    cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
fi

# Add OS Login to NSS databases
sed -i '/^passwd:/s/$/ cache_oslogin oslogin/' /etc/nsswitch.conf
sed -i '/^group:/s/$/ cache_oslogin oslogin/' /etc/nsswitch.conf
sed -i '/^shadow:/s/$/ cache_oslogin oslogin/' /etc/nsswitch.conf

# Remove duplicates
sed -i 's/\(cache_oslogin oslogin\)\s*\1/\1/g' /etc/nsswitch.conf

log "NSS configured for OS Login"

# Configure sudo permissions for OS Login users
cat > /etc/sudoers.d/google-oslogin << 'EOF'
# Google OS Login sudo configuration
# Allow users with specific IAM roles to use sudo

# Users with roles/compute.osAdminLogin can use sudo without password
%google-sudoers ALL=(ALL:ALL) NOPASSWD:ALL

# Users with roles/compute.osLogin get standard sudo (requires password)
# Configure this based on your organization's security policy
EOF

chmod 440 /etc/sudoers.d/google-oslogin

log "Sudo permissions configured for OS Login"

# Create instance metadata script for OS Login (to be set via gcloud)
cat > /tmp/enable-oslogin-2fa.sh << 'EOF'
#!/bin/bash
# Enable OS Login with 2FA for this instance
# Run this script after VM creation in Google Cloud

INSTANCE_NAME=$(hostname)
ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
PROJECT=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)

echo "Enabling OS Login with 2FA for instance: $INSTANCE_NAME"
echo "Zone: $ZONE"
echo "Project: $PROJECT"

# Enable OS Login with 2FA at instance level
gcloud compute instances add-metadata "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --metadata enable-oslogin=TRUE,enable-oslogin-2fa=TRUE

echo "OS Login with 2FA enabled successfully"
echo ""
echo "Important: Configure 2FA for users at https://myaccount.google.com/security"
echo ""
echo "Grant OS Login access to users:"
echo "  gcloud projects add-iam-policy-binding $PROJECT \\"
echo "    --member='user:email@example.com' \\"
echo "    --role='roles/compute.osLogin'"
echo ""
echo "Grant sudo access:"
echo "  gcloud projects add-iam-policy-binding $PROJECT \\"
echo "    --member='user:email@example.com' \\"
echo "    --role='roles/compute.osAdminLogin'"
EOF

chmod +x /tmp/enable-oslogin-2fa.sh

warn "OS Login prepared but NOT enabled yet"
log ""
log "To enable OS Login with 2FA after VM deployment:"
log "  1. Set project-wide metadata (recommended):"
log "     gcloud compute project-info add-metadata \\"
log "       --metadata enable-oslogin=TRUE,enable-oslogin-2fa=TRUE \\"
log "       --project=YOUR_PROJECT_ID"
log ""
log "  2. Or run on this instance: /tmp/enable-oslogin-2fa.sh"
log ""
log "  3. Grant IAM roles to users:"
log "     gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \\"
log "       --member='user:email@example.com' \\"
log "       --role='roles/compute.osLogin'"
log ""
log "  4. Users must configure 2FA at: https://myaccount.google.com/security"
log "     - Google recommends security keys/passkeys (phishing-resistant)"
log "     - Alternatives: Google Authenticator, Google Prompt"
log ""
log "  5. Connect via OS Login:"
log "     gcloud compute ssh INSTANCE_NAME --zone=ZONE --project=PROJECT_ID"
log ""

log "OS Login with 2FA configuration complete"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Moodle LAMP Stack Setup Complete!"
log "============================================"
log ""
log "System Information:"
log "  OS: Ubuntu 22.04 LTS"
log "  Apache: $(apache2 -v | head -n1 | awk '{print $3}')"
log "  MariaDB: $(mysql --version | awk '{print $5}' | cut -d- -f1)"
log "  PHP: $(php -v | head -n1 | awk '{print $2}')"
log ""
log "Moodle Configuration:"
log "  Moodle Directory: ${MOODLE_DIR}"
log "  Moodle Data: ${MOODLE_DATA}"
log "  Database Name: ${DB_NAME}"
log "  Database User: ${DB_USER}"
log ""
log "Security:"
log "  Firewall: Enabled (SSH, HTTP, HTTPS)"
log "  Fail2ban: Enabled"
log "  SSL: Ready for Let's Encrypt (run ssl-setup.sh)"
log "  OS Login: Configured (enable with gcloud metadata)"
log "  2FA: Ready for Google Cloud mandatory MFA (2025)"
log ""
log "Next Steps:"
log "  1. Copy Moodle files to ${MOODLE_DIR}"
log "  2. Run: chown -R www-data:www-data ${MOODLE_DIR}"
log "  3. Access: http://SERVER_IP/moodle"
log "  4. Complete Moodle installation wizard"
log "  5. Run ssl-setup.sh to enable HTTPS"
log "  6. Run security-hardening.sh for additional security"
log "  7. Run redis-setup.sh for 30-50% performance boost (recommended)"
log ""
log "Performance Enhancement Scripts (optional):"
log "  - redis-setup.sh: Install Redis cache (30-50% performance boost)"
log ""
log "Security Enhancement Scripts (recommended):"
log "  - cis-hardening.sh --audit-only: Audit CIS compliance"
log "  - cis-hardening.sh --level 1: Apply CIS Level 1 hardening"
log "  - cis-hardening.sh --install-cron: Install monthly compliance checks"
log "  - setup-apache-ratelimit.sh: Install Apache rate limiting (DDoS protection)"
log "  - setup-apache-ratelimit.sh --mod-security: Full WAF with ModSecurity"
log "  - secrets-manager-setup.sh: Migrate credentials to Secret Manager"
log "  - security-hardening.sh: Additional system hardening"
log ""
log "Monitoring & Maintenance Scripts (recommended):"
log "  - monitoring-setup.sh: Cloud Operations monitoring & logging"
log "  - database-maintenance.sh --install-cron: Automated DB maintenance"
log "  - moodle-security-check.sh --install-cron: Monthly security audits"
log "  - backup-validation.sh --install-cron: Monthly backup validation"
log ""
log "Credentials saved to: /root/.moodle-credentials"
log "Setup log saved to: ${LOG_FILE}"
log "============================================"

exit 0
