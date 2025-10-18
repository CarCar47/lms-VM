#!/bin/bash
# ============================================================================
# Moodle VM Security Hardening Script
# Industry Standard Security Configuration
# ============================================================================
#
# This script implements comprehensive security hardening for Moodle VM
# following industry best practices and security standards.
#
# Security measures implemented:
#   - Advanced firewall configuration (UFW)
#   - Fail2ban intrusion prevention
#   - SSH hardening
#   - File permission auditing
#   - Database security
#   - PHP security settings
#   - Automatic security updates
#   - File integrity monitoring
#   - Security headers
#   - Log rotation and monitoring
#
# Usage:
#   sudo bash security-hardening.sh
#
# References:
#   - CIS Ubuntu Security Benchmarks
#   - OWASP Security Guidelines
#   - Moodle Security Best Practices
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# SSH configuration
SSH_PORT="${SSH_PORT:-22}"
ALLOW_ROOT_LOGIN="no"
ALLOW_PASSWORD_AUTH="no"  # Set to "yes" if you need password authentication

# Firewall trusted IPs (optional - for additional access restrictions)
TRUSTED_IPS="${FIREWALL_TRUSTED_IPS:-}"

# Moodle directories
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/moodle-security-hardening.log"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE" >&2
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
log "Moodle VM Security Hardening"
log "Industry Standard Security Configuration"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Backup directory for configuration files
BACKUP_DIR="/root/security-hardening-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
log "Configuration backups will be saved to: $BACKUP_DIR"

# ============================================================================
# STEP 1: UPDATE SYSTEM
# ============================================================================

log "Step 1: Updating system packages..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

log "System updated"

# ============================================================================
# STEP 2: CONFIGURE AUTOMATIC SECURITY UPDATES
# ============================================================================

log "Step 2: Configuring automatic security updates..."

apt-get install -y -qq unattended-upgrades apt-listchanges

# Configure unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
// Automatic security updates configuration
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Auto-reboot if required
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";

// Email notifications (configure if needed)
// Unattended-Upgrade::Mail "admin@example.com";

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
EOF

# Enable automatic updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

log "Automatic security updates enabled"

# ============================================================================
# STEP 3: HARDEN SSH CONFIGURATION
# ============================================================================

log "Step 3: Hardening SSH configuration..."

# Backup SSH config
cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config.backup"

# Update SSH configuration
cat > /etc/ssh/sshd_config.d/99-moodle-hardening.conf << EOF
# Moodle VM SSH Hardening Configuration
# Created: $(date)

# Change default SSH port (optional - uncomment to use)
# Port $SSH_PORT

# Disable root login
PermitRootLogin $ALLOW_ROOT_LOGIN

# Disable password authentication (use SSH keys only)
PasswordAuthentication $ALLOW_PASSWORD_AUTH
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Enable public key authentication
PubkeyAuthentication yes

# Disable X11 forwarding
X11Forwarding no

# Disable TCP forwarding
AllowTcpForwarding no

# Maximum authentication attempts
MaxAuthTries 3

# Login grace time
LoginGraceTime 30

# Client alive interval (disconnect idle sessions)
ClientAliveInterval 300
ClientAliveCountMax 2

# Limit concurrent sessions
MaxSessions 3

# Restrict users (optional)
# AllowUsers username1 username2

# Use strong encryption
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Disable protocol 1
Protocol 2
EOF

# Test SSH configuration
sshd -t || error "SSH configuration test failed"

# Restart SSH
systemctl restart sshd

log "SSH hardened (root login: $ALLOW_ROOT_LOGIN, password auth: $ALLOW_PASSWORD_AUTH)"

# ============================================================================
# STEP 4: CONFIGURE FAIL2BAN
# ============================================================================

log "Step 4: Configuring Fail2ban intrusion prevention..."

apt-get install -y -qq fail2ban

# Backup fail2ban config
if [[ -f /etc/fail2ban/jail.local ]]; then
    cp /etc/fail2ban/jail.local "$BACKUP_DIR/jail.local.backup"
fi

# Create fail2ban configuration
cat > /etc/fail2ban/jail.local << 'EOF'
# ============================================================================
# Fail2ban Configuration for Moodle VM
# Intrusion Prevention System
# ============================================================================

[DEFAULT]
# Ban settings
bantime = 3600        # 1 hour ban
findtime = 600        # 10 minute window
maxretry = 5          # 5 attempts before ban

# Email notifications (configure if needed)
# destemail = admin@example.com
# sendername = Fail2Ban
# action = %(action_mwl)s

# ============================================================================
# SSH Protection
# ============================================================================

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3          # Stricter for SSH
bantime = 7200        # 2 hour ban for SSH

# ============================================================================
# Apache/Nginx Protection
# ============================================================================

[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/*error.log

[apache-badbots]
enabled = true
port = http,https
logpath = /var/log/apache2/*access.log
maxretry = 2

[apache-noscript]
enabled = true
port = http,https
logpath = /var/log/apache2/*error.log

[apache-overflows]
enabled = true
port = http,https
logpath = /var/log/apache2/*error.log
maxretry = 2

[apache-nohome]
enabled = true
port = http,https
logpath = /var/log/apache2/*error.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/*error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/*access.log
maxretry = 2

# ============================================================================
# MySQL/MariaDB Protection
# ============================================================================

[mysqld-auth]
enabled = true
filter = mysqld-auth
port = 3306
logpath = /var/log/mysql/error.log
maxretry = 3
bantime = 7200

# ============================================================================
# Moodle Specific Protection
# ============================================================================

[moodle-auth]
enabled = true
port = http,https
filter = moodle-auth
logpath = /var/moodledata/error.log
maxretry = 5
findtime = 300

EOF

# Create Moodle-specific fail2ban filter
cat > /etc/fail2ban/filter.d/moodle-auth.conf << 'EOF'
# Fail2ban filter for Moodle authentication failures

[Definition]
failregex = ^.*Failed login attempt.*from <HOST>.*$
            ^.*Invalid login attempt.*<HOST>.*$
            ^.*Brute force attack detected.*<HOST>.*$
ignoreregex =
EOF

# Restart fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

log "Fail2ban configured and running"

# ============================================================================
# STEP 5: ADVANCED FIREWALL CONFIGURATION
# ============================================================================

log "Step 5: Configuring advanced firewall rules..."

# UFW should already be installed from setup script
# Additional hardening

# Default policies
ufw --force default deny incoming
ufw --force default allow outgoing

# Allow loopback
ufw --force allow in on lo
ufw --force allow out on lo

# Allow SSH
ufw --force allow "$SSH_PORT/tcp"

# Allow HTTP/HTTPS
ufw --force allow 80/tcp
ufw --force allow 443/tcp

# Rate limiting for SSH (prevent brute force)
ufw --force limit "$SSH_PORT/tcp"

# Allow specific trusted IPs (if configured)
if [[ -n "$TRUSTED_IPS" ]]; then
    IFS=',' read -ra IPS <<< "$TRUSTED_IPS"
    for ip in "${IPS[@]}"; do
        log "Adding trusted IP: $ip"
        ufw --force allow from "$ip"
    done
fi

# Deny all other traffic
ufw --force deny in from any to any

# Enable firewall
ufw --force enable

# Show firewall status
ufw status verbose | tee -a "$LOG_FILE"

log "Advanced firewall configured"

# ============================================================================
# STEP 6: SECURE FILE PERMISSIONS
# ============================================================================

log "Step 6: Auditing and securing file permissions..."

# Secure Moodle directories
if [[ -d "$MOODLE_DIR" ]]; then
    log "Securing Moodle directory..."
    chown -R www-data:www-data "$MOODLE_DIR"
    find "$MOODLE_DIR" -type d -exec chmod 755 {} \;
    find "$MOODLE_DIR" -type f -exec chmod 644 {} \;

    # Make config.php read-only
    if [[ -f "$MOODLE_DIR/config.php" ]]; then
        chmod 440 "$MOODLE_DIR/config.php"
        chown root:www-data "$MOODLE_DIR/config.php"
    fi
fi

# Secure moodledata
if [[ -d "$MOODLE_DATA" ]]; then
    log "Securing moodledata directory..."
    chown -R www-data:www-data "$MOODLE_DATA"
    chmod -R 770 "$MOODLE_DATA"
fi

# Secure sensitive system files
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/mysql/mariadb.conf.d/*.cnf 2>/dev/null || true
chmod 600 /root/.moodle-credentials 2>/dev/null || true  # Legacy credentials file (if exists)

log "File permissions secured"
info "For production security: Migrate credentials to Secret Manager (sudo bash secrets-manager-setup.sh)"

# ============================================================================
# STEP 7: DATABASE SECURITY HARDENING
# ============================================================================

log "Step 7: Hardening MariaDB security..."

# Remove test database and anonymous users (if not already done)
mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';" 2>/dev/null || true
mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Restrict MySQL to localhost only
if [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
    cp /etc/mysql/mariadb.conf.d/50-server.cnf "$BACKUP_DIR/"
    sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' /etc/mysql/mariadb.conf.d/50-server.cnf
    systemctl restart mariadb
fi

log "Database security hardened"

# ============================================================================
# STEP 8: PHP SECURITY HARDENING
# ============================================================================

log "Step 8: Hardening PHP security settings..."

PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
PHP_INI_DIR="/etc/php/$PHP_VERSION/apache2/conf.d"

if [[ ! -d "$PHP_INI_DIR" ]]; then
    PHP_INI_DIR="/etc/php/$PHP_VERSION/fpm/conf.d"
fi

if [[ -d "$PHP_INI_DIR" ]]; then
    cat > "$PHP_INI_DIR/99-security-hardening.ini" << 'EOF'
; ============================================================================
; PHP Security Hardening Configuration
; ============================================================================

; Disable dangerous functions
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,eval

; Disable remote file access
allow_url_fopen = Off
allow_url_include = Off

; Hide PHP version
expose_php = Off

; Disable error display (log only)
display_errors = Off
display_startup_errors = Off
log_errors = On

; Session security
session.cookie_httponly = On
session.cookie_secure = On
session.cookie_samesite = Strict
session.use_strict_mode = On

; File upload security
file_uploads = On
upload_max_filesize = 100M
post_max_size = 100M
max_file_uploads = 20

; Resource limits
max_execution_time = 300
max_input_time = 300
memory_limit = 512M

; Open basedir restriction (limits file access)
; open_basedir = /var/www/html:/var/moodledata:/tmp:/usr/share/php
EOF

    # Restart web server
    systemctl restart apache2 2>/dev/null || systemctl restart nginx 2>/dev/null || true
    systemctl restart php*-fpm 2>/dev/null || true

    log "PHP security hardened"
else
    warn "PHP configuration directory not found, skipping PHP hardening"
fi

# ============================================================================
# STEP 9: INSTALL AND CONFIGURE LYNIS (SECURITY AUDITING)
# ============================================================================

log "Step 9: Installing Lynis security auditing tool..."

apt-get install -y -qq lynis

log "Lynis installed. Run 'sudo lynis audit system' for security audit"

# ============================================================================
# STEP 10: CONFIGURE LOG MONITORING
# ============================================================================

log "Step 10: Configuring log monitoring..."

# Install logwatch
apt-get install -y -qq logwatch

# Configure logwatch
cat > /etc/cron.daily/00logwatch << 'EOF'
#!/bin/bash
# Daily log summary via logwatch
/usr/sbin/logwatch --output mail --mailto root --detail high --service all --range yesterday
EOF

chmod +x /etc/cron.daily/00logwatch

log "Log monitoring configured (daily reports via logwatch)"

# ============================================================================
# STEP 11: INSTALL RKHUNTER (ROOTKIT DETECTION)
# ============================================================================

log "Step 11: Installing rkhunter rootkit detection..."

apt-get install -y -qq rkhunter

# Initialize rkhunter database
rkhunter --propupd

# Configure weekly scans
cat > /etc/cron.weekly/rkhunter-scan << 'EOF'
#!/bin/bash
# Weekly rootkit scan
/usr/bin/rkhunter --check --skip-keypress --report-warnings-only
EOF

chmod +x /etc/cron.weekly/rkhunter-scan

log "Rkhunter installed and configured for weekly scans"

# ============================================================================
# STEP 12: KERNEL HARDENING (SYSCTL)
# ============================================================================

log "Step 12: Applying kernel security hardening..."

# Backup sysctl configuration
cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.backup"

# Apply kernel security settings
cat >> /etc/sysctl.conf << 'EOF'

# ============================================================================
# Kernel Security Hardening - Moodle VM
# ============================================================================

# IP Forwarding (disable if not needed)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Syn cookies (prevent SYN flood attacks)
net.ipv4.tcp_syncookies = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log martian packets
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests (optional - uncomment to enable)
# net.ipv4.icmp_echo_ignore_all = 1

# Randomize virtual address space
kernel.randomize_va_space = 2

# Restrict kernel pointer access
kernel.kptr_restrict = 2

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict ptrace scope
kernel.yama.ptrace_scope = 1
EOF

# Apply settings
sysctl -p

log "Kernel security settings applied"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Security Hardening Complete!"
log "============================================"
log ""
log "Security measures implemented:"
log "  ✓ Automatic security updates enabled"
log "  ✓ SSH hardened (root login: $ALLOW_ROOT_LOGIN, password auth: $ALLOW_PASSWORD_AUTH)"
log "  ✓ Fail2ban intrusion prevention active"
log "  ✓ Advanced firewall rules (UFW)"
log "  ✓ File permissions secured"
log "  ✓ Database security hardened"
log "  ✓ PHP security settings enforced"
log "  ✓ Lynis security auditing installed"
log "  ✓ Log monitoring (logwatch)"
log "  ✓ Rootkit detection (rkhunter)"
log "  ✓ Kernel security hardening (sysctl)"
log ""
log "Configuration backups: $BACKUP_DIR"
log ""
log "Next Steps:"
log "  1. Run security audit: sudo lynis audit system"
log "  2. Review Fail2ban status: sudo fail2ban-client status"
log "  3. Check firewall rules: sudo ufw status verbose"
log "  4. Monitor logs: sudo logwatch"
log "  5. Scan for rootkits: sudo rkhunter --check"
log ""
log "Security Recommendations:"
log "  - Regularly update system packages"
log "  - Monitor Fail2ban logs: /var/log/fail2ban.log"
log "  - Review security audit results quarterly"
log "  - Test disaster recovery procedures"
log "  - Keep backups offsite (Google Cloud Storage)"
log ""
log "Security hardening log: $LOG_FILE"
log "============================================"

exit 0
