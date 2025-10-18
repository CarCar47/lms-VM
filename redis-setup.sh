#!/bin/bash
# ============================================================================
# Redis Cache Store Setup for Moodle
# Industry Standard Caching Configuration
# ============================================================================
#
# This script installs and configures Redis as the primary cache store for
# Moodle, replacing APCu for better performance (30-50% improvement).
#
# What Redis provides:
#   - Moodle Universal Cache (MUC) storage
#   - Session storage (optional)
#   - Application cache
#   - Persistent cache across PHP-FPM restarts
#
# Official Moodle recommendation (2025): Use Redis for production
#
# Usage:
#   sudo bash redis-setup.sh
#
# ============================================================================

set -e  # Exit on error
set -u  # Exit on undefined variable

# ============================================================================
# CONFIGURATION
# ============================================================================

REDIS_PORT=6379
REDIS_MAX_MEMORY="256mb"  # Adjust based on available RAM
REDIS_MAXMEMORY_POLICY="allkeys-lru"  # Evict least recently used keys

# Moodle directories
MOODLE_DIR="/var/www/html/moodle"
MOODLE_DATA="/var/moodledata"

# Log file
LOG_FILE="/var/log/redis-setup.log"

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
log "Redis Cache Store Setup for Moodle"
log "Industry Standard Configuration"
log "============================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Check if Redis is already installed
if systemctl is-active --quiet redis-server; then
    warn "Redis is already running. This will reconfigure it."
    read -p "Continue? (y/N): " continue_anyway
    if [[ "$continue_anyway" != "y" ]] && [[ "$continue_anyway" != "Y" ]]; then
        exit 0
    fi
fi

# ============================================================================
# STEP 1: INSTALL REDIS
# ============================================================================

log "Step 1: Installing Redis server..."

apt-get update -qq
apt-get install -y -qq redis-server redis-tools

log "Redis installed: $(redis-server --version | head -n1)"

# ============================================================================
# STEP 2: CONFIGURE REDIS FOR MOODLE
# ============================================================================

log "Step 2: Configuring Redis for Moodle..."

# Backup original config
if [[ -f /etc/redis/redis.conf ]]; then
    cp /etc/redis/redis.conf /etc/redis/redis.conf.backup-$(date +%Y%m%d_%H%M%S)
fi

# Create optimized Redis configuration
cat > /etc/redis/redis.conf << EOF
# ============================================================================
# Redis Configuration for Moodle
# Optimized for cache storage and session management
# ============================================================================

# Network
bind 127.0.0.1 ::1
port $REDIS_PORT
protected-mode yes
timeout 0
tcp-keepalive 300

# General
daemonize no
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16

# Snapshotting (persistence)
# For cache-only usage, disable RDB snapshots
# save 900 1
# save 300 10
# save 60 10000
save ""
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis

# Replication
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5

# Security
# requirepass foobared
# rename-command CONFIG ""

# Memory Management
maxmemory $REDIS_MAX_MEMORY
maxmemory-policy $REDIS_MAXMEMORY_POLICY
maxmemory-samples 5

# Lazy freeing (improves performance)
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

# Append Only File (AOF) - disabled for cache
appendonly no

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Latency monitor
latency-monitor-threshold 100

# Event notification
notify-keyspace-events ""

# Advanced config
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
rdb-save-incremental-fsync yes
EOF

# Set permissions
chown redis:redis /etc/redis/redis.conf
chmod 640 /etc/redis/redis.conf

log "Redis configuration created"

# ============================================================================
# STEP 3: CONFIGURE REDIS SYSTEMD SERVICE
# ============================================================================

log "Step 3: Configuring Redis systemd service..."

# Ensure Redis starts on boot and uses correct configuration
systemctl enable redis-server

# Restart Redis with new configuration
systemctl restart redis-server

# Wait for Redis to start
sleep 2

# Verify Redis is running
if systemctl is-active --quiet redis-server; then
    log "Redis is running"
else
    error "Redis failed to start. Check: sudo journalctl -u redis-server"
fi

# ============================================================================
# STEP 4: INSTALL REDIS PHP EXTENSION
# ============================================================================

log "Step 4: Installing Redis PHP extension..."

# Detect PHP version
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

# Install PHP Redis extension
apt-get install -y -qq php${PHP_VERSION}-redis

# Verify extension is loaded
if php -m | grep -q redis; then
    log "PHP Redis extension installed: $(php --ri redis | grep 'Redis Version' || echo 'installed')"
else
    error "PHP Redis extension failed to install"
fi

# Restart web server to load extension
if systemctl is-active --quiet apache2; then
    systemctl restart apache2
    log "Apache restarted"
elif systemctl is-active --quiet nginx; then
    systemctl restart nginx
    systemctl restart php${PHP_VERSION}-fpm
    log "Nginx and PHP-FPM restarted"
fi

# ============================================================================
# STEP 5: TEST REDIS CONNECTION
# ============================================================================

log "Step 5: Testing Redis connection..."

# Test Redis ping
if redis-cli ping | grep -q PONG; then
    log "Redis connection test: SUCCESS"
else
    error "Redis connection test: FAILED"
fi

# Test PHP Redis extension
php -r "
\$redis = new Redis();
if (\$redis->connect('127.0.0.1', $REDIS_PORT)) {
    echo 'PHP Redis connection: SUCCESS\n';
    \$redis->close();
} else {
    echo 'PHP Redis connection: FAILED\n';
    exit(1);
}
" || error "PHP Redis extension not working"

log "Redis connection tests passed"

# ============================================================================
# STEP 6: CONFIGURE MOODLE TO USE REDIS
# ============================================================================

log "Step 6: Updating Moodle configuration for Redis..."

if [[ -f "$MOODLE_DIR/config.php" ]]; then
    # Backup config.php
    cp "$MOODLE_DIR/config.php" "$MOODLE_DIR/config.php.pre-redis-$(date +%Y%m%d_%H%M%S)"

    # Check if Redis configuration already exists
    if grep -q "session_redis_host" "$MOODLE_DIR/config.php"; then
        log "Redis configuration already exists in config.php"
    else
        info "Redis configuration should be added to config.php manually or via config update"
        info "See redis-config.php.example for configuration"
    fi
else
    warn "Moodle config.php not found. Configure Redis after Moodle installation."
fi

# Create example Redis configuration
cat > "$MOODLE_DIR/redis-config.php.example" << 'EOF'
<?php
// ============================================================================
// Redis Cache Configuration for Moodle
// Add this to your config.php file (before require_once lib/setup.php)
// ============================================================================

// Redis session handler (replaces file-based sessions)
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = '127.0.0.1';
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix = 'moodle_session_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;

// Redis as MUC store (configure via Site Admin → Plugins → Caching)
// Or add to config.php for automated setup:
/*
$CFG->alternative_cache_factory_class = 'cache_factory';
// Then configure Redis store in:
// Site Administration → Plugins → Caching → Configuration → Add instance → Redis
*/

// ============================================================================
// Redis Configuration Notes:
// ============================================================================
//
// 1. Session storage (recommended):
//    - Faster than file-based sessions
//    - Persistent across PHP-FPM restarts
//    - Database 0 for sessions
//
// 2. MUC (Moodle Universal Cache):
//    - Database 1 for application cache
//    - Database 2 for session cache
//    - Configure via Site Admin interface
//
// 3. Performance impact:
//    - 30-50% faster page loads
//    - Reduced database queries
//    - Better concurrency handling
//
// ============================================================================
EOF

chown www-data:www-data "$MOODLE_DIR/redis-config.php.example"

log "Redis example configuration created: $MOODLE_DIR/redis-config.php.example"

# ============================================================================
# STEP 7: CREATE REDIS MONITORING SCRIPT
# ============================================================================

log "Step 7: Creating Redis monitoring script..."

cat > /usr/local/bin/redis-monitor << 'EOF'
#!/bin/bash
# Redis monitoring and statistics

echo "========================================"
echo "Redis Status"
echo "========================================"
echo ""

# Service status
systemctl status redis-server --no-pager | head -5

echo ""
echo "Redis Info:"
redis-cli INFO stats | grep -E "total_commands_processed|instantaneous_ops_per_sec|used_memory_human|connected_clients"

echo ""
echo "Redis Memory:"
redis-cli INFO memory | grep -E "used_memory|maxmemory|mem_fragmentation_ratio"

echo ""
echo "Redis Keyspace:"
redis-cli INFO keyspace

echo ""
echo "Recent slow commands:"
redis-cli SLOWLOG GET 5

echo "========================================"
EOF

chmod +x /usr/local/bin/redis-monitor

log "Redis monitoring script created: /usr/local/bin/redis-monitor"

# ============================================================================
# FINAL SUMMARY
# ============================================================================

log "============================================"
log "Redis Setup Complete!"
log "============================================"
log ""
log "Redis Status:"
log "  Service: $(systemctl is-active redis-server)"
log "  Port: $REDIS_PORT"
log "  Max Memory: $REDIS_MAX_MEMORY"
log "  Policy: $REDIS_MAXMEMORY_POLICY"
log ""
log "PHP Redis Extension: $(php -m | grep redis || echo 'NOT LOADED')"
log ""
log "Next Steps:"
log "  1. Add Redis configuration to Moodle config.php"
log "     See: $MOODLE_DIR/redis-config.php.example"
log ""
log "  2. Configure MUC Redis store:"
log "     Site Administration → Plugins → Caching → Configuration"
log "     Add instance: Redis (localhost:$REDIS_PORT)"
log ""
log "  3. Clear Moodle cache:"
log "     sudo -u www-data php $MOODLE_DIR/admin/cli/purge_caches.php"
log ""
log "  4. Monitor Redis performance:"
log "     /usr/local/bin/redis-monitor"
log "     redis-cli INFO"
log "     redis-cli MONITOR (live commands)"
log ""
log "Configuration backup: $MOODLE_DIR/config.php.pre-redis-*"
log "Setup log: $LOG_FILE"
log "============================================"

exit 0
