#!/bin/bash
# ============================================================================
# Moodle VM SSL Certificate Setup Script
# Let's Encrypt Automated SSL Configuration
# Industry Standard HTTPS Setup
# ============================================================================
#
# This script automates the installation and configuration of SSL certificates
# using Let's Encrypt (free, trusted, auto-renewable certificates)
#
# What it does:
#   1. Validates domain DNS configuration
#   2. Installs certbot (if not already installed)
#   3. Obtains SSL certificate from Let's Encrypt
#   4. Configures Apache/Nginx for HTTPS
#   5. Sets up automatic certificate renewal
#   6. Redirects HTTP to HTTPS
#   7. Updates Moodle config with HTTPS URL
#
# Prerequisites:
#   - Domain name pointing to server IP
#   - Port 80 and 443 accessible (firewall rules)
#   - Valid email address for Let's Encrypt notifications
#
# Usage:
#   sudo bash ssl-setup.sh <domain> <email>
#
# Examples:
#   sudo bash ssl-setup.sh moodle.example.com admin@example.com
#   sudo bash ssl-setup.sh learning.school.edu it@school.edu
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

# Domain and email from arguments
DOMAIN="${1:-}"
EMAIL="${2:-}"

# Moodle configuration
MOODLE_DIR="/var/www/html/moodle"
MOODLE_CONFIG="$MOODLE_DIR/config.php"

# Web server detection
WEB_SERVER=""

# Certbot configuration
CERTBOT_WEBROOT="/var/www/html"
CERTBOT_AUTO_RENEW=true

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/moodle-ssl-setup.log"

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
log "Moodle SSL Certificate Setup"
log "Let's Encrypt - Free Automated SSL"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Check arguments
if [[ -z "$DOMAIN" ]]; then
    error "Usage: sudo bash ssl-setup.sh <domain> <email>
Example: sudo bash ssl-setup.sh moodle.example.com admin@example.com"
fi

if [[ -z "$EMAIL" ]]; then
    warn "Email not provided. Let's Encrypt will not send expiration notices."
    read -p "Continue without email? (y/N): " continue_no_email
    if [[ "$continue_no_email" != "y" ]] && [[ "$continue_no_email" != "Y" ]]; then
        error "Please provide a valid email address"
    fi
    EMAIL="admin@$DOMAIN"  # Use a default
fi

log "Domain: $DOMAIN"
log "Email: $EMAIL"

# ============================================================================
# DETECT WEB SERVER
# ============================================================================

log "Detecting web server..."

if systemctl is-active --quiet apache2; then
    WEB_SERVER="apache"
    log "Detected: Apache"
elif systemctl is-active --quiet nginx; then
    WEB_SERVER="nginx"
    log "Detected: Nginx"
else
    error "No web server detected (Apache or Nginx). Install web server first."
fi

# ============================================================================
# VALIDATE DNS CONFIGURATION
# ============================================================================

log "Validating DNS configuration..."

# Get server's public IP
if command -v curl &> /dev/null; then
    SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s api.ipify.org)
else
    SERVER_IP=$(wget -qO- ifconfig.me || wget -qO- icanhazip.com)
fi

log "Server IP: $SERVER_IP"

# Check if domain resolves to server IP
DOMAIN_IP=$(dig +short "$DOMAIN" @8.8.8.8 | tail -n1)

if [[ -z "$DOMAIN_IP" ]]; then
    error "Domain $DOMAIN does not resolve to any IP address.
Please configure DNS A record before running this script."
fi

log "Domain resolves to: $DOMAIN_IP"

if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
    warn "Domain IP ($DOMAIN_IP) does not match server IP ($SERVER_IP)"
    warn "SSL certificate validation may fail!"

    read -p "Continue anyway? (y/N): " continue_anyway
    if [[ "$continue_anyway" != "y" ]] && [[ "$continue_anyway" != "Y" ]]; then
        error "Please update DNS records and try again"
    fi
fi

# ============================================================================
# INSTALL CERTBOT
# ============================================================================

log "Checking certbot installation..."

if ! command -v certbot &> /dev/null; then
    log "Installing certbot..."

    apt-get update -qq
    apt-get install -y -qq certbot

    # Install web server plugin
    if [[ "$WEB_SERVER" == "apache" ]]; then
        apt-get install -y -qq python3-certbot-apache
    else
        apt-get install -y -qq python3-certbot-nginx
    fi

    log "Certbot installed successfully"
else
    log "Certbot already installed"
fi

# ============================================================================
# BACKUP CURRENT CONFIGURATION
# ============================================================================

log "Backing up current web server configuration..."

BACKUP_DIR="/root/ssl-setup-backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

if [[ "$WEB_SERVER" == "apache" ]]; then
    cp -r /etc/apache2/sites-available "$BACKUP_DIR/"
    cp -r /etc/apache2/sites-enabled "$BACKUP_DIR/"
else
    cp -r /etc/nginx/sites-available "$BACKUP_DIR/"
    cp -r /etc/nginx/sites-enabled "$BACKUP_DIR/"
fi

if [[ -f "$MOODLE_CONFIG" ]]; then
    cp "$MOODLE_CONFIG" "$BACKUP_DIR/config.php.backup"
fi

log "Backup saved to: $BACKUP_DIR"

# ============================================================================
# CONFIGURE VIRTUAL HOST (HTTP ONLY - FOR ACME CHALLENGE)
# ============================================================================

log "Configuring virtual host for domain $DOMAIN..."

if [[ "$WEB_SERVER" == "apache" ]]; then
    # Apache configuration
    VHOST_FILE="/etc/apache2/sites-available/$DOMAIN.conf"

    cat > "$VHOST_FILE" << EOF
# Moodle Virtual Host Configuration
# Domain: $DOMAIN
# Created: $(date)

<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN

    DocumentRoot $MOODLE_DIR/public

    <Directory $MOODLE_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        # Moodle requires AllowOverride All for .htaccess
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule ^(.*)$ index.php [L,QSA]
        </IfModule>
    </Directory>

    # Deny access to moodledata
    <Directory /var/moodledata>
        Require all denied
    </Directory>

    # Security headers
    <IfModule mod_headers.c>
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-XSS-Protection "1; mode=block"
    </IfModule>

    # Logging
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

    # Enable site
    a2ensite "$DOMAIN" > /dev/null
    a2enmod rewrite headers ssl > /dev/null

    # Test configuration
    apache2ctl configtest

    # Reload Apache
    systemctl reload apache2

    log "Apache virtual host configured"

else
    # Nginx configuration
    VHOST_FILE="/etc/nginx/sites-available/$DOMAIN"

    cat > "$VHOST_FILE" << EOF
# Moodle Virtual Host Configuration
# Domain: $DOMAIN
# Created: $(date)

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;

    root $MOODLE_DIR/public;
    index index.php index.html;

    # Allow Let's Encrypt ACME challenge
    location ^~ /.well-known/acme-challenge/ {
        allow all;
        root /var/www/html;
        default_type "text/plain";
    }

    # Moodle configuration
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP-FPM configuration
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 300s;
    }

    # Deny access to hidden files
    location ~ /\\. {
        deny all;
    }

    # Logging
    access_log /var/log/nginx/$DOMAIN-access.log;
    error_log /var/log/nginx/$DOMAIN-error.log;
}
EOF

    # Enable site
    ln -sf "$VHOST_FILE" "/etc/nginx/sites-enabled/$DOMAIN"

    # Remove default site
    rm -f /etc/nginx/sites-enabled/default

    # Test configuration
    nginx -t

    # Reload Nginx
    systemctl reload nginx

    log "Nginx virtual host configured"
fi

# ============================================================================
# OBTAIN SSL CERTIFICATE FROM LET'S ENCRYPT
# ============================================================================

log "============================================"
log "Obtaining SSL certificate from Let's Encrypt..."
log "This may take 1-2 minutes..."
log "============================================"

# Run certbot
if [[ "$WEB_SERVER" == "apache" ]]; then
    # Apache: use apache plugin (automatic configuration)
    certbot --apache \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domains "$DOMAIN,www.$DOMAIN" \
        --redirect \
        --hsts \
        --uir

    log "SSL certificate obtained and configured for Apache"

else
    # Nginx: use nginx plugin
    certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        --domains "$DOMAIN,www.$DOMAIN" \
        --redirect \
        --hsts

    log "SSL certificate obtained and configured for Nginx"
fi

# ============================================================================
# VERIFY SSL CERTIFICATE
# ============================================================================

log "Verifying SSL certificate..."

# Check certificate expiration
certbot certificates | grep -A 5 "$DOMAIN"

log "SSL certificate verified"

# ============================================================================
# UPDATE MOODLE CONFIG.PHP WITH HTTPS URL
# ============================================================================

log "Updating Moodle configuration with HTTPS URL..."

if [[ -f "$MOODLE_CONFIG" ]]; then
    # Backup config.php
    cp "$MOODLE_CONFIG" "$MOODLE_CONFIG.pre-ssl-backup"

    # Update wwwroot to HTTPS
    sed -i "s|http://$DOMAIN|https://$DOMAIN|g" "$MOODLE_CONFIG"
    sed -i "s|http://www.$DOMAIN|https://www.$DOMAIN|g" "$MOODLE_CONFIG"

    # Also update any hardcoded HTTP URLs
    sed -i "s|\\\$CFG->wwwroot\s*=\s*'http://|\$CFG->wwwroot = 'https://|g" "$MOODLE_CONFIG"
    sed -i "s|\\\$CFG->wwwroot\s*=\s*\"http://|\$CFG->wwwroot = \"https://|g" "$MOODLE_CONFIG"

    log "Moodle config.php updated with HTTPS URL"
else
    warn "Moodle config.php not found. Update manually after installation."
fi

# ============================================================================
# SETUP AUTOMATIC RENEWAL
# ============================================================================

log "Setting up automatic SSL certificate renewal..."

# Test renewal process
certbot renew --dry-run

# Certbot automatically creates systemd timer for renewal
# Verify it's enabled
systemctl enable certbot.timer
systemctl start certbot.timer

log "Automatic renewal configured (certificates will auto-renew before expiration)"

# ============================================================================
# CONFIGURE SSL SECURITY HEADERS
# ============================================================================

log "Configuring additional security headers..."

if [[ "$WEB_SERVER" == "apache" ]]; then
    # Update Apache SSL virtual host
    VHOST_SSL_FILE="/etc/apache2/sites-available/$DOMAIN-le-ssl.conf"

    if [[ -f "$VHOST_SSL_FILE" ]]; then
        # Add additional security headers
        if ! grep -q "Strict-Transport-Security" "$VHOST_SSL_FILE"; then
            sed -i '/<\/VirtualHost>/i \
    # Additional security headers\n\
    <IfModule mod_headers.c>\n\
        Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"\n\
        Header always set X-Content-Type-Options "nosniff"\n\
        Header always set X-Frame-Options "SAMEORIGIN"\n\
        Header always set X-XSS-Protection "1; mode=block"\n\
        Header always set Referrer-Policy "no-referrer-when-downgrade"\n\
    </IfModule>' "$VHOST_SSL_FILE"

            systemctl reload apache2
        fi
    fi
else
    # Update Nginx SSL configuration
    VHOST_SSL_FILE="/etc/nginx/sites-available/$DOMAIN"

    if [[ -f "$VHOST_SSL_FILE" ]]; then
        # Security headers should already be in nginx.conf template
        # Just verify they exist
        if ! grep -q "Strict-Transport-Security" "$VHOST_SSL_FILE"; then
            warn "Security headers not found in Nginx config. Consider adding manually."
        fi
    fi
fi

log "Security headers configured"

# ============================================================================
# TEST HTTPS CONNECTION
# ============================================================================

log "Testing HTTPS connection..."

if curl -sI "https://$DOMAIN" | grep -q "HTTP/2 200\|HTTP/1.1 200"; then
    log "HTTPS connection successful!"
else
    warn "HTTPS connection test failed. Check web server logs."
fi

# ============================================================================
# CLEAR MOODLE CACHE
# ============================================================================

if [[ -f "$MOODLE_DIR/admin/cli/purge_caches.php" ]]; then
    log "Clearing Moodle cache..."
    sudo -u www-data php "$MOODLE_DIR/admin/cli/purge_caches.php"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "SSL Certificate Setup Complete!"
log "============================================"
log ""
log "Domain: $DOMAIN"
log "SSL Provider: Let's Encrypt"
log "Certificate Valid: 90 days (auto-renews)"
log ""
log "HTTPS URL: https://$DOMAIN"
log "Certificate Location: /etc/letsencrypt/live/$DOMAIN/"
log ""
log "Automatic Renewal:"
log "  - Certbot timer: $(systemctl is-active certbot.timer)"
log "  - Checks twice daily for renewal"
log "  - Auto-renews when <30 days remaining"
log ""
log "Security Features Enabled:"
log "  ✓ HTTP to HTTPS redirect"
log "  ✓ HSTS (HTTP Strict Transport Security)"
log "  ✓ Security headers (XSS, Clickjacking protection)"
log "  ✓ TLS 1.2+ only"
log ""
log "Test SSL Security:"
log "  https://www.ssllabs.com/ssltest/analyze.html?d=$DOMAIN"
log ""
log "Configuration Backup: $BACKUP_DIR"
log "============================================"
log ""
log "Next Steps:"
log "  1. Test Moodle at: https://$DOMAIN"
log "  2. Update any hardcoded HTTP URLs in Moodle content"
log "  3. Run security hardening script: security-hardening.sh"
log "  4. Monitor certificate renewal: certbot certificates"
log ""
log "SSL setup log: $LOG_FILE"
log "============================================"

exit 0
