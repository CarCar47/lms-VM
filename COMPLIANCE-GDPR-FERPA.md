# GDPR and FERPA Compliance Guide for Moodle Deployment

## Overview

This document outlines how the Moodle deployment package complies with:
- **GDPR** (General Data Protection Regulation) - EU data protection law
- **FERPA** (Family Educational Rights and Privacy Act) - US student privacy law

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [GDPR Compliance](#gdpr-compliance)
3. [FERPA Compliance](#ferpa-compliance)
4. [Technical Controls](#technical-controls)
5. [Data Protection Measures](#data-protection-measures)
6. [Incident Response](#incident-response)
7. [Audit and Monitoring](#audit-and-monitoring)
8. [Compliance Checklist](#compliance-checklist)

---

## Executive Summary

### Deployment Compliance Features

✅ **Data Encryption**
- TLS 1.2/1.3 for data in transit (SSL/TLS)
- Encrypted database connections
- Google Cloud encryption at rest (AES-256)

✅ **Access Controls**
- Role-based access control (RBAC)
- Multi-factor authentication (2FA) via OS Login
- Identity-Aware Proxy (IAP) for zero-trust access
- Audit logging for all access

✅ **Data Protection**
- Automated backups with retention policies
- Point-in-time recovery capability
- Data isolation and segmentation
- Secure credential management (Secret Manager)

✅ **Security Monitoring**
- Security Command Center (SCC) integration
- CIS benchmark compliance
- Vulnerability scanning
- Real-time threat detection

✅ **Privacy Controls**
- User consent management (Moodle built-in)
- Data retention policies
- Right to erasure (data deletion)
- Data portability support

---

## GDPR Compliance

### Article 5: Principles of Data Processing

#### 1. Lawfulness, Fairness, and Transparency

**Compliance Measures:**
- Clear privacy policy in Moodle (Site admin > Users > Privacy policy)
- User consent for data collection
- Transparent data usage notifications
- Privacy settings dashboard for users

**Implementation:**
```
Moodle Configuration:
1. Site admin > Users > Privacy and policies > Privacy policy
2. Set policy content with:
   - What data is collected
   - How data is used
   - User rights (access, rectification, erasure)
   - Contact information for privacy inquiries
3. Require acceptance before account creation
```

#### 2. Purpose Limitation

**Compliance Measures:**
- Data collected only for educational purposes
- No secondary use without consent
- Clear data processing agreements

**Technical Implementation:**
- Moodle user profiles limited to educational data
- Optional fields clearly marked
- Analytics opt-in (not opt-out)

#### 3. Data Minimization

**Compliance Measures:**
- Only essential data collected
- Minimal personal information required
- Anonymous usage data where possible

**Moodle Settings:**
```
Site admin > Users > Permissions > User policies
- Require email confirmation: Yes
- Minimum data for user creation:
  * Username
  * Email
  * First name / Last name
  * Password
- Optional fields disabled by default
```

#### 4. Accuracy

**Compliance Measures:**
- Users can update their own profiles
- Regular data quality checks
- Data validation on input

**User Rights:**
- Profile editing enabled for all users
- Self-service data correction
- Admin data correction upon request

#### 5. Storage Limitation

**Compliance Measures:**
- Defined retention periods
- Automated data deletion
- Backup retention policies

**Retention Policy:**
```bash
# Moodle Data Retention (configure in Site admin > Users > Privacy)
- Active users: Indefinite
- Inactive users (no login 2 years): Flag for review
- Deleted users: 30 days in recycle bin, then permanent deletion
- Course data: Retain for academic year + 3 years
- Logs: 90 days (extended via Cloud Logging: 400 days)
- Backups: 30 days (configurable via backup-validation.sh)
```

#### 6. Integrity and Confidentiality (Security)

**Security Measures Implemented:**

✅ **Encryption:**
- TLS 1.2/1.3 (ssl-setup.sh)
- Database encryption at rest (Google Cloud default)
- Encrypted backups

✅ **Access Control:**
- OS Login with 2FA (setup-vm.sh)
- IAP for administrative access (iap-setup.sh)
- Strong password policies (cis-hardening.sh)

✅ **Network Security:**
- Cloud Armor WAF (cloud-armor-setup.sh)
- Rate limiting (nginx.conf, apache-ratelimit.conf)
- Firewall rules (UFW + GCP firewall)

✅ **Monitoring:**
- Security Command Center (scc-setup.sh)
- Audit logging (auditd via cis-hardening.sh)
- Intrusion detection

#### 7. Accountability

**Compliance Measures:**
- Data protection impact assessments (DPIA)
- Privacy by design and default
- Regular compliance audits
- Documentation of processing activities

**Documentation Required:**
- [ ] Data Processing Agreement (DPA) with subprocessors
- [ ] Privacy Impact Assessment (PIA) for new features
- [ ] Records of processing activities (ROPA)
- [ ] Data breach notification procedures

---

### Article 17: Right to Erasure ("Right to be Forgotten")

**Implementation:**

1. **User-Initiated Deletion:**
   ```
   Moodle: Site admin > Users > Privacy and policies > Data requests
   - Enable user data deletion requests
   - Review and approve within 30 days
   ```

2. **Administrative Deletion:**
   ```bash
   # Delete user and all associated data
   php admin/cli/user_delete.php --username=USERNAME --purge=1

   # Verify deletion
   grep "USERNAME" /var/log/moodle-audit.log
   ```

3. **Backup Deletion:**
   ```bash
   # Remove user from backups (if legally required)
   # Note: This may not be possible for encrypted backups
   # Consider backup retention policies instead
   ```

### Article 20: Right to Data Portability

**Implementation:**

1. **Export User Data:**
   ```
   Moodle: Site admin > Users > Privacy and policies > Data requests
   - User requests data export
   - Admin approves
   - Data exported in JSON/XML format
   - Download link provided
   ```

2. **Automated Export:**
   ```bash
   # Export user data via CLI
   php admin/cli/user_data_export.php --username=USERNAME --format=json
   ```

### Article 25: Data Protection by Design and Default

**Privacy-First Features:**

✅ **Default Privacy Settings:**
- User profiles private by default
- Activity tracking opt-in
- Course participation privacy controls

✅ **Privacy Dashboard:**
```
User menu > Preferences > Privacy
- View all personal data
- Download data
- Request data deletion
- Manage privacy settings
```

✅ **Pseudonymization:**
```
Site admin > Users > Privacy > Anonymize users
- Replace names with pseudonyms in analytics
- Preserve functionality while protecting identity
```

### Article 30: Records of Processing Activities (ROPA)

**Required Documentation:**

```markdown
# Data Processing Record

**Controller:** [Institution Name]
**DPO Contact:** [Data Protection Officer Email]

## Processing Activities

### 1. Student Enrollment
- **Purpose:** Student account creation and course access
- **Data Categories:** Name, email, student ID, enrollment date
- **Recipients:** Teachers, administrators
- **Retention:** Active enrollment + 3 years
- **Security:** Encrypted at rest and in transit

### 2. Course Activity
- **Purpose:** Learning analytics and progress tracking
- **Data Categories:** Course access, quiz scores, assignment submissions
- **Recipients:** Course teachers, student (self)
- **Retention:** Course end + 1 year
- **Security:** Access-controlled, audit logged

### 3. Communications
- **Purpose:** Forum posts, messaging, announcements
- **Data Categories:** Message content, timestamps, sender/recipient
- **Recipients:** Course participants
- **Retention:** Course duration + 90 days
- **Security:** Access-restricted to course participants
```

### Article 33: Breach Notification

**Incident Response Procedure:**

1. **Detection:** Security Command Center alerts
2. **Assessment:** Within 24 hours
3. **Notification:** Within 72 hours if high risk
4. **Documentation:** Incident report required

**See:** [Incident Response](#incident-response)

---

## FERPA Compliance

### What is FERPA?

The Family Educational Rights and Privacy Act (FERPA) is a US federal law protecting student education records.

### Applicability

**Covered Institutions:**
- US schools receiving federal funding
- K-12 schools
- Colleges and universities

**Protected Information:**
- Education records
- Grades and transcripts
- Disciplinary records
- Financial information
- Personal identifiers

### FERPA Requirements

#### 1. Student Rights

**Access Rights:**
- Students can review their education records
- Request corrections to inaccurate records

**Implementation:**
```
Moodle: User menu > Grades
- Students view their own grades
- Request grade corrections via messaging
- Download grade reports
```

#### 2. Consent for Disclosure

**Rule:** Cannot disclose education records without written consent

**Exceptions:**
- School officials with legitimate educational interest
- Other schools to which student is transferring
- Authorized representatives for audit purposes
- Financial aid determination
- Compliance with judicial order

**Implementation:**
```bash
# Access Control via Moodle Roles
Site admin > Users > Permissions > Define roles

Teacher Role:
- View grades in own courses: ✓
- View grades in other courses: ✗

Student Role:
- View own grades: ✓
- View other students' grades: ✗

Admin Role:
- Access all records: ✓ (with audit logging)
```

#### 3. Directory Information

**Can be disclosed without consent if institution provides notice:**
- Student name
- Email address
- Date of birth
- Enrollment status

**Implementation:**
```
Site admin > Users > Privacy > Directory information
- Define what constitutes directory information
- Allow students to opt-out
- Provide annual notice
```

#### 4. Security Measures

**Physical Security:**
- ✅ No on-premises servers (cloud-based)
- ✅ Data center security (Google Cloud)

**Technical Security:**
- ✅ Encryption (TLS 1.2/1.3)
- ✅ Access controls (RBAC)
- ✅ Audit logging
- ✅ Multi-factor authentication

**Administrative Security:**
- ✅ Staff training on FERPA
- ✅ Acceptable use policies
- ✅ Incident response plan

### FERPA Audit Requirements

**Annual Review:**
- [ ] Review user access permissions
- [ ] Audit disclosure logs
- [ ] Verify encryption status
- [ ] Test backup/recovery procedures
- [ ] Update privacy policies

**Audit Command:**
```bash
# Run FERPA compliance check
./moodle-security-check.sh --ferpa-audit

# Review audit logs
grep "GRADE_VIEW" /var/log/moodle-audit.log | \
  awk '{print $1, $2, $5}' | \
  sort | uniq -c
```

---

## Technical Controls

### Encryption

#### Data in Transit

**TLS Configuration:**
```nginx
# nginx.conf (lines 78-93)
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:...';
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_stapling on;
ssl_stapling_verify on;
```

**Verification:**
```bash
# Test TLS configuration
curl -I https://yourdomain.com

# SSL Labs test
# Visit: https://www.ssllabs.com/ssltest/
```

#### Data at Rest

**Google Cloud Encryption:**
- Automatic encryption (AES-256)
- Encrypted persistent disks
- Encrypted Cloud Storage buckets
- Encrypted database storage

**Verification:**
```bash
# Check disk encryption status
gcloud compute disks describe DISK_NAME \
  --zone=ZONE \
  --format="get(diskEncryptionKey)"

# Should show: Google-managed encryption
```

### Access Control

#### Role-Based Access Control (RBAC)

**Moodle Roles:**
```
1. System Administrator
   - Full system access
   - User management
   - System configuration

2. Course Creator
   - Create and manage courses
   - Enroll students/teachers

3. Teacher
   - Manage course content
   - Grade assignments
   - View course participant data

4. Student
   - Access enrolled courses
   - Submit assignments
   - View own grades
```

**Least Privilege Principle:**
```bash
# Review role assignments
php admin/cli/role_assignments.php --report

# Remove unnecessary permissions
php admin/cli/role_modify.php --role=teacher \
  --capability=moodle/site:config --permission=prohibit
```

#### Multi-Factor Authentication

**Google Cloud MFA (2025 Mandatory):**
```
Implemented via OS Login (setup-vm.sh):
- Enable OS Login with 2FA metadata
- Users configure 2FA at Google Account level
- Security keys/passkeys recommended (phishing-resistant)
- Google Authenticator alternative
```

**Moodle MFA Plugin (Optional):**
```bash
# Install MFA plugin for Moodle
git clone https://github.com/catalyst/moodle-tool_mfa \
  /var/www/html/moodle/admin/tool/mfa

# Enable in Moodle
Site admin > Plugins > Admin tools > Multi-factor authentication
```

### Audit Logging

#### Moodle Audit Logs

**Enabled Features:**
```
Site admin > Reports > Logs
- Standard logs: All actions
- Live logs: Real-time monitoring
- Report builder: Custom compliance reports
```

**Compliance Reports:**
```sql
-- User data access log
SELECT FROM_UNIXTIME(timecreated) as access_time,
       userid,
       courseid,
       action,
       target,
       ip
FROM mdl_logstore_standard_log
WHERE action = 'viewed'
  AND target = 'user'
  AND timecreated > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 30 DAY))
ORDER BY timecreated DESC;
```

#### System Audit Logs (auditd)

**Configured via cis-hardening.sh:**
```bash
# View audit logs for file access
ausearch -f /etc/passwd -i

# Search for user modifications
ausearch -m ADD_USER,DEL_USER,MOD_USER -i

# Generate compliance report
aureport --summary
```

#### Google Cloud Audit Logs

**Enabled Services:**
- Admin Activity logs (400 days retention)
- Data Access logs (configurable)
- System Event logs
- Policy Denied logs

**Query Logs:**
```bash
# View admin activity
gcloud logging read "logName:activity" \
  --project=PROJECT_ID \
  --limit=100 \
  --format=json

# Export to BigQuery for long-term storage
gcloud logging sinks create compliance-audit \
  bigquery.googleapis.com/projects/PROJECT_ID/datasets/audit_logs \
  --log-filter='logName:"cloudaudit.googleapis.com"'
```

---

## Data Protection Measures

### Backup and Recovery

**Backup Schedule:**
```
Daily: Full database backup (04:00 UTC)
Weekly: Full moodledata backup (Sunday 02:00 UTC)
Monthly: Validation test restore (15th of month)
```

**Backup Encryption:**
```bash
# Backups encrypted by default (Google Cloud Storage)
gsutil encryption -h

# Verify encryption status
gsutil ls -L gs://BUCKET_NAME/backups/
```

**Data Retention:**
```
Daily backups: 7 days
Weekly backups: 30 days
Monthly backups: 90 days
Annual backups: 3 years (for compliance)
```

**Recovery Testing:**
```bash
# Monthly backup validation (automated)
/moodle-VM/backup-validation.sh --test-restore

# Disaster recovery drill (quarterly)
# Full restoration to test environment
```

### Data Isolation

**Multi-Tenancy:**
- Separate Moodle instance per institution
- No shared user databases
- Isolated moodledata directories

**Database Security:**
```sql
-- Dedicated database user per Moodle instance
CREATE USER 'moodle_inst1'@'localhost' IDENTIFIED BY 'STRONG_PASSWORD';
GRANT ALL PRIVILEGES ON moodle_inst1.* TO 'moodle_inst1'@'localhost';

-- Revoke unnecessary privileges
REVOKE FILE ON *.* FROM 'moodle_inst1'@'localhost';
REVOKE PROCESS ON *.* FROM 'moodle_inst1'@'localhost';
```

### Data Minimization

**Moodle Configuration:**
```php
// config.php - Disable unnecessary tracking
$CFG->enablestats = false;          // Disable legacy stats
$CFG->enableglobalreports = false;  // Disable global reports
$CFG->perfdebug = 0;                // Disable performance debug
$CFG->debugdisplay = 0;             // Hide debug messages

// Enable privacy features
$CFG->allowemailaddresses = '';     // Restrict email domains
$CFG->profileroles = 'student';     // Limit profile visibility
```

**Data Collection:**
```
Collect ONLY:
✓ Required for education: Name, email, enrollment
✗ Not required: Birthdate, phone, address (make optional)
✗ Third-party analytics: Google Analytics (opt-in only)
✗ Social media integration: Disable by default
```

---

## Incident Response

### Data Breach Response Plan

#### Phase 1: Detection and Analysis (0-4 hours)

**Trigger Events:**
- Security Command Center critical alert
- Unusual data access patterns
- User report of unauthorized access
- External notification (researcher, law enforcement)

**Immediate Actions:**
1. **Isolate affected systems**
   ```bash
   # Disable affected accounts
   php admin/cli/user_suspend.php --username=AFFECTED_USER

   # Block suspicious IPs
   gcloud compute firewall-rules create block-incident \
     --action=DENY \
     --rules=all \
     --source-ranges=MALICIOUS_IP
   ```

2. **Preserve evidence**
   ```bash
   # Snapshot affected systems
   gcloud compute disks snapshot DISK_NAME \
     --snapshot-names=incident-$(date +%Y%m%d-%H%M%S)

   # Export logs
   gcloud logging read "timestamp >= $(date -d '24 hours ago' --iso-8601)" \
     --format=json > /tmp/incident-logs.json
   ```

3. **Assess scope**
   ```bash
   # Identify affected users
   grep "UNAUTHORIZED_ACCESS" /var/log/moodle-audit.log

   # Check data access
   SELECT COUNT(*) FROM mdl_logstore_standard_log
   WHERE ip = 'MALICIOUS_IP'
     AND action = 'viewed'
     AND timecreated > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 24 HOUR));
   ```

#### Phase 2: Containment (4-24 hours)

**Short-term Containment:**
1. Change all admin passwords
2. Revoke all API tokens
3. Enable enhanced monitoring
4. Notify security team

**Long-term Containment:**
1. Apply security patches
2. Update firewall rules
3. Enable additional logging
4. Implement compensating controls

#### Phase 3: Notification (24-72 hours)

**GDPR Requirements:**
- Notify supervisory authority within 72 hours
- Notify affected users if high risk
- Document the breach

**FERPA Requirements:**
- No specific timeframe, but "without unreasonable delay"
- Notify affected students/parents
- Notify Department of Education if systemic issue

**Notification Template:**
```
Subject: Security Incident Notification

Dear [User],

We are writing to inform you of a security incident that may have affected your personal information.

What happened: [Brief description]
What information was involved: [Data categories]
What we are doing: [Response actions]
What you can do: [Recommended actions]

We take the security of your data seriously and have implemented additional measures to prevent future incidents.

For questions, contact: [DPO/Security Contact]

Sincerely,
[Institution Name]
```

#### Phase 4: Recovery and Lessons Learned

**Recovery Steps:**
1. Restore from clean backup if necessary
2. Verify system integrity
3. Monitor for recurrence
4. Gradually restore services

**Post-Incident Review:**
```markdown
# Incident Report Template

## Incident Summary
- Date/Time: [timestamp]
- Duration: [hours]
- Severity: [Critical/High/Medium/Low]
- Affected users: [count]

## Root Cause
[Technical explanation]

## Timeline
- Detection: [timestamp]
- Containment: [timestamp]
- Notification: [timestamp]
- Recovery: [timestamp]

## Lessons Learned
1. [Finding 1]
2. [Finding 2]
3. [Finding 3]

## Action Items
- [ ] Action 1 (Owner: X, Due: Y)
- [ ] Action 2 (Owner: X, Due: Y)
```

---

## Audit and Monitoring

### Continuous Compliance Monitoring

**Automated Checks:**
```bash
# Weekly compliance scan
0 9 * * 1 /moodle-VM/moodle-security-check.sh --gdpr --ferpa

# Monthly CIS audit
0 3 1 * * /moodle-VM/cis-hardening.sh --audit-only

# Quarterly backup validation
0 2 15 */3 * /moodle-VM/backup-validation.sh --test-restore
```

**Manual Reviews:**
```
Monthly:
- [ ] Review user access logs
- [ ] Check for inactive accounts (>90 days)
- [ ] Verify encryption status
- [ ] Review privacy policy updates

Quarterly:
- [ ] Data retention policy compliance
- [ ] Third-party processor audit
- [ ] Security awareness training completion
- [ ] Disaster recovery drill

Annually:
- [ ] Full GDPR/FERPA compliance audit
- [ ] Privacy impact assessment
- [ ] Update data processing agreements
- [ ] Review and update policies
```

### Compliance Dashboards

**Google Cloud Monitoring:**
```yaml
# Sample Dashboard Configuration
dashboards:
  - name: "GDPR Compliance"
    widgets:
      - title: "Encryption Status"
        type: scorecard
        metric: "custom/encryption/status"
        target: 100%

      - title: "Data Access Logs"
        type: chart
        metric: "logging.googleapis.com/user/data_access"

      - title: "Backup Success Rate"
        type: scorecard
        metric: "custom/backup/success_rate"
        target: 100%
```

**Moodle Compliance Reports:**
```
Site admin > Reports > GDPR > Data registry
Site admin > Reports > Privacy > Data requests
Site admin > Reports > Security > Security overview
```

---

## Compliance Checklist

### Pre-Deployment

**GDPR:**
- [ ] Privacy policy drafted and approved
- [ ] Data processing agreements signed
- [ ] Privacy impact assessment completed
- [ ] DPO designated (if required)
- [ ] User consent mechanism implemented

**FERPA:**
- [ ] Annual notice prepared
- [ ] Directory information defined
- [ ] Disclosure authorization forms ready
- [ ] Staff training materials prepared
- [ ] Record retention schedule defined

**Technical:**
- [ ] TLS/SSL certificates configured
- [ ] Backups tested and validated
- [ ] Audit logging enabled
- [ ] MFA configured for admins
- [ ] Firewall rules reviewed

### Post-Deployment

**Week 1:**
- [ ] Verify SSL/TLS working (A+ rating on SSL Labs)
- [ ] Test backup/restore procedure
- [ ] Configure Cloud Armor WAF
- [ ] Enable Security Command Center
- [ ] Test user data export

**Month 1:**
- [ ] Complete CIS hardening audit
- [ ] Review all user access logs
- [ ] Test incident response procedure
- [ ] Conduct security awareness training
- [ ] Document all processing activities

**Ongoing:**
- [ ] Monthly security scans
- [ ] Quarterly disaster recovery drills
- [ ] Annual compliance audits
- [ ] Continuous monitoring

---

## Additional Resources

### Regulatory Guidance

**GDPR:**
- Official Text: https://gdpr-info.eu/
- ICO Guidance: https://ico.org.uk/for-organisations/guide-to-data-protection/guide-to-the-general-data-protection-regulation-gdpr/
- EDPB Guidelines: https://edpb.europa.eu/

**FERPA:**
- DOE Guidance: https://studentprivacy.ed.gov/
- FERPA Regulations: https://www.ecfr.gov/current/title-34/subtitle-A/part-99
- PTAC Resources: https://studentprivacy.ed.gov/resources

### Technical Resources

**Moodle Privacy:**
- Privacy API: https://docs.moodle.org/dev/Privacy_API
- GDPR Plugin: https://docs.moodle.org/en/GDPR
- Data Requests: https://docs.moodle.org/en/Data_privacy

**Google Cloud Compliance:**
- Compliance Resource Center: https://cloud.google.com/security/compliance
- Data Protection: https://cloud.google.com/security/data-protection
- Audit Logging: https://cloud.google.com/logging/docs/audit

---

## Conclusion

This Moodle deployment package implements industry-standard security and privacy controls to support GDPR and FERPA compliance. However, **compliance is not a one-time event** - it requires:

1. **Ongoing monitoring** - Automated checks and manual reviews
2. **Regular updates** - Software patches and security improvements
3. **Staff training** - Privacy awareness and best practices
4. **Documentation** - Maintaining records of processing activities
5. **Continuous improvement** - Learning from incidents and audits

**Remember:** Technology alone cannot ensure compliance. Organizational policies, procedures, and culture are equally important.

---

**Document Version:** 1.0.0
**Last Updated:** 2025-01-17
**Next Review:** 2025-07-17 (6 months)

For questions or concerns, contact:
- **Data Protection Officer:** [dpo@institution.edu]
- **Security Team:** [security@institution.edu]
- **Compliance Officer:** [compliance@institution.edu]
