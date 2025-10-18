# Moodle VM Client Deployment Template

Complete this template for each client deployment.

## Client Information

- **School/Organization**: ___________________________
- **Domain Name**: ___________________________
- **Admin Email**: ___________________________
- **GCP Project ID**: ___________________________
- **Region**: ___________________________ (default: us-central1)
- **Deployment Date**: ___________________________

---

## Pre-Deployment Checklist

### Google Cloud Setup
- [ ] GCP project created/selected
- [ ] Billing enabled
- [ ] gcloud CLI installed
- [ ] Authenticated with gcloud
- [ ] Project ID configured

### Domain & Email
- [ ] Domain name purchased/available
- [ ] DNS access confirmed
- [ ] Admin email for SSL
- [ ] Alert email for monitoring

### Resources Planned
- [ ] VM size determined (e2-medium recommended)
- [ ] Storage size planned (30GB boot + 50GB data default)
- [ ] Backup retention period decided
- [ ] Budget approved

---

## Deployment Configuration

### Environment Variables

Create `.env` file:

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"
export INSTANCE_NAME="moodle-prod"
export DOMAIN_NAME="learning.yourschool.edu"
export ADMIN_EMAIL="admin@yourschool.edu"
```

### Deploy VM

```bash
source .env
bash deploy-to-gcp.sh production $INSTANCE_NAME
```

---

## Post-Deployment Tasks

### 1. Configure DNS
- [ ] Create A record pointing to VM IP
- [ ] Verify DNS resolution

### 2. Complete Moodle Installation
- [ ] Access installation wizard
- [ ] Configure database connection
- [ ] Create admin account
- [ ] Configure site settings

### 3. Configure SSL
```bash
sudo bash ssl-setup.sh $DOMAIN_NAME $ADMIN_EMAIL
```

### 4. Harden Security
```bash
sudo bash security-hardening.sh
```

### 5. Setup Monitoring
```bash
sudo bash monitoring-setup.sh
```

### 6. Test Backups
```bash
sudo bash backup-vm.sh
sudo bash backup-vm.sh --install-cron
```

---

## Moodle Configuration

### Email Settings
- SMTP Host: ___________________________
- SMTP User: ___________________________
- No-reply Address: ___________________________

### Site Settings
- Site Name: ___________________________
- Short Name: ___________________________
- Time Zone: ___________________________

### Custom Branding
- [ ] Logo uploaded
- [ ] Favicon uploaded
- [ ] Custom CSS (if needed)
- [ ] Welcome message configured

---

## Security Configuration

### Passwords
- Admin password (16+ chars): [ ] Created and saved
- Database password: [ ] Located in /root/.moodle-credentials
- SSH keys: [ ] Generated and saved

### Security Policies
- [ ] Force login enabled
- [ ] Password policy enforced
- [ ] Two-factor authentication (optional)
- [ ] IP restrictions (if needed)

---

## Monitoring & Alerts

### Alert Policies Created
- [ ] High CPU usage alert
- [ ] High memory usage alert
- [ ] Low disk space alert
- [ ] Uptime check configured
- [ ] Email notifications configured

### Notification Email
- Alert Email: ___________________________

---

## Backup Configuration

### Backup Settings
- Daily backups: [ ] Enabled (2 AM)
- Weekly backups: [ ] Enabled (Sundays)
- Monthly backups: [ ] Enabled (1st of month)
- Offsite backups: [ ] Configured (GCS bucket)

### Backup Verification
- [ ] Manual backup tested
- [ ] Backup files verified
- [ ] Restore procedure documented

---

## Training & Documentation

### Staff Training
- [ ] Admin login and navigation
- [ ] Course creation
- [ ] User management
- [ ] Grading and reports
- [ ] Attendance tracking

### Student Orientation
- [ ] Login instructions
- [ ] Course access
- [ ] Assignment submission
- [ ] Communication tools

### Documentation Provided
- [ ] README.md
- [ ] Admin credentials document
- [ ] Backup/restore procedures
- [ ] Troubleshooting guide
- [ ] Support contact information

---

## Maintenance Schedule

### Daily (Automated)
- Automated backups
- Security updates
- Log rotation

### Weekly
- Review security logs
- Check backup status
- Monitor disk usage

### Monthly
- Test disaster recovery
- Review performance metrics
- Update Moodle (security patches)
- Run security audit

---

## Cost Summary

| Item | Monthly Cost |
|------|--------------|
| Compute (e2-medium) | $15-18 |
| Storage (80GB SSD) | $13 |
| Snapshots | $3 |
| **Total** | **$31-34** |

**With 1-year commitment**: ~$20/month (37% savings)

---

## Deployment Sign-Off

### Deployment Team
- **Deployed by**: ___________________________
- **Date**: ___________________________
- **Deployment Duration**: ___________ hours

### Client Acceptance
- **Reviewed by**: ___________________________
- **Approved by**: ___________________________
- **Date**: ___________________________
- **Signature**: ___________________________

---

## Support Information

**Technical Support**
- Email: support@cor4edu.com
- Documentation: See README.md

**Emergency Contact**
- Critical outages: emergency@cor4edu.com

**Community Resources**
- Moodle Forums: https://moodle.org/forums
- Moodle Docs: https://docs.moodle.org

---

## Notes & Custom Requirements

```
(Document any client-specific customizations, plugins, or special requirements here)




```

---

**Save this completed template with client records for future reference and maintenance.**
