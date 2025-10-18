# Moodle 5.1 Production Setup Guide

## Overview

This guide documents the complete production readiness checklist for deploying Moodle 5.1 STABLE on Google Cloud Platform VM. Follow these steps **after** initial VM deployment to ensure enterprise-grade security, data protection, and automation.

## Prerequisites

Before starting this production setup, ensure you have:

- ✅ **Deployed VM**: Successfully deployed using `deploy-production-golden.sh`
- ✅ **Domain Name**: Registered domain for your institution (e.g., `example.edu`)
- ✅ **Email Address**: Valid admin email for SSL certificate notifications
- ✅ **GCP Project**: Active Google Cloud Platform project with billing enabled
- ✅ **DNS Access**: Ability to configure DNS A records for your domain
- ✅ **VM Access**: SSH access to your Moodle VM instance

**Required Information:**
```bash
VM_NAME="YOUR_VM_NAME"              # e.g., moodle-vm-demo
ZONE="YOUR_GCP_ZONE"                # e.g., us-central1-a
PROJECT_ID="YOUR_GCP_PROJECT"       # e.g., my-school-project
DOMAIN="YOUR_DOMAIN"                # e.g., lms.example.edu
ADMIN_EMAIL="YOUR_EMAIL"            # e.g., admin@example.edu
BACKUP_BUCKET="YOUR_BACKUP_BUCKET"  # e.g., example-moodle-backups
```

---

## Production Readiness Checklist

### ☐ Step 1: Fix Moodle Cron Configuration

**Issue**: Moodle shows warning "The admin/cli/cron.php script has never been run"

**Root Cause**: Moodle 5.1 uses new directory structure without `/moodle/` subdirectory

#### 1.1 Verify Current Cron Configuration

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
cat /etc/cron.d/moodle
"
```

**Expected Output (BROKEN)**:
```
* * * * * www-data /usr/bin/php /var/www/html/moodle/admin/cli/cron.php > /dev/null 2>&1
```

#### 1.2 Fix Cron Path

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
echo '# Moodle cron - runs every minute (official recommendation)
* * * * * www-data /usr/bin/php /var/www/html/admin/cli/cron.php > /dev/null 2>&1' | sudo tee /etc/cron.d/moodle > /dev/null

sudo chmod 644 /etc/cron.d/moodle
"
```

#### 1.3 Verify Cron Works

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo -u www-data /usr/bin/php /var/www/html/admin/cli/cron.php 2>&1 | head -20
"
```

**Expected Output (SUCCESS)**:
```
Execute scheduled task: Cleanup old sessions (core\task\session_cleanup_task)
... started 16:38:33. Current memory use 14.0 MB.
... used 24 dbqueries
... used 0.12253284454346 seconds
Scheduled task complete: Cleanup old sessions
```

**Reference**: `templates/cron-examples/moodle-cron.template`

---

### ☐ Step 2: Configure SSL/HTTPS with Domain

**Issue**: Site only accessible via HTTP and IP address (insecure)

**Goal**: Enable HTTPS with valid SSL certificate using Let's Encrypt

#### 2.1 Configure DNS A Record

**IMPORTANT**: Complete this step BEFORE requesting SSL certificate

1. Log into your domain registrar's DNS management console
2. Create an A record:
   - **Host/Name**: `lms` (or desired subdomain)
   - **Type**: `A`
   - **TTL**: `1800` (30 minutes) or `3600` (1 hour)
   - **Value**: Your VM's external IP address

**Find Your VM's External IP**:
```bash
gcloud compute instances describe $VM_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
```

**Example DNS Configuration**:
```
Host: lms
Type: A
TTL:  1800
Value: 34.45.8.75
```

This creates: `lms.example.edu → 34.45.8.75`

#### 2.2 Verify DNS Propagation

```bash
nslookup $DOMAIN 8.8.8.8
```

**Expected Output**:
```
Server:  8.8.8.8
Address: 8.8.8.8#53

Name:    lms.example.edu
Address: 34.45.8.75
```

**IMPORTANT**: Wait for DNS to propagate (1-5 minutes) before proceeding

#### 2.3 Obtain SSL Certificate

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo certbot --apache -d $DOMAIN \
  --non-interactive \
  --agree-tos \
  --email $ADMIN_EMAIL \
  --redirect
"
```

**Expected Output**:
```
Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/$DOMAIN/fullchain.pem
Key is saved at:         /etc/letsencrypt/live/$DOMAIN/privkey.pem
This certificate expires on 2026-01-16.
```

**What This Does**:
- Obtains free SSL certificate from Let's Encrypt
- Configures Apache with HTTPS virtual host
- Sets up automatic HTTP→HTTPS redirect
- Installs systemd timer for auto-renewal (twice daily)

#### 2.4 Update Moodle Configuration

**Update config.php**:
```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo sed -i 's|^\$CFG->wwwroot.*|\$CFG->wwwroot   = '\''https://$DOMAIN'\'';|' /var/www/html/config.php
cat /var/www/html/config.php | grep wwwroot
"
```

**Update Database**:
```bash
# First, get database credentials from config.php
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
DB_USER=\$(grep dbuser /var/www/html/config.php | cut -d\"'\" -f2)
DB_PASS=\$(grep dbpass /var/www/html/config.php | cut -d\"'\" -f2)

sudo mysql -u \$DB_USER -p\$DB_PASS moodle_lms << 'EOF'
INSERT INTO mdl_config (name, value) VALUES ('wwwroot', 'https://$DOMAIN')
ON DUPLICATE KEY UPDATE value='https://$DOMAIN';
SELECT name, value FROM mdl_config WHERE name='wwwroot';
EOF
"
```

#### 2.5 Fix Apache DocumentRoot (Moodle 5.1 Structure)

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
# Fix HTTP virtual host
sudo sed -i 's|DocumentRoot /var/www/html/moodle/public|DocumentRoot /var/www/html/public|g' /etc/apache2/sites-enabled/$DOMAIN.conf

# Fix HTTPS virtual host
sudo sed -i 's|DocumentRoot /var/www/html/moodle/public|DocumentRoot /var/www/html/public|g' /etc/apache2/sites-enabled/$DOMAIN-le-ssl.conf

sudo systemctl restart apache2
"
```

#### 2.6 Clear Moodle Sessions

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo rm -rf /var/moodledata/sessions/*
sudo rm -rf /var/moodledata/cache/*
sudo rm -rf /var/moodledata/localcache/*
sudo systemctl restart apache2
"
```

#### 2.7 Verify HTTPS Working

```bash
curl -I https://$DOMAIN
```

**Expected Output**:
```
HTTP/1.1 200 OK
Date: Sat, 18 Oct 2025 17:15:32 GMT
Server: Apache/2.4.52 (Ubuntu)
Strict-Transport-Security: max-age=31536000
X-Frame-Options: sameorigin
X-Content-Type-Options: nosniff
```

**Test in Browser**:
1. Open incognito window: `Ctrl+Shift+N`
2. Navigate to: `https://YOUR_DOMAIN`
3. Verify green padlock icon appears
4. Verify HTTP redirects to HTTPS automatically

**Certificate Renewal**:
```bash
# Check auto-renewal status
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo systemctl status certbot.timer
"
```

**Expected**: `active (waiting)` - Certbot will auto-renew certificates twice daily

---

### ☐ Step 3: Configure Google Cloud Storage Backups

**Issue**: No offsite backup strategy in place

**Goal**: Implement 3-2-1 backup rule (3 copies, 2 storage types, 1 offsite)

#### 3.1 Create GCS Bucket

```bash
gsutil mb -p $PROJECT_ID -l $ZONE gs://$BACKUP_BUCKET
```

**Expected Output**:
```
Creating gs://YOUR_BACKUP_BUCKET/...
```

#### 3.2 Apply Lifecycle Policy

```bash
cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["daily/", "weekly/"]
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 365,
          "matchesPrefix": ["monthly/"]
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json gs://$BACKUP_BUCKET
```

**What This Does**:
- Deletes daily/weekly backups after 90 days
- Deletes monthly backups after 365 days
- Automatically manages storage costs

#### 3.3 Configure VM Environment Variables

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
echo '# Moodle Backup Configuration
export MOODLE_BACKUP_BUCKET=\"$BACKUP_BUCKET\"
export GCP_REGION=\"\${ZONE%-*}\"' | sudo tee /etc/environment.d/moodle-backup.conf > /dev/null

# Load environment variables immediately
sudo systemctl daemon-reload
"
```

#### 3.4 Test Manual Backup

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
# Set environment variables for current session
export MOODLE_BACKUP_BUCKET=\"$BACKUP_BUCKET\"
export GCP_REGION=\"\${ZONE%-*}\"

# Run manual backup
sudo -E bash /opt/moodle-deployment/backup-vm.sh
"
```

**Expected Output**:
```
============================================
Starting Moodle Backup
============================================
Backup type: daily
Step 1: Backing up database (moodle_lms)...
Database backup complete: 156.9K
Step 2: Backing up moodledata directory...
Moodledata backup complete: 45.6K
Step 7: Uploading to Google Cloud Storage...
Backup uploaded to gs://YOUR_BACKUP_BUCKET/daily/backup_20251018_171532/
Total backup size: 239.4K
Duration: 0m 9s
============================================
```

#### 3.5 Install Automated Backup Cron

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo bash /opt/moodle-deployment/backup-vm.sh --install-cron
"
```

**Expected Output**:
```
Cron job installed successfully
Backups will run daily at 2:00 AM
Log file: /var/log/moodle-backup.log
```

#### 3.6 Verify Backup in GCS

```bash
gsutil ls -lh gs://$BACKUP_BUCKET/daily/
```

**Expected Output**:
```
239.4 KiB  backup_20251018_171532/BACKUP_MANIFEST.txt
156.9 KiB  backup_20251018_171532/database.sql.gz
  45.6 KiB  backup_20251018_171532/moodledata.tar.gz
  36.9 KiB  backup_20251018_171532/config-files.tar.gz
```

**Reference**: `templates/cron-examples/moodle-backup.template`

---

### ☐ Step 4: Install Automated Maintenance Crons

**Issue**: Manual database maintenance required

**Goal**: Automate database optimization and security checks

#### 4.1 Install Database Maintenance Cron

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
echo '# Moodle database maintenance - runs daily at 3 AM (after backups)
0 3 * * * root /bin/bash /opt/moodle-deployment/database-maintenance.sh >> /var/log/moodle-maintenance.log 2>&1' | sudo tee /etc/cron.d/moodle-database-maintenance > /dev/null

sudo chmod 644 /etc/cron.d/moodle-database-maintenance
"
```

**What This Does**:
- Analyzes and optimizes database tables
- Repairs corrupted tables
- Updates table statistics
- Runs daily at 3:00 AM (after backups complete)

**Reference**: `templates/cron-examples/moodle-database-maintenance.template`

#### 4.2 Install Security Check Cron

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
echo '# Moodle security check - runs weekly on Sunday at 4 AM
0 4 * * 0 root /bin/bash /opt/moodle-deployment/moodle-security-check.sh >> /var/log/moodle-security.log 2>&1' | sudo tee /etc/cron.d/moodle-security-check > /dev/null

sudo chmod 644 /etc/cron.d/moodle-security-check
"
```

**What This Does**:
- Checks file permissions
- Scans for security updates
- Validates SSL certificate expiration
- Checks failed login attempts
- Runs weekly on Sundays at 4:00 AM

**Reference**: `templates/cron-examples/moodle-security-check.template`

#### 4.3 Verify All Cron Jobs

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
echo '=== Installed Cron Jobs ==='
ls -lh /etc/cron.d/moodle*
echo ''
echo '=== Cron Job Contents ==='
for cron in /etc/cron.d/moodle*; do
  echo \"=== \$cron ===\"
  cat \$cron
  echo ''
done
"
```

**Expected Output**:
```
=== Installed Cron Jobs ===
-rw-r--r-- 1 root root  128 Oct 18 17:15 /etc/cron.d/moodle
-rw-r--r-- 1 root root  156 Oct 18 17:16 /etc/cron.d/moodle-backup
-rw-r--r-- 1 root root  178 Oct 18 17:17 /etc/cron.d/moodle-database-maintenance
-rw-r--r-- 1 root root  142 Oct 18 17:17 /etc/cron.d/moodle-security-check

=== Cron Job Contents ===
=== /etc/cron.d/moodle ===
* * * * * www-data /usr/bin/php /var/www/html/admin/cli/cron.php > /dev/null 2>&1

=== /etc/cron.d/moodle-backup ===
0 2 * * * root /bin/bash /opt/moodle-deployment/backup-vm.sh >> /var/log/moodle-backup.log 2>&1

=== /etc/cron.d/moodle-database-maintenance ===
0 3 * * * root /bin/bash /opt/moodle-deployment/database-maintenance.sh >> /var/log/moodle-maintenance.log 2>&1

=== /etc/cron.d/moodle-security-check ===
0 4 * * 0 root /bin/bash /opt/moodle-deployment/moodle-security-check.sh >> /var/log/moodle-security.log 2>&1
```

---

### ☐ Step 5: Production Validation

**Issue**: Verify all production systems are working correctly

**Goal**: Validate all production readiness requirements

#### 5.1 Verify HTTPS Access

```bash
curl -I https://$DOMAIN
```

**Expected**: `HTTP/1.1 200 OK` with security headers

#### 5.2 Verify SSL Certificate

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
sudo certbot certificates
"
```

**Expected**:
```
Found the following certs:
  Certificate Name: YOUR_DOMAIN
    Domains: YOUR_DOMAIN
    Expiry Date: 2026-01-16 16:20:41+00:00 (VALID: 89 days)
```

#### 5.3 Verify HTTP→HTTPS Redirect

```bash
curl -I http://$DOMAIN
```

**Expected**: `HTTP/1.1 303 See Other` with `Location: https://YOUR_DOMAIN/`

#### 5.4 Verify Storage Persistence

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
df -h | grep -E '(Filesystem|/dev/sdb|/var/moodledata)'
lsblk | grep -E '(NAME|sdb)'
"
```

**Expected**:
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb         49G  537M   47G   2% /var/moodledata

NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sdb      8:16   0   50G  0 disk /var/moodledata
```

#### 5.5 Verify System Resources

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
free -h
uptime
systemctl is-active apache2 mariadb certbot.timer
"
```

**Expected**:
```
              total        used        free      shared  buff/cache   available
Mem:          3.8Gi       1.1Gi       2.7Gi       1.0Mi       307Mi       2.7Gi
 17:30:45 up 15:45,  1 user,  load average: 0.08, 0.02, 0.01

active
active
active
```

#### 5.6 Verify GCS Backups

```bash
gsutil ls gs://$BACKUP_BUCKET/daily/ | head -5
```

**Expected**: Recent backup directories listed

#### 5.7 Verify All Cron Jobs

```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
ls -1 /etc/cron.d/moodle*
"
```

**Expected**:
```
/etc/cron.d/moodle
/etc/cron.d/moodle-backup
/etc/cron.d/moodle-database-maintenance
/etc/cron.d/moodle-security-check
```

#### 5.8 Production Readiness Summary

✅ **Security**:
- HTTPS enabled with valid SSL certificate
- Auto-renewal configured (certbot systemd timer)
- Security headers present (X-Frame-Options, X-XSS-Protection)
- HTTP→HTTPS redirect working

✅ **Data Protection**:
- Persistent storage mounted at `/var/moodledata`
- Automated daily backups to GCS
- 3-2-1 backup rule implemented
- Lifecycle policy for automatic cleanup

✅ **Automation**:
- Moodle cron: Every minute
- Automated backups: Daily at 2:00 AM
- Database maintenance: Daily at 3:00 AM
- Security checks: Weekly Sunday at 4:00 AM

✅ **Performance**:
- System resources healthy
- Database optimized
- Apache/MariaDB active

---

## Troubleshooting

### Issue: DNS Not Resolving

**Symptom**: `nslookup` returns `NXDOMAIN` or wrong IP

**Solution**:
1. Verify DNS A record configuration in registrar console
2. Wait 5-10 minutes for DNS propagation
3. Clear local DNS cache: `ipconfig /flushdns` (Windows) or `sudo systemd-resolve --flush-caches` (Linux)
4. Test with Google DNS: `nslookup YOUR_DOMAIN 8.8.8.8`

### Issue: SSL Certificate Request Fails

**Symptom**: Certbot fails with "DNS problem: NXDOMAIN"

**Root Cause**: DNS not propagated or incorrect A record

**Solution**:
1. Verify DNS resolves correctly: `nslookup YOUR_DOMAIN 8.8.8.8`
2. Wait for DNS to propagate (1-30 minutes depending on TTL)
3. Verify VM's external IP matches DNS A record
4. Try certbot again after DNS propagates

### Issue: Apache Returns 404 After SSL Setup

**Symptom**: Both HTTP and HTTPS return `404 Not Found`

**Root Cause**: DocumentRoot pointing to wrong directory (Moodle 5.1 structure change)

**Solution**:
```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
# Fix both HTTP and HTTPS virtual hosts
sudo sed -i 's|DocumentRoot /var/www/html/moodle/public|DocumentRoot /var/www/html/public|g' /etc/apache2/sites-enabled/*.conf
sudo systemctl restart apache2
"
```

### Issue: "Invalid Login Token" After HTTPS Setup

**Symptom**: Login shows "Invalid Login Token" error

**Root Cause**: `wwwroot` not updated in database

**Solution**:
```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
DB_USER=\$(grep dbuser /var/www/html/config.php | cut -d\"'\" -f2)
DB_PASS=\$(grep dbpass /var/www/html/config.php | cut -d\"'\" -f2)

sudo mysql -u \$DB_USER -p\$DB_PASS moodle_lms << 'EOF'
UPDATE mdl_config SET value='https://YOUR_DOMAIN' WHERE name='wwwroot';
SELECT name, value FROM mdl_config WHERE name='wwwroot';
EOF

# Clear sessions
sudo rm -rf /var/moodledata/sessions/*
sudo systemctl restart apache2
"
```

### Issue: Backup Fails "Access Denied"

**Symptom**: Backup script fails with database access error

**Root Cause**: Database credentials not found

**Solution**:
```bash
gcloud compute ssh $VM_NAME --zone=$ZONE --command="
# Verify credentials file exists
ls -lh /root/.moodle-credentials

# Or configure Secret Manager
sudo bash /opt/moodle-deployment/secrets-manager-setup.sh
"
```

### Issue: GCS Upload Fails

**Symptom**: Backup completes but GCS upload fails

**Root Cause**: Service account lacks Storage Admin permission

**Solution**:
```bash
# Grant Storage Admin to VM's service account
SERVICE_ACCOUNT=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --format='get(serviceAccounts[0].email)')

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/storage.admin"
```

---

## Additional Resources

- **Moodle 5.1 Documentation**: See `TROUBLESHOOTING-LOGIN-ISSUES.md`
- **Password Reset Guide**: See `MOODLE-5.1-PASSWORD-RESET-GUIDE.md`
- **Cron Templates**: See `templates/cron-examples/`
- **Security Compliance**: See `COMPLIANCE-GDPR-FERPA.md`
- **Main Documentation**: See `README.md`

---

## Automation Summary

After completing this production setup, your Moodle deployment will have:

| Task | Frequency | Log File |
|------|-----------|----------|
| Moodle Cron | Every 1 minute | `/var/log/syslog` |
| Automated Backups | Daily at 2:00 AM | `/var/log/moodle-backup.log` |
| Database Maintenance | Daily at 3:00 AM | `/var/log/moodle-maintenance.log` |
| Security Checks | Weekly Sunday 4:00 AM | `/var/log/moodle-security.log` |
| SSL Renewal | Twice daily (automatic) | `/var/log/letsencrypt/letsencrypt.log` |

---

**Last Updated**: 2025-10-18
**Version**: 1.1.0
**Applies To**: Moodle 5.1 STABLE on Ubuntu 22.04 LTS (Google Cloud Platform VM)
