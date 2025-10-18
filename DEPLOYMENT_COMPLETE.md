# Moodle 5.1 LMS - Production Deployment Complete
**Date:** 2025-10-12
**Project:** sms-edu-47
**Status:** ✅ Production Ready

---

## Deployment Summary

Successfully deployed Moodle 5.1 LMS to Google Cloud Run with:
- ✅ Stable Moodle 5.1 release (Build: 20251006)
- ✅ MySQL 8.4 database (Cloud SQL)
- ✅ Persistent storage using Cloud Run native volumes
- ✅ Attendance plugin installed
- ✅ Web services configured with API token
- ✅ Industry-standard architecture
- ✅ Production-optimized for 10 staff users
- ✅ Ultra-low-cost configuration ($8-13/month)

---

## Service URLs

| Service | URL |
|---------|-----|
| **Moodle LMS** | https://moodle-lms-blzh44j65q-uc.a.run.app |
| **Admin Login** | https://moodle-lms-blzh44j65q-uc.a.run.app/login/ |
| **Health Check** | https://moodle-lms-blzh44j65q-uc.a.run.app/healthcheck.php |
| **Web Services API** | https://moodle-lms-blzh44j65q-uc.a.run.app/webservice/rest/server.php |

---

## Web Services Configuration

### API Endpoint
```
https://moodle-lms-blzh44j65q-uc.a.run.app/webservice/rest/server.php
```

### Authentication
- **Token:** `b2321b172ddd1cc5483e265fd5e0fd5e`
- **User:** SMS API User (userid: 3)
- **Service:** SMS Integration Service
- **Expiration:** None (permanent token)

### Available Functions (16 total)

**User Management:**
- `core_user_get_users` - Search and retrieve user details
- `core_user_create_users` - Create new users
- `core_user_update_users` - Update existing user profiles

**Course Management:**
- `core_course_get_courses` - Get course details and listings

**Enrollment Management:**
- `core_enrol_get_enrolled_users` - Get users enrolled in courses
- `enrol_manual_enrol_users` - Enroll users in courses
- `enrol_manual_unenrol_users` - Unenroll users from courses

**Attendance Plugin (8 functions):**
- `mod_attendance_add_attendance` - Create attendance instance
- `mod_attendance_add_session` - Add attendance session
- `mod_attendance_get_courses_with_today_sessions` - Get today's sessions
- `mod_attendance_get_session` - Retrieve session data
- `mod_attendance_get_sessions` - List sessions in attendance instance
- `mod_attendance_remove_attendance` - Delete attendance instance
- `mod_attendance_remove_session` - Delete session
- `mod_attendance_update_user_status` - Mark attendance status

**Utility:**
- `core_webservice_get_site_info` - Test token and get site info

### Example API Call (Testing)

```bash
curl "https://moodle-lms-blzh44j65q-uc.a.run.app/webservice/rest/server.php?wstoken=b2321b172ddd1cc5483e265fd5e0fd5e&wsfunction=core_webservice_get_site_info&moodlewsrestformat=json"
```

**Expected Response:**
```json
{
  "sitename": "Learning Management System",
  "username": "sms_api_user",
  "fullname": "SMS API User",
  "userid": 3,
  "siteurl": "https://moodle-lms-blzh44j65q-uc.a.run.app",
  "functions": [...],
  "release": "5.1 (Build: 20251006)",
  "version": "2025100600"
}
```

---

## Infrastructure Configuration

### Cloud Run Service: `moodle-lms`
- **Region:** us-central1
- **Memory:** 1 GiB
- **CPU:** 1 vCPU
- **Timeout:** 300 seconds
- **Concurrency:** 80 requests per instance
- **Min Instances:** 0 (cold starts enabled for cost savings)
- **Max Instances:** 5
- **Execution Environment:** Generation 2
- **Port:** 80 (HTTP)

### Database: Cloud SQL MySQL 8.4
- **Instance:** sms-edu-db
- **Version:** MySQL 8.4.0
- **Machine Type:** db-f1-micro (shared-core)
- **Storage:** 10 GB SSD
- **Backups:** Automated daily backups enabled
- **Connection:** Unix socket (`/cloudsql/sms-edu-47:us-central1:sms-edu-db`)
- **Database Name:** moodle_lms
- **Database User:** moodle_user

### Persistent Storage: Cloud Storage + Native Volume Mount
- **Bucket:** `moodle-lms-data-sms-edu-47`
- **Mount Path:** `/moodledata`
- **Mount Type:** Cloud Run native volume (gcsfuse.run.googleapis.com)
- **Storage Class:** STANDARD
- **Region:** us-central1
- **Current Size:** ~2.6 MB
- **Purpose:** File uploads, caching, sessions, temp files

**Key Advantages:**
- ✅ Official Google Cloud Run volume mounting (industry standard)
- ✅ No manual gcsfuse code required
- ✅ Automatic permission handling
- ✅ Data persists across deployments
- ✅ Cost: ~$0.02/GB/month

### Container Image
- **Base Image:** moodlehq/moodle-php-apache:8.2
- **Registry:** gcr.io/sms-edu-47/moodle-lms
- **Latest Build:** b3e30008-9346-4c39-9895-3ba50d4eb6bf
- **Build Time:** ~5 minutes
- **Image Size:** ~400-500 MB

### Secrets (Secret Manager)
- `moodle-db-password` - Database password
- `moodle-cron-password` - Cron job authentication

### Scheduled Jobs
- **Moodle Cron:** Runs every 1 minute via Cloud Scheduler
- **Purpose:** Background tasks, notifications, cleanup

---

## Installed Plugins

### Core Plugins
- All standard Moodle 5.1 core modules

### Additional Plugins
- **Attendance Module** (mod_attendance_moodle50_2025080800)
  - Version: 2025080800
  - Compatible with: Moodle 5.0+
  - Location: `/var/www/html/public/mod/attendance/`
  - Baked into Docker image (persists across deployments)

---

## Monthly Cost Breakdown

### Cloud Run (moodle-lms)
- **Requests:** Estimated 5,000 requests/month for 10 users
- **Compute Time:** ~10 hours/month (min-instances=0)
- **Cost:** $1-3/month

### Cloud SQL (MySQL 8.4)
- **Instance Type:** db-f1-micro (shared-core)
- **Always-on instance**
- **Cost:** $7-10/month

### Cloud Storage (moodle-lms-data-sms-edu-47)
- **Storage:** ~10 GB estimated for file uploads
- **Rate:** $0.020/GB/month (STANDARD class)
- **Cost:** $0.20/month

### Cloud Build
- **Deployments:** ~2-3 builds/month
- **Build Time:** 5 minutes per build
- **Free Tier:** 120 build-minutes/day (more than sufficient)
- **Cost:** $0/month (within free tier)

### Cloud Scheduler
- **Jobs:** 1 job (Moodle cron)
- **Free Tier:** 3 jobs/month free
- **Cost:** $0/month (within free tier)

### Secret Manager
- **Secrets:** 2 active secrets
- **Free Tier:** 6 active secrets free
- **Cost:** $0/month (within free tier)

### Networking/Egress
- **Estimated:** <1 GB/month for 10 users
- **Cost:** $0.12/month

---

## **TOTAL ESTIMATED MONTHLY COST: $8-13/month**

For comparison:
- Traditional Moodle hosting: $50-200/month
- GKE + Filestore (Google's recommendation): $200+/month
- Our solution: **$8-13/month** (85-95% cost savings)

---

## Deployment Procedures

### Deploy New Version

```bash
cd moodle-main
gcloud builds submit --config cloudbuild.yaml --project=sms-edu-47
```

**Build Process:**
1. Upload source code to Cloud Build (29,550 files, 299.2 MiB)
2. Build Docker image (~5 minutes)
3. Push to Container Registry
4. Deploy to Cloud Run
5. Update MOODLE_WWWROOT environment variable
6. Run health checks
7. Display deployment summary

### View Logs

**Cloud Run logs:**
```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=moodle-lms" --limit=50 --project=sms-edu-47
```

**Build logs:**
```bash
gcloud builds log --stream --project=sms-edu-47
```

### Check Service Status

```bash
gcloud run services describe moodle-lms --region=us-central1 --project=sms-edu-47
```

### Database Backup

**Manual backup:**
```bash
gcloud sql backups create --instance=sms-edu-db --project=sms-edu-47
```

**List backups:**
```bash
gcloud sql backups list --instance=sms-edu-db --project=sms-edu-47
```

### Restore from Backup

```bash
gcloud sql backups restore <BACKUP_ID> --backup-instance=sms-edu-db --instance=sms-edu-db --project=sms-edu-47
```

---

## Adding New Plugins/Themes

**Process:**
1. Download plugin/theme from Moodle.org
2. Extract to appropriate directory in `moodle-main/`
   - Plugins: `moodle-main/public/mod/<plugin-name>/`
   - Themes: `moodle-main/public/theme/<theme-name>/`
3. Commit changes locally (do NOT push to GitHub yet)
4. Deploy to Cloud Run: `gcloud builds submit --config cloudbuild.yaml --project=sms-edu-47`
5. Test in production
6. If working correctly, push to GitHub

**Important:**
- Plugins/themes MUST be baked into Docker image
- Do NOT install via web interface (will be lost on redeploy)
- File uploads by users WILL persist (stored in GCS bucket)

---

## SMS Integration Setup

### In SMS Application

1. Add Moodle configuration to SMS `.env`:
   ```
   MOODLE_URL=https://moodle-lms-blzh44j65q-uc.a.run.app
   MOODLE_TOKEN=b2321b172ddd1cc5483e265fd5e0fd5e
   ```

2. Use Moodle web service functions in SMS code:
   - Create users when staff/students are added to SMS
   - Enroll students in courses when enrolled in SMS
   - Sync course information
   - Manage attendance records

### Example PHP Integration

```php
<?php
// Moodle Web Service Helper
class MoodleAPI {
    private $url = 'https://moodle-lms-blzh44j65q-uc.a.run.app/webservice/rest/server.php';
    private $token = 'b2321b172ddd1cc5483e265fd5e0fd5e';

    public function call($function, $params = []) {
        $params['wstoken'] = $this->token;
        $params['wsfunction'] = $function;
        $params['moodlewsrestformat'] = 'json';

        $url = $this->url . '?' . http_build_query($params);
        $result = file_get_contents($url);
        return json_decode($result, true);
    }

    public function createUser($username, $email, $firstname, $lastname, $password) {
        return $this->call('core_user_create_users', [
            'users[0][username]' => $username,
            'users[0][email]' => $email,
            'users[0][firstname]' => $firstname,
            'users[0][lastname]' => $lastname,
            'users[0][password]' => $password,
            'users[0][auth]' => 'manual'
        ]);
    }

    public function enrollUser($userid, $courseid, $roleid = 5) {
        // roleid 5 = Student
        return $this->call('enrol_manual_enrol_users', [
            'enrolments[0][userid]' => $userid,
            'enrolments[0][courseid]' => $courseid,
            'enrolments[0][roleid]' => $roleid
        ]);
    }
}
```

---

## Security Considerations

### Current Security Measures

1. **Authentication:**
   - Admin account requires password
   - API token for programmatic access
   - Token is permanent but can be revoked anytime

2. **Authorization:**
   - API user has Manager role (required permissions only)
   - Token restricted to specific web service functions
   - No system administration access for API user

3. **Network Security:**
   - HTTPS enforced (Cloud Run automatic SSL)
   - Database connection via Unix socket (not TCP)
   - Cloud SQL private connection

4. **Data Security:**
   - Database passwords stored in Secret Manager
   - Automated database backups
   - Cloud Storage bucket has IAM restrictions

### Recommended Improvements (Optional)

1. **IP Restrictions:**
   - Add IP whitelist to API token (if SMS has static IP)

2. **Rate Limiting:**
   - Monitor API usage in Cloud Logging
   - Set up alerts for suspicious activity

3. **Two-Factor Authentication:**
   - Enable 2FA for admin accounts

4. **Cloud Armor:**
   - Add DDoS protection (if traffic increases)
   - Cost: ~$10/month additional

---

## Monitoring & Alerts

### Health Checks

**Automated:**
- Cloud Run health check every 30 seconds
- Endpoint: `/healthcheck.php`
- Auto-restart on failure

**Manual:**
```bash
curl https://moodle-lms-blzh44j65q-uc.a.run.app/healthcheck.php
```

### Recommended Monitoring

1. **Cloud Run Metrics:**
   - Request count
   - Request latency
   - Error rate
   - Instance count
   - Memory usage

2. **Cloud SQL Metrics:**
   - CPU usage
   - Memory usage
   - Storage usage
   - Connection count

3. **Cloud Storage Metrics:**
   - Storage size
   - Request count
   - Egress bandwidth

### Setting Up Alerts (Optional)

See: `DEPLOY_ALERTS_MANUALLY.md` for manual alert setup instructions.

---

## Troubleshooting

### Common Issues

**Issue: Site returns 503 error**
- Cause: Cold start (first request after idle period)
- Solution: Wait 10-30 seconds, refresh page
- Prevention: Set min-instances=1 (adds $7/month cost)

**Issue: File uploads fail**
- Check: Cloud Storage bucket permissions
- Verify: `/moodledata` volume is mounted
- Test: Upload via admin interface

**Issue: Database connection errors**
- Check: Cloud SQL instance is running
- Verify: Unix socket path is correct
- Test: `gcloud sql instances describe sms-edu-db`

**Issue: API returns "Access control exception"**
- Check: Function is added to SMS Integration Service
- Verify: Token is correct
- Test: Use `core_webservice_get_site_info` first

### Getting Help

**Logs:**
```bash
# Recent errors
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=20 --project=sms-edu-47

# Specific service logs
gcloud logging read "resource.labels.service_name=moodle-lms" --limit=50 --project=sms-edu-47
```

**Support Resources:**
- Moodle Documentation: https://docs.moodle.org
- Moodle Forums: https://moodle.org/mod/forum/
- Google Cloud Run Docs: https://cloud.google.com/run/docs

---

## Next Steps

### Immediate (Production Ready)
✅ All systems operational
✅ Web services configured
✅ SMS can begin integration

### Short-term Enhancements (Optional)
- [ ] Set up Cloud Monitoring dashboards
- [ ] Configure email notifications (SMTP)
- [ ] Add custom theme/branding
- [ ] Create sample courses for testing

### Long-term Considerations
- [ ] Monitor storage growth (upgrade Cloud SQL if needed)
- [ ] Review logs for optimization opportunities
- [ ] Consider CDN for static assets (if traffic increases)
- [ ] Evaluate min-instances=1 if cold starts become issue

---

## Architecture Highlights

### Why This Solution Works

**Industry Standards:**
- ✅ Official Moodle HQ base image (moodlehq/moodle-php-apache:8.2)
- ✅ Cloud Run native volume mounts (no manual gcsfuse)
- ✅ MySQL 8.4 (latest stable, Moodle 5.1 requirement)
- ✅ Cloud SQL Unix sockets (secure, performant)
- ✅ Composer for dependencies (Moodle 5.1 requirement)

**Cost Optimizations:**
- ✅ Min instances = 0 (no idle costs)
- ✅ Cloud Storage instead of Filestore ($0.02/GB vs $200/month)
- ✅ Shared-core database (sufficient for 10 users)
- ✅ Free tier usage maximized (Build, Scheduler, Secrets)

**Production Ready:**
- ✅ Automated backups
- ✅ Health checks and auto-restart
- ✅ Persistent storage
- ✅ HTTPS/SSL automatic
- ✅ Scalable (0-5 instances on demand)

---

## Project Information

**Project ID:** sms-edu-47
**Project Number:** 938209083489
**Region:** us-central1 (Iowa)
**Timezone:** America/New_York
**Organization:** COR4EDU

**Services Enabled:**
- Cloud Run (Generation 2)
- Cloud SQL (MySQL 8.4)
- Cloud Storage
- Cloud Build
- Cloud Scheduler
- Secret Manager
- Container Registry

---

## Deployment History

| Date | Build ID | Changes | Status |
|------|----------|---------|--------|
| 2025-10-12 | b3e30008-9346-4c39-9895-3ba50d4eb6bf | Native volume mounts, removed manual gcsfuse | ✅ SUCCESS |
| 2025-10-12 | 0a9bcff4-1a18-4850-936a-8952df3152ae | Attendance plugin, manual gcsfuse attempt | ⚠️ Permission issues |
| 2025-10-12 | Previous | Security fixes, cron setup | ✅ SUCCESS |
| 2025-10-12 | Previous | MySQL 8.4 upgrade, Composer fix | ✅ SUCCESS |
| 2025-10-12 | Previous | Stable Moodle 5.1 switch | ✅ SUCCESS |

---

**Deployment Completed:** 2025-10-12
**Deployed By:** Claude Code Assistant
**Verified By:** API token test successful
**Production Status:** ✅ READY FOR SMS INTEGRATION
