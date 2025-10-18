# Changelog

All notable changes to COR4EDU Moodle LMS deployment configuration will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- API integration with SMS for user provisioning
- Additional plugins (forum, quiz, assignment)
- Email notification templates
- Multi-region deployment support
- Advanced CDN configurations

---

## [1.1.0] - 2025-10-18

### Summary
Production Readiness Edition - Comprehensive post-deployment automation and enterprise-grade operational enhancements for the Moodle VM golden copy template.

### Added

#### Production Setup Documentation
- **PRODUCTION-SETUP.md**:
  - Complete 5-step production readiness guide
  - Step 1: Fix Moodle Cron configuration for Moodle 5.1
  - Step 2: SSL/HTTPS setup with Let's Encrypt
  - Step 3: Google Cloud Storage automated backups (3-2-1 rule)
  - Step 4: Automated maintenance cron jobs
  - Step 5: Production validation checklist
  - Comprehensive troubleshooting section
  - Client-agnostic with placeholder variables

#### Cron Job Templates
- **templates/cron-examples/**:
  - `moodle-cron.template` - Scheduled tasks (every minute)
  - `moodle-backup.template` - Daily backups at 2:00 AM
  - `moodle-database-maintenance.template` - Daily optimization at 3:00 AM
  - `moodle-security-check.template` - Weekly audits Sunday 4:00 AM
  - All templates include installation instructions and documentation

#### Documentation Enhancements
- **README.md**:
  - New "Production Readiness Checklist" section (after Quick Start)
  - 5-step checklist with time estimates
  - Quick overview of each production task
  - Clear explanation of why production setup matters
  - Reference links to PRODUCTION-SETUP.md

- **.env.template**:
  - Enhanced documentation with production requirements
  - Clear section headers for all variable categories
  - IMPORTANT notes for SSL/HTTPS and backup configuration
  - References to PRODUCTION-SETUP.md for context

### Fixed

#### Moodle 5.1 Cron Path Issue
- **Issue**: Moodle cron configured with wrong path (`/var/www/html/moodle/admin/cli/cron.php`)
- **Root Cause**: Moodle 5.1 uses new directory structure without `/moodle/` subdirectory
- **Fix**: Updated cron path to `/var/www/html/admin/cli/cron.php`
- **Impact**: Moodle scheduled tasks now execute correctly every minute

### Production Setup Workflow

This release establishes the complete production workflow:

1. **Deploy VM** using `deploy-production-golden.sh` (30-40 minutes)
2. **Configure Production** using PRODUCTION-SETUP.md guide (35-45 minutes)
   - Fix Moodle cron (5 min)
   - Configure SSL/HTTPS with domain (10-15 min)
   - Setup GCS backups (10 min)
   - Install automated maintenance (5 min)
   - Validate production systems (5 min)
3. **Result**: Fully automated, enterprise-ready Moodle deployment

### Production Automation

**Automated Cron Schedule** (after production setup):
| Task | Frequency | Log File |
|------|-----------|----------|
| Moodle Cron | Every 1 minute | `/var/log/syslog` |
| Automated Backups | Daily at 2:00 AM | `/var/log/moodle-backup.log` |
| Database Maintenance | Daily at 3:00 AM | `/var/log/moodle-maintenance.log` |
| Security Checks | Weekly Sunday 4:00 AM | `/var/log/moodle-security.log` |
| SSL Renewal | Twice daily (systemd) | `/var/log/letsencrypt/letsencrypt.log` |

**Backup Strategy** (3-2-1 Rule):
- 3 copies of data (original + local + cloud)
- 2 storage types (VM disk + Google Cloud Storage)
- 1 offsite location (GCS bucket with lifecycle policies)

**Retention Policies**:
- Daily backups: 7 days local, 90 days GCS
- Weekly backups: 28 days local, 90 days GCS
- Monthly backups: 365 days local and GCS

### Security Enhancements

**SSL/HTTPS Automation**:
- Let's Encrypt SSL certificates with certbot
- Automatic HTTP→HTTPS redirect
- Auto-renewal via systemd timer (twice daily)
- Certificate expiration monitoring in security checks

**File Templates for Deployment**:
- All cron templates include proper permissions (644)
- Templates follow industry standards
- Easy copy-paste installation commands
- Comprehensive inline documentation

### Benefits

**Without Production Setup** (v1.0.0 only):
- ❌ Moodle scheduled tasks never run
- ❌ HTTP-only access (insecure)
- ❌ No automated backups (data loss risk)
- ❌ Manual maintenance required

**With Production Setup** (v1.1.0):
- ✅ Fully automated operations
- ✅ Enterprise-grade security (HTTPS, auto-renewal)
- ✅ Disaster recovery ready (offsite backups)
- ✅ Self-maintaining system (daily optimization, weekly audits)

### Version History Update

| Version | Date | Type | Description |
|---------|------|------|-------------|
| 1.1.0 | 2025-10-18 | Minor | Production readiness automation and documentation |
| 1.0.0 | 2025-10-17 | Major | Initial VM golden copy deployment |

### Contributors
- Carlos Rivera (CarCar47) - Lead Developer
- Claude Code - Development Assistant & Documentation

### Upgrade from 1.0.0 to 1.1.0

**No code changes required** - This is a documentation and template release.

**Steps**:
1. Pull latest from GitHub: `git pull origin main`
2. Review new files:
   - `PRODUCTION-SETUP.md`
   - `templates/cron-examples/*.template`
   - Updated `README.md` (Production Readiness Checklist section)
   - Updated `.env.template`
3. Follow production setup guide for existing deployments
4. Install cron templates on running VMs (see PRODUCTION-SETUP.md)

**Estimated Time**: 35-45 minutes to apply production setup to existing VM

---

## [1.0.0] - 2025-01-13

### Summary
Initial production release of COR4EDU Moodle LMS deployment configuration. Golden template ready for multi-tenant deployment to Google Cloud Platform.

### Moodle Core
- **Version**: Moodle 5.1 STABLE (Build: 20251006)
- **PHP**: 8.2 via official moodlehq/moodle-php-apache base image
- **Database**: MySQL 8.0 via Cloud SQL
- **Storage**: Cloud Storage native volume mount for /moodledata

### Added

#### Cloud Infrastructure
- **Cloud Run Deployment**:
  - Serverless container deployment
  - Auto-scaling (0-5 instances)
  - Min instances: 0 (cold starts enabled for cost savings)
  - Max instances: 5 (scales with demand)
  - Memory: 2Gi
  - CPU: 2 vCPU
  - Timeout: 300 seconds

- **Cloud SQL Integration**:
  - Shared Cloud SQL instance with SMS
  - Separate `moodle_lms` database
  - Unix socket connection for security
  - Automated daily backups (7-day retention)
  - Point-in-time recovery enabled

- **Cloud Storage Volume**:
  - Native volume mount (not FUSE)
  - Persistent /moodledata directory
  - Optimized for performance
  - Automatic failover and redundancy

- **Secret Manager Integration**:
  - Database password securely stored
  - Cron password securely stored
  - API tokens (for future use)

#### Moodle Configuration

**Base Image**:
- Official moodlehq/moodle-php-apache:8.2
- All required PHP extensions pre-compiled:
  - Core: ctype, curl, fileinfo, hash, iconv, json, openssl, pcre, sodium, spl, zlib
  - Database: mysqli, pdo, pdo_mysql
  - XML: dom, simplexml, xml, xmlreader, xmlwriter, soap, xsl
  - Processing: gd, exif, intl, mbstring, zip
  - Performance: opcache, apcu, redis, igbinary, memcached
  - Optional: ldap, bcmath, sockets

**Source Code Deployment**:
- Moodle 5.1 STABLE source code is included in this repository
- Source: Official Moodle repository MOODLE_501_STABLE branch (cloned October 6, 2025)
- Build: 20251006
- Docker build uses `COPY` to include complete Moodle codebase
- This approach ensures consistent deployments and eliminates download failures
- Version locked to Moodle 5.1 STABLE (no automatic upgrades)
- Manual updates required for security patches and new versions

**Directory Structure**:
- Moodle core: `/var/www/html/`
- Web accessible: `/var/www/html/public/` (auto-detected by moodlehq image)
- Data directory: `/moodledata` (mounted from Cloud Storage)
- Configuration: `/var/www/html/config.php` (created by installer)

#### Plugins Pre-Installed

**Attendance Plugin** (`public/mod/attendance/`):
- Session attendance tracking
- Multiple status types (Present, Absent, Late, Excused)
- Attendance reports
- Grade book integration
- Email notifications
- Export to Excel/CSV

#### Health & Monitoring

**Health Check Endpoint** (`/healthcheck.php`):
```json
{
  "status": "healthy",
  "service": "moodle-lms",
  "timestamp": "2025-01-13T12:00:00Z",
  "php_version": "8.2.x"
}
```

**Cloud Run Health Check**:
- Interval: 30 seconds
- Timeout: 10 seconds
- Start period: 60 seconds
- Retries: 3

#### CI/CD Pipeline

**Cloud Build Configuration** (`cloudbuild.yaml`):
1. **Build Step**: Copy Moodle 5.1 STABLE source code from repository
2. **Build Step**: Create Docker image with moodlehq base
3. **Push Step**: Push to Container Registry with build ID tag
4. **Push Step**: Push with 'latest' tag
5. **Deploy Step**: Deploy to Cloud Run with volume mounts
6. **Configure Step**: Set MOODLE_WWWROOT environment variable
7. **Test Step**: Verify health check and main page accessibility

**Build Time**: 8-12 minutes (vs 15-20 min for custom compilation)

**Build Machine**: N1_HIGHCPU_8 (fast builds)

#### Student Provisioning

**Manual Excel Upload** (Recommended):
- Export students from SMS to Excel
- Import to Moodle via Site Administration → Users → Upload users
- Map columns: username, email, firstname, lastname
- Set temporary passwords with force reset

**Integration Tables Ready** (Phase 0 - Future Use):
- `cor4edu_lms_user_mapping` - SMS ↔ Moodle user mapping
- `cor4edu_lms_courses` - Course catalog sync
- `cor4edu_lms_enrollments` - Enrollment sync
- `cor4edu_lms_grades` - Grade sync
- `cor4edu_lms_attendance` - Attendance sync
- `cor4edu_lms_sync_log` - Integration history

#### Documentation

**Comprehensive Documentation Created**:
- `README.md` - Overview and quick start
- `DEPLOYMENT.md` - Complete deployment guide
- `VERSIONING.md` - Version management strategy
- `CHANGELOG.md` - This file
- `Dockerfile` - Well-commented container configuration
- `cloudbuild.yaml` - Annotated CI/CD pipeline

#### Configuration Files

**Docker Configuration**:
- `Dockerfile` - Optimized multi-stage build with version pinning
- `.dockerignore` - Minimal exclusions (Moodle needs most files)
- `.gcloudignore` - Cloud Build optimizations

**Moodle Configuration**:
- `config.php.template` - Configuration template
- Environment variables for database, paths, secrets
- Auto-configuration via installer or Bitnami entrypoint

### Changed
- Moodle source code included directly in repository (COPY approach)
- Build process copies complete Moodle 5.1 STABLE codebase into Docker image
- Eliminates network dependencies and download failures during build

### Fixed
- XML extensions now included via moodlehq base image
- Apache DocumentRoot auto-detection for Moodle 5.1 structure
- Cloud Storage volume mount properly configured
- Healthcheck endpoint returns JSON format

### Security
- HTTPS enforced (Cloud Run default)
- Database passwords in Secret Manager
- Cron password protection
- Unix socket database connection (more secure than TCP)
- No sensitive data in Docker image
- Regular security updates via version pinning

### Infrastructure

**Cost Optimization**:
- **Min instances: 0** - Saves $$ when idle
- **Shared Cloud SQL** - One instance for SMS + LMS
- **Native volume mount** - More efficient than FUSE
- **Version pinning** - Avoid unexpected costs from major upgrades

**Estimated Monthly Costs**:
- Development (idle): ~$0.20
- 10-50 students: ~$2
- 50-100 students: ~$5

**Note**: Cloud SQL shared with SMS ($7.67/month total for both)

**Performance**:
- OPcache enabled
- Moodle caching configured
- Cloud Run auto-scaling
- Cloud Storage CDN-ready

**Reliability**:
- Automated database backups (7-day retention)
- Point-in-time recovery
- Multi-region storage redundancy
- Health checks with automatic restarts
- Zero-downtime deployments

### Dependencies

**Base Image**:
- moodlehq/moodle-php-apache:8.2 (official Moodle HQ image)

**Runtime**:
- PHP 8.2
- Apache 2.4
- MySQL 8.0 (Cloud SQL)

**Build Tools**:
- Git and unzip (Composer installation)
- Composer (PHP dependency management)
- curl (health checks)

### System Requirements

**Production Environment**:
- Google Cloud Run (serverless)
- Cloud SQL MySQL 8.0+
- Cloud Storage bucket
- 2Gi RAM minimum
- 2 vCPU minimum
- HTTPS required

**Browser Compatibility**:
- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Edge (latest)
- Mobile browsers supported

### Known Issues
- Cold starts: 5-10 seconds when scaling from zero (acceptable trade-off for cost savings)
- Large file uploads: Limited by Cloud Run request timeout (300s)
- Moodle mobile app: Requires additional configuration (not covered in v1.0.0)

### Breaking Changes
- None (initial release)

### Deprecations
- None (initial release)

### Migration Notes
- Fresh installations: Use Cloud Build deployment
- Existing Moodle: Export data, deploy clean instance, import data
- No migrations needed (initial release)

### Multi-Tenant Architecture
- Separate Cloud Run service per school (independent scaling)
- Shared Cloud SQL instance (cost savings)
- Separate databases per school
- Independent backups per school
- Golden template deployment (~30 minutes per school)

### Contributors
- Carlos Rivera (CarCar47) - Lead Developer
- Claude Code - Development Assistant

### Acknowledgments
- [Moodle HQ](https://moodle.com/) for official Docker base images
- [Moodle Community](https://moodle.org/) for open-source LMS
- Attendance plugin developers
- Google Cloud Platform for infrastructure

---

## Version History

| Version | Date | Moodle Version | Type | Description |
|---------|------|----------------|------|-------------|
| 1.0.0 | 2025-01-13 | 5.1 STABLE | Major | Initial production release, golden template |

---

## Upgrade Instructions

### From Development to v1.0.0
1. Pull latest code from GitHub
2. Deploy using `cloudbuild.yaml`
3. Complete Moodle installation wizard
4. Configure site settings
5. Verify attendance plugin
6. Test student provisioning

### Moodle Core Updates

**Minor Updates** (5.1.0 → 5.1.1 → 5.1.2):
1. Backup database and /moodledata
2. Pull updated Moodle source from MOODLE_501_STABLE branch
3. Replace local moodle-main/public/ directory with new version
4. Test locally if possible
5. Commit changes to repository
6. Deploy: `gcloud builds submit --config cloudbuild.yaml`
7. Moodle will auto-detect version change and run upgrade wizard

**Major Updates** (5.1 → 5.2):
1. Backup database and /moodledata
2. Clone new Moodle version (e.g., MOODLE_502_STABLE branch)
3. Test extensively in staging environment
4. Replace local moodle-main/public/ directory with new version
5. Update version references in Dockerfile and documentation
6. Commit changes to repository
7. Deploy to production: `gcloud builds submit --config cloudbuild.yaml`
8. Run Moodle upgrade wizard
9. Verify all functionality and plugins compatibility

---

## Support & Feedback

**Issues or Questions:**
- GitHub Issues: [https://github.com/CarCar47/lms-moo/issues](https://github.com/CarCar47/lms-moo/issues)
- Moodle Forums: [https://moodle.org/forums](https://moodle.org/forums)
- Email: support@cor4edu.com

**Related Resources:**
- SMS Repository: [https://github.com/CarCar47/sms-moo](https://github.com/CarCar47/sms-moo)
- Moodle Documentation: [https://docs.moodle.org/](https://docs.moodle.org/)
- Cloud Run Documentation: [https://cloud.google.com/run/docs](https://cloud.google.com/run/docs)

---

**Note**: This is the initial production release. Future versions will follow semantic versioning as documented in VERSIONING.md.

**Version Control**: Configuration v1.0.0 deploys Moodle 5.1 STABLE (Build: 20251006) from MOODLE_501_STABLE branch. Moodle source code is version-controlled in this repository. Updates require manual source replacement and redeployment.
