# Troubleshooting Moodle 5.1 Login Issues

## Overview

This guide documents all known login issues encountered during Moodle 5.1 deployment on Ubuntu 22.04 LTS and their solutions. Based on production troubleshooting experience.

## Common Login Issues

### Issue #1: Invalid Login After Fresh Deployment

**Symptoms:**
- Site loads correctly
- Login page displays
- Entering credentials shows "Invalid login, please try again"
- No errors in Apache logs

**Root Cause:** Default admin password not set correctly during installation

**Solution:** Reset admin password using safe method (see [MOODLE-5.1-PASSWORD-RESET-GUIDE.md](MOODLE-5.1-PASSWORD-RESET-GUIDE.md))

---

### Issue #2: Invalid Login Token (CSRF Error)

**Symptoms:**
- Login attempt shows "Invalid Login Token"
- Apache logs show: `[php:notice] Invalid Login Token: admin`
- HTTP 303 redirect back to login page

**Root Cause:** Missing `wwwroot` setting in `mdl_config` database table

**How to Diagnose:**
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
SELECT name, value FROM moodle_lms.mdl_config WHERE name='wwwroot';
EOF
"
```

**Solution:**
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
INSERT INTO moodle_lms.mdl_config (name, value) VALUES ('wwwroot', 'http://YOUR_IP_OR_DOMAIN')
ON DUPLICATE KEY UPDATE value='http://YOUR_IP_OR_DOMAIN';
FLUSH TABLES;
EOF
"
```

**Verification:**
1. Clear browser cache or use incognito mode
2. Navigate to your Moodle site
3. Login token error should be resolved

---

### Issue #3: Password Hash Corruption (Shell Escaping)

**Symptoms:**
- Password reset command reports success
- Login still fails with "Invalid login"
- No errors in logs
- Hash in database is corrupted

**Root Cause:** Shell escaping corrupts password hashes containing special characters like `$`, `` ` ``, `!`

**How to Detect:**
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
SELECT id, username, LEFT(password, 30) as hash_preview, LENGTH(password) as hash_length
FROM moodle_lms.mdl_user
WHERE username='admin';
EOF
"
```

**Valid Hash Characteristics:**
- Length: 119-123 characters
- Starts with: `$6$rounds=10000$` or `$2y$10$`
- Example: `$6$rounds=10000$q5dowDr35Wbkcg1a$RdazjF...`

**Corrupted Hash Characteristics:**
- Length: < 100 characters
- Starts with: `=` or missing dollar sign prefix
- Example: `=100003ZK.QBmQa3lLmu2/I21rpAk6a...`

**Solution:** Use PHP script method to reset password (see [MOODLE-5.1-PASSWORD-RESET-GUIDE.md](MOODLE-5.1-PASSWORD-RESET-GUIDE.md#method-1-php-script-using-moodle-database-api-recommended))

---

### Issue #4: Undefined Property $libdir Error

**Symptoms:**
- Site returns HTTP 500 error
- Apache logs show: `PHP Warning: Undefined property: stdClass::$libdir in /var/www/html/lib/setup.php on line 26`

**Root Cause:** Manually setting `$CFG->dirroot` in config.php for Moodle 5.1

**Why This Happens:**
Moodle 5.1 has a new directory structure with `/public/` subdirectory. When dirroot is manually set to `/var/www/html` (not ending in `/public`), lib/setup.php tries to modify `$CFG->libdir` before it's defined.

**Broken Configuration:**
```php
$CFG->dirroot = '/var/www/html';  // WRONG - Causes libdir error
```

**Correct Configuration:**
```php
// Do NOT set $CFG->dirroot manually
// Let Moodle 5.1 auto-detect it
$CFG->wwwroot   = 'http://YOUR_IP_OR_DOMAIN';
$CFG->dataroot  = '/var/moodledata';
// ... other settings
require_once(__DIR__ . '/lib/setup.php');
```

**Solution:**
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo nano /var/www/html/config.php
# Remove the line: \$CFG->dirroot = '/var/www/html';
# Save and exit

sudo systemctl restart apache2
"
```

---

### Issue #5: Site Returns HTTP 500 After Config Changes

**Symptoms:**
- Site was working, now returns HTTP 500
- Made changes to config.php
- Apache logs show PHP syntax errors

**Common Causes:**
1. PHP syntax error in config.php
2. Incorrect quote escaping
3. Missing semicolon
4. Incorrect file path

**Diagnosis:**
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
php -l /var/www/html/config.php
"
```

**Solution:**
1. Check syntax: `php -l /var/www/html/config.php`
2. Review Apache error logs: `sudo tail -50 /var/log/apache2/error.log`
3. Restore from backup if available
4. Verify all quotes are properly escaped

---

### Issue #6: Can't Access Site After Password Reset

**Symptoms:**
- Password reset completed
- Still can't login
- Sessions not cleared

**Root Cause:** Old sessions cached in browser or on server

**Solution:**
```bash
# Clear server-side sessions
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo rm -rf /var/moodledata/sessions/*
sudo rm -rf /var/moodledata/cache/*
sudo rm -rf /var/moodledata/localcache/*
sudo systemctl restart apache2
"
```

Then:
1. Close all browser windows
2. Open new incognito window
3. Navigate to site
4. Attempt login

---

## Diagnostic Commands Reference

### Check Site Status
```bash
# Test site accessibility
curl -I http://YOUR_IP_OR_DOMAIN

# Expected: HTTP/1.1 200 OK or HTTP/1.1 303 See Other
```

### Check Database Connection
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
php -r \\\"
define('CLI_SCRIPT', true);
require_once('/var/www/html/config.php');
echo 'Database connection: ';
echo \\\$DB->get_dbvendor();
echo PHP_EOL;
\\\"
"
```

### Check Admin Account
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
SELECT id, username, email, auth, confirmed, suspended, deleted, LENGTH(password) as pwd_len
FROM moodle_lms.mdl_user
WHERE username='admin';
EOF
"
```

### Check Apache Error Logs
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo tail -100 /var/log/apache2/error.log
"
```

### Check PHP Configuration
```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
php -v
php -m | grep -i mysql
php -i | grep memory_limit
"
```

---

## Prevention Best Practices

### 1. Always Use Safe Password Reset Methods
- Use PHP scripts with Moodle Database API
- Avoid shell SQL commands for password updates
- See [MOODLE-5.1-PASSWORD-RESET-GUIDE.md](MOODLE-5.1-PASSWORD-RESET-GUIDE.md)

### 2. Never Manually Set $CFG->dirroot for Moodle 5.1
- Let Moodle auto-detect directory root
- Moodle 5.1 uses `/public/` subdirectory structure
- Manual dirroot causes undefined $libdir errors

### 3. Always Set wwwroot in Database
- Required for CSRF token validation
- Set during installation or via SQL:
  ```sql
  INSERT INTO mdl_config (name, value) VALUES ('wwwroot', 'http://YOUR_DOMAIN')
  ON DUPLICATE KEY UPDATE value='http://YOUR_DOMAIN';
  ```

### 4. Clear Sessions After Major Changes
- After password resets
- After config.php changes
- After Apache restarts
- Commands:
  ```bash
  sudo rm -rf /var/moodledata/sessions/*
  sudo rm -rf /var/moodledata/cache/*
  sudo rm -rf /var/moodledata/localcache/*
  ```

### 5. Test in Incognito Mode
- Avoids cached sessions
- Avoids cached credentials
- Provides clean test environment

### 6. Validate config.php Syntax
- Before restarting Apache
- Command: `php -l /var/www/html/config.php`
- Expected: "No syntax errors detected"

---

## Quick Reference: Common Fixes

| Issue | Quick Fix |
|-------|-----------|
| Invalid Login Token | Add wwwroot to mdl_config table |
| Invalid Login (password) | Reset using PHP script method |
| HTTP 500 (libdir error) | Remove $CFG->dirroot from config.php |
| PHP syntax error | Run `php -l config.php` to validate |
| Corrupted password hash | Reset using PHP Database API |
| Cached sessions | Clear /var/moodledata/sessions/* |

---

## Escalation Path

If issues persist after trying all solutions:

1. Check Moodle official forums: https://moodle.org/forums
2. Review Moodle documentation: https://docs.moodle.org
3. Check server logs: `/var/log/apache2/error.log`
4. Verify database integrity: `OPTIMIZE TABLE mdl_user;`
5. Consider fresh installation if configuration is too broken

---

**Last Updated:** 2025-10-18
**Version:** 1.0.1
**Applies To:** Moodle 5.1 STABLE on Ubuntu 22.04 LTS
**Deployment:** Google Cloud Platform VM