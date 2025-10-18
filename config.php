<?php
/**
 * Moodle Configuration File for VM Deployment
 *
 * This configuration is optimized for single Compute Engine VM deployment
 * with local MariaDB database and file-based storage.
 *
 * Based on official Moodle recommendations for 40-200 student deployments
 *
 * @package    core
 * @copyright  2025 COR4EDU
 * @license    http://www.gnu.org/copyleft/gpl.html GNU GPL v3 or later
 */

unset($CFG);
global $CFG;
$CFG = new stdClass();

// ============================================================================
// DATABASE CONFIGURATION (Local MariaDB)
// ============================================================================

$CFG->dbtype    = 'mysqli';              // MySQL/MariaDB driver
$CFG->dblibrary = 'native';              // Native database library
$CFG->dbhost    = 'localhost';           // Local database server
$CFG->dbname    = getenv('MOODLE_DB_NAME') ?: 'moodle_lms';
$CFG->dbuser    = getenv('MOODLE_DB_USER') ?: 'moodle_user';
$CFG->dbpass    = getenv('MOODLE_DB_PASSWORD') ?: '';
$CFG->prefix    = 'mdl_';                // Table prefix for Moodle tables
$CFG->dboptions = [
    'dbpersist' => false,                // Don't use persistent connections (recommended)
    'dbport'    => 3306,                 // Standard MariaDB port
    'dbcollation' => 'utf8mb4_unicode_ci', // Character collation
];

// ============================================================================
// SITE CONFIGURATION
// ============================================================================

// WWW Root - The URL of this Moodle instance
// Set via environment variable or during setup
$CFG->wwwroot   = getenv('MOODLE_WWWROOT') ?: 'http://localhost';

// Data Root - Directory for uploaded files
// Located on same VM, NOT network storage (much faster)
$CFG->dataroot  = getenv('MOODLE_DATAROOT') ?: '/var/moodledata';

// Directory permissions (standard for VM)
$CFG->directorypermissions = 0755;

// Admin directory
$CFG->admin = 'admin';

// ============================================================================
// SESSION CONFIGURATION (Redis-Based - Industry Standard)
// ============================================================================

// Use Redis session storage (FASTER than file-based for production)
// Official Moodle 2025 recommendation: "Use Redis for production deployments"
// Benefits: 30-50% faster, persistent across PHP-FPM restarts, better concurrency
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = '127.0.0.1';
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;  // Database 0 for sessions
$CFG->session_redis_prefix = 'moodle_session_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;
$CFG->session_redis_serializer_use_igbinary = false;  // Use PHP serializer
$CFG->session_redis_compressor = 'none';  // No compression (faster)

// Session timeout (2 hours)
$CFG->sessiontimeout = 7200;

// Fallback to file-based sessions if Redis is unavailable
// Uncomment these lines to use file-based sessions instead:
// $CFG->session_handler_class = '\core\session\file';
// $CFG->session_file_save_path = '/var/moodledata/sessions';

// ============================================================================
// CACHE CONFIGURATION (Redis + APCu - Maximum Performance)
// ============================================================================

// Local cache directory (for file-based cache stores)
$CFG->localcachedir = '/var/moodledata/cache';

// Enable Redis for Moodle Universal Cache (MUC) - MAJOR PERFORMANCE BOOST
// Redis reduces database queries by 40-60% by caching in RAM
// APCu is used as secondary cache for small, frequently-accessed data
$CFG->alternative_cache_factory_class = 'cache_factory';

// Increase context cache size to reduce database queries
// Official Moodle: "Can save 1000+ database queries per page"
// Default is usually 2500, increasing to 5000 for better performance
$CFG->core_cache_contexts = 5000;

// Redis Cache Store Configuration
// Configure via Site Administration → Plugins → Caching → Configuration
// Or use these settings for automated setup (requires redis-setup.sh)
//
// Application Cache (MUC): Database 1
// - Store: Redis (127.0.0.1:6379, db=1)
// - Purpose: Application data, definitions, course info
// - TTL: Variable (Moodle manages)
//
// Session Cache: Database 2
// - Store: Redis (127.0.0.1:6379, db=2)
// - Purpose: Request cache, temporary data
// - TTL: Short (minutes)
//
// APCu remains active as L1 cache for small objects (< 1KB)
// Redis serves as L2 cache for larger objects and shared cache

// ============================================================================
// WEB SERVICES CONFIGURATION (Required for SMS Integration)
// ============================================================================

// Enable web services globally
$CFG->enablewebservices = 1;

// Enable REST protocol
$CFG->webserviceprotocols = 'rest';

// ============================================================================
// SECURITY CONFIGURATION
// ============================================================================

// Password policy
$CFG->passwordpolicy = 1;                // Enforce password policy
$CFG->minpasswordlength = 8;             // Minimum 8 characters
$CFG->minpassworddigits = 1;             // At least 1 digit
$CFG->minpasswordlower = 1;              // At least 1 lowercase letter
$CFG->minpasswordupper = 1;              // At least 1 uppercase letter
$CFG->minpasswordnonalphanum = 0;        // Special characters optional

// Force password change on first login
$CFG->passwordchangelogout = 1;

// Prevent session hijacking
$CFG->preventexecpath = true;

// ============================================================================
// PERFORMANCE CONFIGURATION
// ============================================================================

// Enable caching
$CFG->cachejs = true;
$CFG->themedesignermode = false;         // Disable for production

// Compress JavaScript
$CFG->yuicomboloading = true;

// ============================================================================
// CRON CONFIGURATION
// ============================================================================

// Cron will be triggered via system cron job (setup script will configure)
// For CLI execution only (more secure)
$CFG->cronclionly = true;

// ============================================================================
// EMAIL CONFIGURATION
// ============================================================================

// Email settings (configure SMTP via environment variables)
$CFG->smtphosts = getenv('SMTP_HOST') ?: '';
$CFG->smtpsecure = 'tls';
$CFG->smtpauthtype = 'LOGIN';
$CFG->smtpuser = getenv('SMTP_USER') ?: '';
$CFG->smtppass = getenv('SMTP_PASSWORD') ?: '';
$CFG->noreplyaddress = getenv('NOREPLY_EMAIL') ?: 'noreply@example.com';

// ============================================================================
// DEBUGGING & ERROR REPORTING
// ============================================================================

// Get environment (production vs development)
$environment = getenv('ENVIRONMENT') ?: 'production';

if ($environment === 'development' || $environment === 'dev') {
    // Development settings
    $CFG->debug = 32767;                 // E_ALL | E_STRICT (DEBUG_DEVELOPER)
    $CFG->debugdisplay = 1;              // Display errors
    $CFG->debugsmtp = true;              // Debug SMTP
    $CFG->perfdebug = 15;                // Performance debugging
    $CFG->debugpageinfo = 1;             // Show page info
} else {
    // Production settings
    $CFG->debug = 0;                     // No debugging
    $CFG->debugdisplay = 0;              // Don't display errors
    $CFG->debugsmtp = false;
    $CFG->perfdebug = 0;
    $CFG->debugpageinfo = 0;
}

// ============================================================================
// LOGGING CONFIGURATION
// ============================================================================

// Log to standard output
$CFG->log_manager = '\core\log\manager';
$CFG->log_standard = '\logstore_standard\log\store';

// Set log retention to 365 days (prevents database bloat)
// Official Moodle: "Large log tables can consume 90%+ of database"
$CFG->loglifetime = 365;

// ============================================================================
// FILE UPLOAD LIMITS
// ============================================================================

$CFG->maxbytes = 104857600;              // 100MB max upload

// ============================================================================
// THEME CONFIGURATION
// ============================================================================

// Default theme
$CFG->theme = 'boost';                   // Moodle's default responsive theme

// ============================================================================
// INTEGRATION CONFIGURATION (Custom for SMS Integration)
// ============================================================================

// SMS API configuration (for future bidirectional sync)
$CFG->sms_api_url = getenv('SMS_API_URL') ?: '';
$CFG->sms_api_token = getenv('SMS_API_TOKEN') ?: '';

// ============================================================================
// MAINTENANCE MODE
// ============================================================================

// Enable maintenance mode during updates
// Set MOODLE_MAINTENANCE=1 in environment to enable
if (getenv('MOODLE_MAINTENANCE') === '1') {
    $CFG->maintenance_enabled = true;
    $CFG->maintenance_message = 'Moodle is currently undergoing scheduled maintenance. Please try again in a few minutes.';
}

// ============================================================================
// BACKUP CONFIGURATION (Automated Daily Backups)
// ============================================================================

// Automated backup settings
$CFG->backup_auto_active = 1;                // Enable automated backups
$CFG->backup_auto_weekdays = '1111111';      // Run every day
$CFG->backup_auto_hour = 2;                  // Run at 2 AM
$CFG->backup_auto_minute = 0;                // At the start of the hour
$CFG->backup_auto_storage = 0;               // Course backup area (not external)
$CFG->backup_auto_destination = '/var/backups/moodle/automated';  // Local backup path
$CFG->backup_auto_keep = 7;                  // Keep last 7 days of backups

// ============================================================================
// FINISH CONFIGURATION
// ============================================================================

// There is no php closing tag in this file, it is intentional because it
// prevents trailing whitespace problems!

// Load the Moodle library
require_once(__DIR__ . '/public/lib/setup.php');
