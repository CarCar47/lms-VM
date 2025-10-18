# Moodle LMS - Versioning Strategy

This document outlines the versioning strategy for COR4EDU Moodle LMS deployment configuration.

## Two-Tier Versioning

This repository uses a two-tier versioning system:

1. **Moodle Core Version**: Official Moodle version (e.g., 5.1.2)
2. **Configuration Version**: COR4EDU deployment config version (e.g., 1.0.0)

```
Configuration v1.2.3 → Moodle 5.1.2
Configuration v2.0.0 → Moodle 5.2.0
```

---

## Moodle Core Versioning

### Source Code Version Control Strategy

We include the **complete Moodle source code** in this repository:

```
moodle-main/public/  ← Contains full Moodle 5.1 STABLE codebase
Build: 20251006
Source: MOODLE_501_STABLE branch
```

**What this means:**
- **5.1.0 → 5.1.1 → 5.1.2**: Manual update (pull updated source, commit, redeploy)
- **5.1.x → 5.2.0**: Manual upgrade required (major features, breaking changes)

### Moodle Version Components

Moodle uses semantic versioning: **MAJOR.MINOR.PATCH**

Example: **5.1.2**

- **MAJOR (5)**: Major release with new features
- **MINOR (1)**: Feature release within major version
- **PATCH (2)**: Bug fixes and security patches

### Moodle Release Schedule

Moodle releases new versions twice per year:

| Version | Release Date | Support Until | LTS |
|---------|--------------|---------------|-----|
| 5.2 | May 2025 | May 2026 | No |
| 5.1 | November 2024 | November 2025 | No |
| 5.0 | May 2024 | May 2025 | No |
| 4.4 | April 2024 | April 2028 | Yes |
| 4.1 | November 2022 | November 2026 | Yes |

**LTS (Long-Term Support)**: Every third major version

### Manual Updates

All Moodle updates require manual source code replacement:
- ✅ Security patches (5.1.0 → 5.1.1) - Manual source update required
- ✅ Bug fixes (5.1.1 → 5.1.2) - Manual source update required
- ✅ Feature releases (5.1 → 5.2) - Manual upgrade required

---

## Configuration Versioning

### Semantic Versioning

COR4EDU deployment configuration follows [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH

Example: 1.2.3
```

### Version Components

- **MAJOR** (1.x.x): Breaking changes
  - Moodle major version upgrade (5.1 → 5.2)
  - Significant configuration changes
  - Incompatible with previous deployments

- **MINOR** (x.1.x): New features (backward compatible)
  - New deployment scripts
  - Enhanced monitoring
  - Additional plugins
  - Cloud infrastructure improvements

- **PATCH** (x.x.1): Bug fixes and patches
  - Dockerfile optimizations
  - Documentation updates
  - Configuration tweaks
  - Security patches to deployment

### Version Examples

```
v1.0.0 - Initial release (Moodle 5.1.0)
v1.0.1 - Dockerfile optimization (Moodle 5.1.0)
v1.1.0 - Add monitoring dashboard (Moodle 5.1.1)
v1.1.1 - Fix volume mount issue (Moodle 5.1.1)
v2.0.0 - Upgrade to Moodle 5.2 (Moodle 5.2.0)
```

---

## Upgrade Procedures

### Minor Updates (5.1.x → 5.1.y)

**Manual source code update** required:

```bash
# 1. Backup database
gcloud sql backups create --instance=sms-edu-db --project=PROJECT_ID

# 2. Pull updated Moodle source
cd /tmp
git clone --branch MOODLE_501_STABLE --depth 1 https://github.com/moodle/moodle.git

# 3. Replace local source
rm -rf moodle-main/public/*
cp -r /tmp/moodle/* moodle-main/public/

# 4. Commit and redeploy
git add moodle-main/public/
git commit -m "Update Moodle to 5.1.x security patch"
gcloud builds submit --config cloudbuild.yaml --project=PROJECT_ID
```

**What happens:**
1. Updated Moodle source copied into Docker image
2. Cloud Build creates new image
3. Cloud Run deploys new version
4. Moodle auto-detects version change
5. Database schema updated automatically (if needed)

**Downtime**: ~30 seconds (during deployment)

**Rollback**: Redeploy previous Cloud Run revision or restore from git

### Major Updates (5.1 → 5.2)

**Manual upgrade required** - significant changes:

#### Step 1: Backup Everything

```bash
# Backup database
gcloud sql export sql sms-edu-db \
  gs://backups/moodle_lms_backup_$(date +%Y%m%d).sql \
  --database=moodle_lms \
  --project=PROJECT_ID

# Backup moodledata
gsutil -m rsync -r \
  gs://moodle-lms-data-PROJECT/ \
  gs://backups/moodledata_$(date +%Y%m%d)/
```

#### Step 2: Test in Staging

```bash
# Create staging environment
# Deploy Moodle 5.2 to staging project
# Test all functionality
# Verify plugins compatibility
# Test attendance plugin
```

#### Step 3: Update Configuration

```bash
# Clone Moodle 5.2 STABLE source
cd /tmp
git clone --branch MOODLE_502_STABLE --depth 1 https://github.com/moodle/moodle.git

# Replace local source
rm -rf moodle-main/public/*
cp -r /tmp/moodle/* moodle-main/public/

# Update version references in documentation
# - Dockerfile labels
# - README.md
# - CHANGELOG.md
# - VERSIONING.md (this file)

# Commit changes
git add moodle-main/public/ Dockerfile README.md CHANGELOG.md VERSIONING.md
git commit -m "Upgrade to Moodle 5.2 STABLE"
git tag -a v2.0.0 -m "Major upgrade: Moodle 5.2"
```

#### Step 4: Deploy to Production

```bash
# Deploy
gcloud builds submit --config cloudbuild.yaml --project=PROJECT_ID

# Monitor deployment
gcloud run services logs tail moodle-lms --region=us-central1
```

#### Step 5: Run Moodle Upgrade

1. Access: `https://moodle-lms-[hash].run.app/admin`
2. Moodle detects version change
3. Click "Upgrade Moodle database now"
4. Review upgrade notes
5. Confirm upgrade
6. Wait for completion (5-10 minutes)
7. Test all functionality

#### Step 6: Verify and Test

- ✅ Admin dashboard loads
- ✅ Courses accessible
- ✅ Attendance plugin works
- ✅ Student enrollment works
- ✅ File uploads work
- ✅ Mobile app compatibility (if used)

---

## Git Branching Strategy

```
main (production - Moodle 5.1)
├── develop (integration)
├── feature/monitoring-dashboard
├── bugfix/volume-mount-fix
└── upgrade/moodle-5.2
```

### Branch Types

**main**
- Production-ready configuration
- Tagged with version numbers
- Protected branch (no direct commits)

**develop**
- Integration branch for features
- Tested before merging to main

**feature/\***
- New deployment features
- Configuration enhancements
- Example: `feature/backup-automation`

**bugfix/\***
- Configuration fixes
- Deployment issue fixes
- Example: `bugfix/cloudsql-connection`

**upgrade/\***
- Moodle version upgrades
- Major configuration changes
- Example: `upgrade/moodle-5.2`

---

## Version Tagging

### Tag Format

```bash
v1.2.3          # Configuration version
v1.2.3-moodle-5.1.2  # Includes Moodle version (optional)
```

### Creating Tags

```bash
# Tag configuration version
git tag -a v1.2.3 -m "Release v1.2.3: Add monitoring dashboard (Moodle 5.1.2)"

# Push tag
git push origin v1.2.3

# List tags
git tag -l

# Show tag details
git show v1.2.3
```

---

## Docker Image Versioning

### Image Tags

Each build creates multiple image tags:

```
gcr.io/PROJECT/moodle-lms:BUILD_ID       # Unique build
gcr.io/PROJECT/moodle-lms:v1.2.3         # Config version
gcr.io/PROJECT/moodle-lms:moodle-5.1.2   # Moodle version
gcr.io/PROJECT/moodle-lms:latest         # Latest build
```

### Build Metadata

Labels embedded in Docker image:

```dockerfile
LABEL maintainer="COR4EDU Support <support@cor4edu.com>" \
      version="1.0" \
      moodle.version="5.1 STABLE" \
      php.version="8.2" \
      base.image="moodlehq/moodle-php-apache:8.2"
```

### View Image Tags

```bash
# List available versions
gcloud container images list-tags gcr.io/PROJECT_ID/moodle-lms

# Output:
# DIGEST    TAGS                    TIMESTAMP
# abc123    v1.2.3, latest          2025-01-13
# def456    v1.2.2, moodle-5.1.1    2025-01-10
# ghi789    v1.2.1, moodle-5.1.0    2025-01-05
```

---

## Rollback Procedures

### Rollback to Previous Configuration

```bash
# List Cloud Run revisions
gcloud run revisions list \
  --service=moodle-lms \
  --region=us-central1 \
  --project=PROJECT_ID

# Rollback to specific revision
gcloud run services update-traffic moodle-lms \
  --to-revisions=moodle-lms-00005-abc=100 \
  --region=us-central1 \
  --project=PROJECT_ID
```

### Rollback to Previous Moodle Version

**Not recommended** - requires database downgrade (complex):

1. Restore database backup from before upgrade
2. Restore moodledata backup
3. Deploy previous Docker image version
4. Verify functionality

**Better approach**: Test thoroughly in staging before production upgrade

---

## Multi-Tenant Version Management

Each school can run different Moodle versions:

| School | Project ID | Config Version | Moodle Version | Notes |
|--------|-----------|----------------|----------------|-------|
| School A | school-a-sms | v1.2.3 | 5.1.2 | Latest |
| School B | school-b-sms | v1.2.3 | 5.1.2 | Latest |
| School C | school-c-sms | v1.1.0 | 5.1.0 | Stable |

**Upgrade Strategy:**
1. Test in demo environment
2. Upgrade pilot school
3. Monitor for 1 week
4. Roll out to remaining schools

---

## Version Compatibility

### Plugin Compatibility

**Attendance Plugin:**
- Moodle 5.1: ✅ Compatible
- Moodle 5.2: Verify before upgrade
- Always check: [Moodle Plugins Directory](https://moodle.org/plugins/)

### PHP Compatibility

| Moodle Version | PHP Version | Our Base Image |
|----------------|-------------|----------------|
| 5.1 | 8.1, 8.2 | ✅ moodlehq/moodle-php-apache:8.2 |
| 5.2 | 8.1, 8.2, 8.3 | Update to 8.3 if needed |

### Database Compatibility

| Moodle Version | MySQL Version | Our Cloud SQL |
|----------------|---------------|---------------|
| 5.1 | 8.0, 8.1 | ✅ MySQL 8.0 |
| 5.2 | 8.0, 8.1, 8.2 | ✅ MySQL 8.0 |

---

## Changelog Maintenance

All changes documented in `CHANGELOG.md`:

### Format

```markdown
## [1.2.3] - 2025-01-13

### Moodle Core
- Updated to Moodle 5.1.2 (security patches)

### Configuration
- Added monitoring dashboard
- Optimized Docker build time

### Fixed
- Volume mount permission issue
- Health check timeout

### Security
- Updated PHP base image
- Patched Moodle security vulnerabilities
```

---

## Version Information Display

### Health Check Endpoint

`/healthcheck.php` includes version info:

```json
{
  "status": "healthy",
  "service": "moodle-lms",
  "version": "1.2.3",
  "moodle_version": "5.1.2",
  "php_version": "8.2.15",
  "timestamp": "2025-01-13T12:00:00Z"
}
```

### Moodle Admin Dashboard

View Moodle version:
- Site Administration → Notifications
- Shows current Moodle version
- Indicates available updates

---

## References

- [Semantic Versioning](https://semver.org/)
- [Moodle Release Notes](https://docs.moodle.org/dev/Releases)
- [Moodle Upgrade Guide](https://docs.moodle.org/en/Upgrading)
- [Moodle Security Announcements](https://moodle.org/security/)

---

**Version**: 1.0.0
**Moodle Version**: 5.1 STABLE (Build: 20251006)
**Last Updated**: 2025-01-13
**Status**: Active
