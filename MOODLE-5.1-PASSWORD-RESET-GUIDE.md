# Moodle 5.1 Password Reset Guide

## Critical Information

**IMPORTANT:** Do NOT use shell SQL commands or CLI tools with command-line password arguments to reset Moodle passwords. Shell escaping will corrupt password hashes containing special characters like ` (backticks), causing login failures.

## Why This Guide Exists

During production deployment, we discovered that using shell commands to reset passwords corrupts the password hash due to shell escaping of special characters. For example:

**BROKEN APPROACH** (Hash gets corrupted):
```bash
# DO NOT USE - Shell escaping corrupts the hash
mysql -u root -p'password' << EOF
UPDATE mdl_user SET password = '$hash' WHERE username = 'admin';
EOF
```

**Result**: Hash corruption - `$6$rounds=10000$...` becomes `=100003ZK...` (invalid)

## Safe Password Reset Methods

### Method 1: PHP Script Using Moodle Database API (RECOMMENDED)

This method avoids shell escaping by using Moodle's Database API directly.

**Step 1:** Create password reset script on the VM

```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="cat > /tmp/reset_admin_password.php << 'ENDPHP'
<?php
/**
 * Moodle Admin Password Reset Script
 * Safe method that avoids shell escaping issues
 *
 * Usage: sudo -u www-data php /tmp/reset_admin_password.php
 */

define('CLI_SCRIPT', true);
require_once('/var/www/html/config.php');
require_once(\$CFG->libdir.'/moodlelib.php');

global \$DB;

// SET YOUR NEW PASSWORD HERE
\$username = 'admin';
\$new_password = 'YourNewPassword123!';  // Change this

echo \"===============================================\\n\";
echo \"Moodle Admin Password Reset\\n\";
echo \"===============================================\\n\\n\";

// Verify user exists
\$user = \$DB->get_record('user', ['username' => \$username]);
if (!\$user) {
    echo \"ERROR: User '\$username' not found\\n\";
    exit(1);
}

echo \"User found: \$username (ID: \$user->id)\\n\";
echo \"Email: \$user->email\\n\";
echo \"Auth method: \$user->auth\\n\\n\";

// Generate hash using Moodle's function
\$hash = hash_internal_user_password(\$new_password);

echo \"Generated password hash:\\n\";
echo \$hash . \"\\n\\n\";

// Update password using Database API (avoids shell escaping)
\$DB->set_field('user', 'password', \$hash, ['id' => \$user->id]);

echo \"Password updated in database\\n\\n\";

// Verify the password matches
\$user = \$DB->get_record('user', ['username' => \$username]);
if (validate_internal_user_password(\$user, \$new_password)) {
    echo \"✓ VERIFICATION SUCCESS: Password matches!\\n\";
    echo \"\\nYou can now login with:\\n\";
    echo \"  Username: \$username\\n\";
    echo \"  Password: \$new_password\\n\\n\";
    exit(0);
} else {
    echo \"✗ VERIFICATION FAILED: Password does not match\\n\";
    echo \"Please check the hash and try again\\n\\n\";
    exit(1);
}
ENDPHP
"

**Step 2:** Edit the script to set your new password

```bash
# SSH into the VM
gcloud compute ssh moodle-vm-demo --zone=us-central1-a

# Edit the script
sudo nano /tmp/reset_admin_password.php

# Change these lines:
# $username = 'admin';  // Change if needed
# $new_password = 'YourNewPassword123!';  // Set your new password
```

**Step 3:** Execute the script

```bash
sudo -u www-data php /tmp/reset_admin_password.php
```

**Step 4:** Verify the output

Expected output:
```
===============================================
Moodle Admin Password Reset
===============================================

User found: admin (ID: 2)
Email: admin@example.com
Auth method: manual

Generated password hash:
$6$rounds=10000$q5dowDr35Wbkcg1a$RdazjF.pXhVEBpja2KIIBrs94sSgDu50b9Cq3cTa8/vd0eExRaRnZVJOo0mp2Ze2zyGAY/ffxtXOK5zwSpliP/

Password updated in database

✓ VERIFICATION SUCCESS: Password matches!

You can now login with:
  Username: admin
  Password: YourNewPassword123!
```

### Method 2: Using Moodle's Official CLI Tool (Alternative)

Moodle provides an official password reset tool at `admin/cli/reset_password.php`. However, you must call it correctly to avoid shell escaping issues.

**CORRECT Usage** (Interactive Mode - Safest):
```bash
cd /var/www/html
sudo -u www-data php admin/cli/reset_password.php
# Script will prompt you for username and password interactively
# This avoids shell escaping issues
```

**Usage with Arguments** (Use with caution):
```bash
# Only safe if password has NO special shell characters
cd /var/www/html
sudo -u www-data php admin/cli/reset_password.php \
    --username=admin \
    --password='SimplePassword123' \
    --ignore-password-policy
```

**NEVER DO THIS** (Shell escaping risk):
```bash
# UNSAFE - Password with special characters gets corrupted
sudo -u www-data php admin/cli/reset_password.php \
    --username=admin \
    --password='P@ssw0rd!' \  # @ and ! will cause issues
    --ignore-password-policy
```

## Post-Password Reset Steps

### 1. Clear All Sessions

After resetting a password, clear all existing sessions:

```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo rm -rf /var/moodledata/sessions/*
sudo rm -rf /var/moodledata/cache/*
sudo rm -rf /var/moodledata/localcache/*
"
```

### 2. Restart Apache

```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo systemctl restart apache2
"
```

### 3. Test Login

1. Open browser in incognito mode (Ctrl+Shift+N)
2. Navigate to your Moodle site
3. Login with the new credentials
4. Verify access to admin panel

## Troubleshooting

### Issue: "Invalid Login" After Password Reset

**Symptoms:**
- Password reset reports success
- Login still shows "Invalid login"
- No errors in logs

**Root Cause:** Shell escaping corrupted the password hash

**Solution:** Use Method 1 (PHP script) instead of command-line tools

### Issue: Hash Corruption Detection

Check if your password hash is corrupted:

```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
SELECT id, username, LEFT(password, 30) as hash_preview, LENGTH(password) as hash_length
FROM moodle_lms.mdl_user
WHERE username='admin';
EOF
"
```

**Valid Hash:**
- Length: ~119-123 characters
- Starts with: `$6$rounds=10000$` or `$2y$10$`
- Example: `$6$rounds=10000$q5dowDr35Wbkcg1a$RdazjF.pXhVEBpja...`

**Corrupted Hash:**
- Length: < 100 characters
- Starts with: `=` or missing prefix
- Example: `=100003ZK.QBmQa3lLmu2/I21rpAk6a...`

### Issue: "wwwroot" Not Set

If you get "Invalid Login Token" errors:

```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
SELECT name, value FROM moodle_lms.mdl_config WHERE name='wwwroot';
EOF
"
```

If empty, add it:

```bash
gcloud compute ssh moodle-vm-demo --zone=us-central1-a --command="
sudo mysql -u root -p << 'EOF'
INSERT INTO moodle_lms.mdl_config (name, value) VALUES ('wwwroot', 'http://YOUR_IP_OR_DOMAIN')
ON DUPLICATE KEY UPDATE value='http://YOUR_IP_OR_DOMAIN';
EOF
"
```

## Security Best Practices

1. **Use Strong Passwords:** Minimum 12 characters, mix of upper/lower/numbers/symbols
2. **Delete Reset Scripts:** Remove `/tmp/reset_admin_password.php` after use
3. **Rotate Passwords Regularly:** Every 90 days for admin accounts
4. **Enable 2FA:** Use Moodle's MFA plugin for additional security
5. **Audit Logs:** Check `mdl_logstore_standard_log` for unauthorized access attempts

## Reference

- Moodle Official Documentation: https://docs.moodle.org/en/Managing_accounts
- Password Policy Configuration: https://docs.moodle.org/en/Password_policy
- CLI Admin Tools: https://docs.moodle.org/en/Administration_via_command_line

---

**Last Updated:** 2025-10-18
**Version:** 1.0.1
**Applies To:** Moodle 5.1 STABLE on Ubuntu 22.04 LTS