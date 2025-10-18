# Certificate Transparency Monitoring Guide

## Overview

Certificate Transparency (CT) is a Google-initiated open-source framework that provides an audit trail for SSL/TLS certificates, protecting against fraudulent certificates.

## Why Certificate Transparency Matters

- **Detection of Mis-issued Certificates**: Identify unauthorized certificates issued for your domains
- **Compliance**: Required by modern browsers (Chrome, Safari, Firefox)
- **Security**: Early warning system for certificate-based attacks
- **Trust**: Demonstrates commitment to security best practices

## Automatic CT with Let's Encrypt

**Good News**: If you're using Let's Encrypt (via ssl-setup.sh), Certificate Transparency is **automatically enabled**.

Let's Encrypt submits all certificates to CT logs automatically. No additional configuration needed!

## Monitoring Your Certificates

### 1. Google Certificate Transparency Search

Monitor certificates issued for your domain:
- Visit: https://transparencyreport.google.com/https/certificates
- Search for your domain (e.g., `example.com`)
- Review all certificates issued
- Set up email alerts for new certificates

### 2. crt.sh - Certificate Search

Another excellent free service:
- Visit: https://crt.sh
- Search: `%.yourdomain.com`
- View all certificates for domain and subdomains
- Check for unauthorized certificates

### 3. Certificate Transparency Monitor (Paid)

For enterprise monitoring:
- **Facebook CT Monitor**: https://github.com/facebook/ct-monitoring
- **Censys**: https://censys.io (paid)
- **SSLMate**: https://sslmate.com/certspotter/ (paid)

## Setting Up Alerts

### Google Certificate Transparency Alerts

1. Go to: https://transparencyreport.google.com/https/certificates
2. Search for your domain
3. Click "Monitor this domain"
4. Enter email address
5. Receive notifications for new certificates

### Manual Monitoring Script

Create a simple monitoring script:

```bash
#!/bin/bash
# Check for new certificates via crt.sh API

DOMAIN="yourdomain.com"
EMAIL="admin@yourdomain.com"

# Get certificates from last 7 days
CERTS=$(curl -s "https://crt.sh/?q=${DOMAIN}&output=json" | \
    jq -r '.[] | select(.entry_timestamp >= (now - 604800 | strftime("%Y-%m-%dT%H:%M:%S"))) | .common_name')

if [[ -n "$CERTS" ]]; then
    echo "New certificates detected for $DOMAIN in the last 7 days:" | mail -s "CT Alert: $DOMAIN" "$EMAIL"
    echo "$CERTS" | mail -s "CT Alert: $DOMAIN" "$EMAIL"
fi
```

Schedule with cron:
```bash
# Run weekly certificate transparency check
0 9 * * 1 /usr/local/bin/ct-monitor.sh
```

## Best Practices

### 1. Regular Monitoring
- Check CT logs at least weekly
- Review all new certificates
- Investigate unauthorized certificates immediately

### 2. Domain Validation
- Maintain a list of authorized certificate authorities
- Only use reputable CAs (Let's Encrypt, DigiCert, etc.)
- Monitor for certificates from unexpected CAs

### 3. Response Plan
If you find an unauthorized certificate:

1. **Immediate Actions**:
   - Contact the CA that issued the certificate
   - Request immediate revocation
   - Report to your security team

2. **Investigation**:
   - Check domain control validation
   - Review DNS records for unauthorized changes
   - Audit certificate issuance processes

3. **Mitigation**:
   - Implement CAA DNS records (see below)
   - Enable DNSSEC
   - Review access controls for domain management

## CAA Records (Certificate Authority Authorization)

Prevent unauthorized CAs from issuing certificates:

### What is CAA?

CAA DNS records specify which CAs are authorized to issue certificates for your domain.

### Setting Up CAA Records

Add to your DNS (replace with your domain):

```dns
; Allow Let's Encrypt only
yourdomain.com.  CAA  0 issue "letsencrypt.org"
yourdomain.com.  CAA  0 issuewild "letsencrypt.org"

; Report unauthorized attempts
yourdomain.com.  CAA  0 iodef "mailto:security@yourdomain.com"
```

### Verify CAA Records

```bash
dig CAA yourdomain.com
```

## SSL/TLS Certificate Monitoring Integration

### With Google Cloud Monitoring

Monitor certificate expiration:

```yaml
# Cloud Monitoring Alert Policy
displayName: "SSL Certificate Expiration"
conditions:
  - displayName: "Certificate expires in 30 days"
    conditionThreshold:
      filter: 'resource.type="uptime_url" AND metric.type="monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires"'
      comparison: COMPARISON_LT
      thresholdValue: 2592000  # 30 days in seconds
      duration: 0s
notificationChannels:
  - projects/PROJECT_ID/notificationChannels/CHANNEL_ID
```

### With External Monitoring

Third-party services:
- **SSL Labs**: https://www.ssllabs.com/ssltest/
- **SSL Shopper**: https://www.sslshopper.com/ssl-checker.html
- **DigiCert**: https://www.digicert.com/help/

## Integration with Moodle Security

### 1. Document in Security Policy

Include CT monitoring in your security documentation:
- Security policy (see COMPLIANCE-GDPR-FERPA.md)
- Incident response procedures
- Regular security audit checklist

### 2. Include in Security Audits

Add to moodle-security-check.sh:

```bash
# Check SSL certificate transparency
DOMAIN=$(hostname -f)
CT_CERTS=$(curl -s "https://crt.sh/?q=${DOMAIN}&output=json" | jq -r '.[].issuer_name' | sort -u)

log "Certificate Transparency Check:"
log "  Certificates found for $DOMAIN:"
echo "$CT_CERTS"
```

### 3. Compliance Requirements

**GDPR**: Demonstrates security measures for data protection
**FERPA**: Shows due diligence for student data security
**SOC 2**: Part of comprehensive security monitoring

## Quick Reference

| Service | URL | Cost | Features |
|---------|-----|------|----------|
| Google CT | https://transparencyreport.google.com/https/certificates | Free | Search, alerts |
| crt.sh | https://crt.sh | Free | Search, API |
| SSL Labs | https://www.ssllabs.com/ssltest/ | Free | Security testing |
| SSLMate | https://sslmate.com/certspotter/ | Paid | Enterprise monitoring |
| Censys | https://censys.io | Paid | Advanced search |

## Automated Setup (Optional)

For automated CT monitoring, add to monitoring-setup.sh:

```bash
# Install jq for JSON parsing
apt-get install -y jq

# Create CT monitoring script
cat > /usr/local/bin/ct-monitor.sh << 'CTEOF'
#!/bin/bash
DOMAIN="$(hostname -f)"
ALERT_EMAIL="admin@example.com"

# Check for new certificates in last 7 days
NEW_CERTS=$(curl -s "https://crt.sh/?q=${DOMAIN}&output=json" | \
    jq -r '.[] | select(.entry_timestamp >= (now - 604800 | strftime("%Y-%m-%dT%H:%M:%S"))) |
    "\(.common_name) - \(.issuer_name) - \(.entry_timestamp)"')

if [[ -n "$NEW_CERTS" ]]; then
    echo "New certificates detected:" | mail -s "CT Alert: $DOMAIN" "$ALERT_EMAIL"
    echo "$NEW_CERTS" | mail -s "CT Alert: $DOMAIN" "$ALERT_EMAIL"
fi
CTEOF

chmod +x /usr/local/bin/ct-monitor.sh

# Add to cron (weekly Monday 9am)
echo "0 9 * * 1 /usr/local/bin/ct-monitor.sh" | crontab -
```

## Summary

✅ **Let's Encrypt automatically provides CT** - no setup needed
✅ **Monitor via Google CT or crt.sh** - free and simple
✅ **Set up CAA records** - prevent unauthorized issuance
✅ **Enable alerts** - early detection of issues
✅ **Include in security audits** - demonstrate compliance

## Additional Resources

- [Google CT Explainer](https://certificate.transparency.dev/)
- [CAA Records Explained](https://letsencrypt.org/docs/caa/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [SSL Best Practices](https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices)

---

**Note**: This monitoring is automatically included when using Let's Encrypt via the ssl-setup.sh script. Additional monitoring is optional but recommended for production environments.
