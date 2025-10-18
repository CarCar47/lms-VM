# Moodle LMS - Deployment Guide

Complete guide for deploying Moodle 5.1 LMS to Google Cloud Run alongside COR4EDU SMS.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [Installation Wizard](#installation-wizard)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Student Provisioning](#student-provisioning)
- [Troubleshooting](#troubleshooting)
- [Monitoring & Maintenance](#monitoring--maintenance)

---

## Overview

Moodle LMS is deployed as a separate Cloud Run service sharing the same Cloud SQL instance as the SMS.

**Architecture:**
```
┌────────────────────────────────────────────────────────┐
│         Google Cloud Project (per school)               │
├────────────────────────────────────────────────────────┤
│                                                          │
│  ┌─────────────────┐         ┌──────────────────────┐ │
│  │   Cloud Run     │────────>│     Cloud SQL        │ │
│  │   (sms-edu)     │  Socket │   (sms-edu-db)       │ │
│  │   SMS           │         │                      │ │
│  └─────────────────┘         │  - cor4edu_sms       │ │
│                               │  - moodle_lms        │ │
│  ┌─────────────────┐         │                      │ │
│  │   Cloud Run     │────────>│                      │ │
│  │   (moodle-lms)  │  Socket │                      │ │
│  │   LMS           │         └──────────────────────┘ │
│  └─────────────────┘                                   │
│         ↓                                               │
│  ┌─────────────────┐                                   │
│  │ Cloud Storage   │                                   │
│  │ /moodledata     │                                   │
│  └─────────────────┘                                   │
└────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Required Infrastructure
1. **SMS Deployed**: COR4EDU SMS must be deployed first
2. **Cloud SQL Instance**: `sms-edu-db` running and accessible
3. **Google Cloud Project**: Same project as SMS deployment

### Required Tools
```bash
# Verify gcloud CLI
gcloud version

# Verify project access
gcloud config get-value project

# Verify SMS is deployed
gcloud run services list --project=YOUR-PROJECT-ID
```

### Credentials Needed
- Google Cloud project ID
- School name
- Admin email for Moodle

---

## Deployment Steps

### Step 1: Verify SMS Deployment

```bash
# Set project
export PROJECT_ID="your-school-sms"
gcloud config set project $PROJECT_ID

# Verify SMS service exists
gcloud run services describe sms-edu \
  --region=us-central1 \
  --project=$PROJECT_ID

# Verify Cloud SQL instance
gcloud sql instances describe sms-edu-db \
  --project=$PROJECT_ID
```

### Step 2: Create Moodle Database

```bash
# Create moodle_lms database
gcloud sql databases create moodle_lms \
  --instance=sms-edu-db \
  --charset=utf8mb4 \
  --collation=utf8mb4_unicode_ci \
  --project=$PROJECT_ID

# Verify database created
gcloud sql databases list \
  --instance=sms-edu-db \
  --project=$PROJECT_ID
```

### Step 3: Create Database User

```bash
# Generate secure password
MOODLE_DB_PASSWORD=$(openssl rand -base64 24)

# Create moodle_user
gcloud sql users create moodle_user \
  --instance=sms-edu-db \
  --password="$MOODLE_DB_PASSWORD" \
  --project=$PROJECT_ID

# Store password in Secret Manager
echo -n "$MOODLE_DB_PASSWORD" | gcloud secrets create moodle-db-password \
  --data-file=- \
  --replication-policy=automatic \
  --project=$PROJECT_ID

# Grant access to Cloud Run service account
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID \
  --format='value(projectNumber)')

gcloud secrets add-iam-policy-binding moodle-db-password \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=$PROJECT_ID
```

### Step 4: Create Cloud Storage Bucket

```bash
# Create bucket for /moodledata
gsutil mb -p $PROJECT_ID -c STANDARD -l us-central1 \
  gs://moodle-lms-data-${PROJECT_ID}

# Verify bucket created
gsutil ls -p $PROJECT_ID | grep moodle
```

### Step 5: Create Cron Password Secret

```bash
# Generate cron password
CRON_PASSWORD=$(openssl rand -base64 32)

# Store in Secret Manager
echo -n "$CRON_PASSWORD" | gcloud secrets create moodle-cron-password \
  --data-file=- \
  --replication-policy=automatic \
  --project=$PROJECT_ID

# Grant access
gcloud secrets add-iam-policy-binding moodle-cron-password \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project=$PROJECT_ID
```

### Step 6: Deploy Moodle to Cloud Run

```bash
# Navigate to moodle-main directory
cd moodle-main

# Deploy using Cloud Build
gcloud builds submit \
  --config cloudbuild.yaml \
  --project=$PROJECT_ID

# Wait for deployment (8-12 minutes)
# Cloud Build will:
# 1. Copy Moodle 5.1 STABLE source code from repository
# 2. Build Docker image with moodlehq base
# 3. Push to Container Registry
# 4. Deploy to Cloud Run with volume mounts
# 5. Configure environment variables
# 6. Test health check endpoint
```

### Step 7: Get Service URL

```bash
# Retrieve Moodle URL
MOODLE_URL=$(gcloud run services describe moodle-lms \
  --region=us-central1 \
  --format='value(status.url)' \
  --project=$PROJECT_ID)

echo "Moodle URL: $MOODLE_URL"
echo "Installation: $MOODLE_URL/install.php"
```

---

## Installation Wizard

### Step 1: Access Installation Wizard

Navigate to: `https://moodle-lms-[hash].run.app/install.php`

**Note**: If auto-install is enabled (Bitnami), wait 2-3 minutes for automatic setup.

### Step 2: Choose Language

- Select preferred language
- Click "Next"

### Step 3: Confirm Paths

Pre-configured paths (should auto-detect):
- **Web address**: `https://moodle-lms-[hash].run.app`
- **Moodle directory**: `/var/www/html`
- **Data directory**: `/moodledata`

Click "Next"

### Step 4: Database Configuration

Pre-configured via environment variables:
- **Database driver**: `mysqli` (MySQL Native)
- **Database host**: `/cloudsql/PROJECT:REGION:INSTANCE` (Unix socket)
- **Database name**: `moodle_lms`
- **Database user**: `moodle_user`
- **Database password**: (from Secret Manager)
- **Tables prefix**: `mdl_`

Click "Next"

### Step 5: License Agreement

- Read GPL v3 license
- Click "Continue"

### Step 6: Server Checks

Moodle verifies all requirements:
- ✅ PHP 8.2
- ✅ All required extensions (from moodlehq base image)
- ✅ Database connection
- ✅ File permissions

**All checks should pass** - Click "Continue"

### Step 7: Database Installation

Moodle creates ~500 tables (takes 5-10 minutes):
- Core tables
- Module tables
- Activity tables
- Block tables
- Enrollment tables

Wait for completion - **Do not close browser**

### Step 8: Create Admin Account

**Important credentials:**
- **Username**: `admin` (recommended)
- **Password**: Minimum 16 characters (strong password required)
- **Email**: Admin email address
- **First name**: Administrator first name
- **Last name**: Administrator last name

**Save these credentials securely!**

### Step 9: Site Settings

Configure school information:
- **Full site name**: "School Name LMS"
- **Short name**: "School"
- **Front page summary**: Description of your LMS
- **Time zone**: Select appropriate timezone
- **Country**: Select country
- **Language**: Default language

Click "Save changes"

### Step 10: Installation Complete

You'll see: "✅ Installation complete!"

Click "Continue" to access Moodle dashboard.

---

## Post-Deployment Configuration

### Step 1: Configure Web Services (Optional)

For future SMS integration:

1. **Enable web services**:
   - Site Administration → Advanced features
   - Check "Enable web services"
   - Save changes

2. **Enable REST protocol**:
   - Site Administration → Plugins → Web services → Manage protocols
   - Enable "REST protocol"

3. **Create SMS Integration service**:
   - Site Administration → Server → Web services → External services
   - Add new service: "SMS Integration API"
   - Enable required functions (future use)

4. **Create API user**:
   - Create user: `sms_api_user`
   - Assign system role: Web service user
   - Generate token

5. **Store token**:
   ```bash
   echo -n "TOKEN" | gcloud secrets create moodle-api-token \
     --data-file=- \
     --replication-policy=automatic \
     --project=$PROJECT_ID
   ```

### Step 2: Verify Attendance Plugin

1. Navigate to: Site Administration → Plugins → Activity modules
2. Confirm "Attendance" plugin is installed and enabled
3. Test by creating a course and adding attendance activity

### Step 3: Configure Email (Optional)

For notifications:

1. Site Administration → Server → Email → Outgoing mail configuration
2. Configure SMTP settings or use default PHP mail
3. Test email: Site Administration → Server → Email → Test outgoing mail

### Step 4: Set Up Cron (Automated)

Cloud Run scheduler automatically triggers Moodle cron:
- Frequency: Every 5 minutes
- Uses cron password from Secret Manager
- Handles background tasks (emails, cleanup, etc.)

Verify cron:
```bash
# Check scheduler job
gcloud scheduler jobs describe moodle-cron \
  --location=us-central1 \
  --project=$PROJECT_ID

# Manual trigger (testing)
gcloud scheduler jobs run moodle-cron \
  --location=us-central1 \
  --project=$PROJECT_ID
```

### Step 5: Security Hardening

**Recommended settings:**

1. **Force HTTPS** (already enforced by Cloud Run)

2. **Password policy**:
   - Site Administration → Security → Site security settings
   - Minimum length: 12 characters
   - Require: digits, lowercase, uppercase, special chars

3. **Session timeout**:
   - Site Administration → Security → Session handling
   - Timeout: 30 minutes

4. **Two-factor authentication** (optional):
   - Install 2FA plugin
   - Enable for admin accounts

---

## Student Provisioning

### Method 1: Manual Excel Upload (Recommended)

**Export from SMS:**

1. Access SMS → Students → Export
2. Download Excel with columns:
   - username
   - email
   - firstname
   - lastname
   - cohort (optional)

**Import to Moodle:**

1. Site Administration → Users → Upload users
2. Select CSV/Excel file
3. Map columns:
   - Username → username
   - Email → email
   - First name → firstname
   - Last name → lastname
4. Choose: "Create new users only"
5. Upload and create accounts
6. **Default password**: Set temporary password, force reset on first login

**Benefits:**
- Simple and reliable
- School controls timing
- No API needed
- Handles 10-500 students easily

### Method 2: Future API Integration

Tables ready for future automation:
- `cor4edu_lms_user_mapping` (SMS ↔ Moodle user mapping)
- `cor4edu_lms_courses` (Course catalog sync)
- `cor4edu_lms_enrollments` (Enrollment sync)
- `cor4edu_lms_grades` (Grade sync)
- `cor4edu_lms_attendance` (Attendance sync)

---

## Troubleshooting

### Installation Wizard Not Appearing

**Symptoms**: Blank page or 404 at `/install.php`

**Diagnosis:**
```bash
# Check if Moodle installed correctly
gcloud run services logs read moodle-lms \
  --region=us-central1 \
  --limit=50 \
  --project=$PROJECT_ID

# Verify health check
curl https://moodle-lms-[hash].run.app/healthcheck.php
```

**Solutions:**
1. Wait 2-3 minutes for Bitnami auto-install
2. Check database connection
3. Verify volume mount for /moodledata

### Database Connection Errors

**Symptoms**: "Cannot connect to database"

**Diagnosis:**
```bash
# Verify database exists
gcloud sql databases describe moodle_lms \
  --instance=sms-edu-db \
  --project=$PROJECT_ID

# Test connection from Cloud Run
gcloud run services describe moodle-lms \
  --region=us-central1 \
  --format='yaml(spec.template.spec.containers[0].env)'
```

**Solutions:**
1. Verify `--add-cloudsql-instances` in deployment
2. Check database credentials in Secret Manager
3. Ensure database user has proper privileges

### Files Not Persisting

**Symptoms**: Uploads disappear after restart

**Diagnosis:**
```bash
# Verify Cloud Storage bucket
gsutil ls gs://moodle-lms-data-${PROJECT_ID}/

# Check volume mount
gcloud run services describe moodle-lms \
  --region=us-central1 \
  --format='yaml(spec.template.spec.volumes)'
```

**Solutions:**
1. Verify volume mount: `--add-volume-mount=volume=moodledata,mount-path=/moodledata`
2. Check bucket permissions
3. Test file write: Create test file in Moodle

### Slow Performance

**Symptoms**: Pages load slowly, timeouts

**Diagnosis:**
```bash
# Check current resources
gcloud run services describe moodle-lms \
  --region=us-central1 \
  --format='yaml(spec.template.spec.containers[0].resources)'

# View metrics
gcloud run services describe moodle-lms \
  --region=us-central1
```

**Solutions:**
```bash
# Increase resources
gcloud run services update moodle-lms \
  --region=us-central1 \
  --memory=2Gi \
  --cpu=2 \
  --max-instances=10 \
  --project=$PROJECT_ID

# Increase min instances (avoid cold starts)
gcloud run services update moodle-lms \
  --region=us-central1 \
  --min-instances=1 \
  --project=$PROJECT_ID
```

---

## Monitoring & Maintenance

### Health Checks

```bash
# Automated health check (Cloud Run)
curl https://moodle-lms-[hash].run.app/healthcheck.php

# Expected response:
{
  "status": "healthy",
  "service": "moodle-lms",
  "timestamp": "2025-01-13T12:00:00Z",
  "php_version": "8.2.x"
}
```

### View Logs

```bash
# Real-time logs
gcloud run services logs tail moodle-lms \
  --region=us-central1 \
  --project=$PROJECT_ID

# Recent errors only
gcloud run services logs read moodle-lms \
  --region=us-central1 \
  --filter="severity>=ERROR" \
  --limit=50 \
  --project=$PROJECT_ID
```

### Database Backups

```bash
# List backups (shared with SMS)
gcloud sql backups list \
  --instance=sms-edu-db \
  --project=$PROJECT_ID

# Create on-demand backup
gcloud sql backups create \
  --instance=sms-edu-db \
  --project=$PROJECT_ID

# Restore specific database
gcloud sql export sql sms-edu-db \
  gs://backup-bucket/moodle_lms_backup.sql \
  --database=moodle_lms \
  --project=$PROJECT_ID
```

### Update Deployment

```bash
# Pull latest changes (if any)
cd moodle-main
git pull origin main

# Redeploy
gcloud builds submit --config cloudbuild.yaml --project=$PROJECT_ID

# Verify deployment
gcloud run services describe moodle-lms --region=us-central1
```

### Moodle Updates

**Minor updates (5.1.0 → 5.1.1 → 5.1.2)**: Manual source code update
```bash
# 1. Backup database
gcloud sql backups create --instance=sms-edu-db

# 2. Pull updated Moodle source
cd /tmp
git clone --branch MOODLE_501_STABLE --depth 1 https://github.com/moodle/moodle.git

# 3. Replace local source
rm -rf moodle-main/public/*
cp -r /tmp/moodle/* moodle-main/public/

# 4. Commit and redeploy
git add moodle-main/public/
git commit -m "Update Moodle to 5.1.x security patch"
gcloud builds submit --config cloudbuild.yaml
```

**Major updates (5.1 → 5.2)**: Manual upgrade required
1. Backup database first
2. Clone Moodle 5.2 STABLE branch
3. Replace local `moodle-main/public/` directory
4. Update version references in Dockerfile and documentation
5. Test in staging environment
6. Deploy to production
7. Run Moodle upgrade wizard

---

## Cost Monitoring

### Current Configuration
- Min instances: 0 (saves $$ when idle)
- Max instances: 5
- Memory: 2Gi
- CPU: 2 vCPU

### Estimated Costs
- Idle: ~$0.20/month
- 10-50 students: ~$2/month
- 50-100 students: ~$5/month

### View Costs
```bash
# Project billing
gcloud billing accounts list

# Usage reports (via console)
# https://console.cloud.google.com/billing
```

---

## Additional Resources

- [Moodle Documentation](https://docs.moodle.org/)
- [Moodle Forums](https://moodle.org/forums)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [SMS Repository](https://github.com/CarCar47/sms-moo)

---

## Support

**Issues or Questions:**
1. Check troubleshooting section
2. Review Moodle logs
3. Consult official Moodle documentation
4. Open GitHub issue with details
5. Email: support@cor4edu.com

---

**Version**: 1.0.0
**Last Updated**: 2025-01-13
**Status**: Production Ready
