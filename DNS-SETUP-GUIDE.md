# DNS Setup Guide for Moodle VM
Complete DNS Configuration for Production Deployment

---

## 🎯 Overview

This guide walks you through configuring DNS for your Moodle VM deployment. Proper DNS configuration is **REQUIRED** before you can obtain an SSL certificate and access Moodle via a custom domain.

**What you'll learn:**
- How to configure DNS A records
- How to verify DNS propagation
- How to set up SSL after DNS is ready
- Common DNS troubleshooting

---

## 📋 Prerequisites

Before starting DNS configuration:

1. **Static IP Address**: Your VM must have a static IP (automatically configured by deploy-to-gcp.sh)
2. **Domain Name**: You must own a domain (e.g., yourdomain.com)
3. **DNS Provider Access**: Access to your domain's DNS management panel

**Common DNS Providers:**
- GoDaddy
- Cloudflare
- Google Domains
- Namecheap
- Route53 (AWS)
- Any registrar where you purchased your domain

---

## 🔍 Step 1: Find Your Static IP Address

### Option 1: From Deployment Info File

After running `deploy-to-gcp.sh`, check the deployment info file:

```bash
cat ~/.moodle-vm-deployments/moodle-vm.txt
```

Look for:
```
External IP: XXX.XXX.XXX.XXX (STATIC - permanent)
Static IP Name: moodle-vm-ip
```

### Option 2: Using gcloud Command

```bash
# List all static IPs in your project
gcloud compute addresses list

# Get specific static IP
gcloud compute addresses describe moodle-vm-ip \
    --region=us-central1 \
    --format="value(address)"
```

### Option 3: From Google Cloud Console

1. Go to: https://console.cloud.google.com/networking/addresses
2. Find your static IP (name: `moodle-vm-ip` or `<instance-name>-ip`)
3. Copy the IP address

---

## ⚙️ Step 2: Configure DNS A Records

DNS A records map your domain name to your server's IP address.

### What to Create:

You need **TWO** A records:

1. **Root domain** (@) → Points to your static IP
2. **www subdomain** (www) → Points to your static IP

This ensures both `yourdomain.com` AND `www.yourdomain.com` work.

---

### Configuration by Provider:

#### GoDaddy

1. Log in to GoDaddy: https://dcc.godaddy.com/
2. Go to **My Products** → **Domains** → Click **DNS** next to your domain
3. Scroll to **Records** section

**Add Root Domain Record:**
- Type: `A`
- Name: `@`
- Value: `YOUR_STATIC_IP` (e.g., 34.72.123.45)
- TTL: `600` (or 1 hour)
- Click **Save**

**Add WWW Subdomain Record:**
- Type: `A`
- Name: `www`
- Value: `YOUR_STATIC_IP` (same IP)
- TTL: `600`
- Click **Save**

---

#### Cloudflare

1. Log in to Cloudflare: https://dash.cloudflare.com/
2. Select your domain
3. Go to **DNS** → **Records**

**Add Root Domain Record:**
- Type: `A`
- Name: `@` (or leave blank, it will auto-fill with your domain)
- IPv4 address: `YOUR_STATIC_IP`
- Proxy status: **DNS only** (orange cloud OFF for initial setup)
- TTL: `Auto`
- Click **Save**

**Add WWW Subdomain Record:**
- Type: `A`
- Name: `www`
- IPv4 address: `YOUR_STATIC_IP`
- Proxy status: **DNS only** (you can enable proxy later)
- TTL: `Auto`
- Click **Save**

**Important**: For initial SSL setup, disable Cloudflare proxy (orange cloud OFF). Enable after SSL is working.

---

#### Google Domains / Cloud DNS

**Google Domains:**

1. Go to: https://domains.google.com/
2. Click your domain → **DNS**

**Add Root Domain Record:**
- Type: `A`
- Host name: `@`
- Data: `YOUR_STATIC_IP`
- TTL: `3600`

**Add WWW Subdomain Record:**
- Type: `A`
- Host name: `www`
- Data: `YOUR_STATIC_IP`
- TTL: `3600`

**Google Cloud DNS (Advanced):**

```bash
# Create DNS zone (one-time setup)
gcloud dns managed-zones create moodle-zone \
    --dns-name="yourdomain.com." \
    --description="Moodle DNS zone"

# Add A record for root domain
gcloud dns record-sets create yourdomain.com. \
    --zone="moodle-zone" \
    --type="A" \
    --ttl="300" \
    --rrdatas="YOUR_STATIC_IP"

# Add A record for www subdomain
gcloud dns record-sets create www.yourdomain.com. \
    --zone="moodle-zone" \
    --type="A" \
    --ttl="300" \
    --rrdatas="YOUR_STATIC_IP"
```

---

#### Namecheap

1. Log in: https://www.namecheap.com/
2. Go to **Domain List** → Click **Manage** next to your domain
3. Go to **Advanced DNS** tab

**Add Root Domain Record:**
- Type: `A Record`
- Host: `@`
- Value: `YOUR_STATIC_IP`
- TTL: `Automatic` or `5 min`
- Click **Save**

**Add WWW Subdomain Record:**
- Type: `A Record`
- Host: `www`
- Value: `YOUR_STATIC_IP`
- TTL: `Automatic`
- Click **Save**

---

#### AWS Route53

1. Go to: https://console.aws.amazon.com/route53/
2. Click **Hosted zones** → Select your domain
3. Click **Create record**

**Add Root Domain Record:**
- Record name: (leave blank for root)
- Record type: `A - Routes traffic to an IPv4 address`
- Value: `YOUR_STATIC_IP`
- TTL: `300`
- Routing policy: `Simple routing`
- Click **Create records**

**Add WWW Subdomain Record:**
- Record name: `www`
- Record type: `A`
- Value: `YOUR_STATIC_IP`
- TTL: `300`
- Click **Create records**

---

## ⏱️ Step 3: Wait for DNS Propagation

After creating DNS records, you must wait for DNS propagation.

**Propagation Time:**
- **Minimum**: 5-10 minutes
- **Typical**: 15-30 minutes
- **Maximum**: Up to 48 hours (rare)

**Factors affecting propagation:**
- TTL (Time To Live) value: Lower TTL = faster updates
- DNS provider: Some providers are faster than others
- ISP caching: Your internet provider may cache old DNS records

**What to do while waiting:**
- ☕ Take a break
- 📧 Check email
- 📚 Read Moodle documentation
- 🔄 Continue to Step 4 to verify

---

## ✅ Step 4: Verify DNS Configuration

### Method 1: Using dig command (Linux/Mac)

```bash
# Check root domain
dig yourdomain.com +short

# Check www subdomain
dig www.yourdomain.com +short

# Expected output: YOUR_STATIC_IP (e.g., 34.72.123.45)
```

### Method 2: Using nslookup (Windows/All)

```bash
# Check root domain
nslookup yourdomain.com

# Check www subdomain
nslookup www.yourdomain.com

# Look for "Address: YOUR_STATIC_IP" in the output
```

### Method 3: Using gcloud (if gcloud CLI installed)

```bash
# From your Moodle VM
gcloud compute ssh moodle-vm --zone=us-central1-a --command="
    dig yourdomain.com +short
    dig www.yourdomain.com +short
"

# Should return your static IP twice
```

### Method 4: Online DNS Checkers

Use these websites to check DNS from multiple locations:

- https://dnschecker.org/ (checks from 20+ locations worldwide)
- https://www.whatsmydns.net/
- https://mxtoolbox.com/SuperTool.aspx

**Enter your domain and select "A" record type**

---

## 🔒 Step 5: Set Up SSL Certificate

**ONLY proceed after DNS is verified!**

Once DNS is propagated and verified:

### 1. SSH into your VM

```bash
gcloud compute ssh moodle-vm --zone=us-central1-a
```

### 2. Run SSL Setup Script

```bash
sudo bash /opt/moodle-deployment/ssl-setup.sh yourdomain.com admin@yourdomain.com
```

Replace:
- `yourdomain.com` with your actual domain
- `admin@yourdomain.com` with your email for Let's Encrypt notifications

### 3. SSL Script Will:

✅ Verify DNS points to server IP
✅ Install Certbot (Let's Encrypt client)
✅ Obtain free SSL certificate
✅ Configure Apache/Nginx for HTTPS
✅ Set up auto-renewal (certificates renew every 90 days)

### 4. Verify HTTPS Works

After SSL setup, test:

```bash
# Check if site is accessible via HTTPS
curl -I https://yourdomain.com

# You should see "HTTP/2 200" or "HTTP/1.1 200"
```

**Visit in browser**: https://yourdomain.com (should show 🔒 padlock icon)

---

## 🛠️ Troubleshooting

### Problem: DNS Not Resolving

**Symptoms:**
- `dig yourdomain.com` returns no IP
- Browser shows "DNS_PROBE_FINISHED_NXDOMAIN"

**Solutions:**

1. **Verify DNS records are saved** - Log back into DNS provider and confirm A records exist
2. **Check for typos** - Ensure domain name is spelled correctly
3. **Wait longer** - Some providers take 30-60 minutes
4. **Flush local DNS cache**:
   ```bash
   # Windows
   ipconfig /flushdns

   # Mac
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

   # Linux
   sudo systemd-resolve --flush-caches
   ```

---

### Problem: DNS Points to Wrong IP

**Symptoms:**
- `dig yourdomain.com` returns different IP than your static IP

**Solutions:**

1. **Check static IP hasn't changed**:
   ```bash
   gcloud compute addresses describe moodle-vm-ip --region=us-central1
   ```

2. **Update DNS record** - Correct the IP in your DNS provider
3. **Remove old records** - Delete any conflicting A records pointing to old IPs
4. **Wait for propagation** - After updating, wait 15-30 minutes

---

### Problem: SSL Certificate Fails

**Symptoms:**
- `ssl-setup.sh` script fails with "Challenge failed"
- Certbot can't verify domain ownership

**Solutions:**

1. **Verify DNS is fully propagated**:
   ```bash
   dig yourdomain.com +short @8.8.8.8
   ```
   Should return your static IP. If not, wait longer.

2. **Check firewall allows HTTP**:
   ```bash
   curl -I http://yourdomain.com
   ```
   Should return HTTP 200. If timeout, check firewall rules.

3. **Verify domain points to server**:
   ```bash
   # On VM
   DOMAIN_IP=$(dig +short yourdomain.com @8.8.8.8)
   SERVER_IP=$(curl -s ifconfig.me)
   echo "Domain IP: $DOMAIN_IP"
   echo "Server IP: $SERVER_IP"
   # These should match!
   ```

4. **Check for Cloudflare proxy** - Disable orange cloud during SSL setup
5. **Check rate limits** - Let's Encrypt has rate limits (5 failures per hour per domain)

---

### Problem: WWW Not Working

**Symptoms:**
- `yourdomain.com` works but `www.yourdomain.com` doesn't (or vice versa)

**Solutions:**

1. **Add missing A record** - Ensure BOTH @ and www A records exist
2. **Check SSL certificate includes both**:
   ```bash
   # List Let's Encrypt certificates
   sudo certbot certificates

   # Should show "Domains: yourdomain.com www.yourdomain.com"
   ```

3. **Re-run SSL setup with both domains**:
   ```bash
   sudo bash /opt/moodle-deployment/ssl-setup.sh \
       "yourdomain.com www.yourdomain.com" \
       admin@yourdomain.com
   ```

---

### Problem: Cloudflare "Too Many Redirects"

**Symptoms:**
- Browser shows "ERR_TOO_MANY_REDIRECTS" or redirect loop

**Solutions:**

1. **Disable Cloudflare proxy** (orange cloud) temporarily
2. **Set SSL/TLS mode to "Full"**:
   - Cloudflare Dashboard → SSL/TLS → Overview
   - Select **Full** or **Full (strict)**
3. **Wait 5 minutes** and test again
4. **After working**, you can re-enable proxy

---

## 📚 Additional Resources

### DNS Basics
- [Google: How DNS Works](https://www.cloudflare.com/learning/dns/what-is-dns/)
- [DNS Propagation Explained](https://www.dnswatch.info/)

### Let's Encrypt Documentation
- [How Let's Encrypt Works](https://letsencrypt.org/how-it-works/)
- [Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Challenge Types](https://letsencrypt.org/docs/challenge-types/)

### Provider-Specific Guides
- [GoDaddy DNS Help](https://www.godaddy.com/help/manage-dns-records-680)
- [Cloudflare DNS Docs](https://developers.cloudflare.com/dns/)
- [Google Domains Help](https://support.google.com/domains/answer/3290350)
- [Route53 Documentation](https://docs.aws.amazon.com/route53/)

---

## 🎉 Success Checklist

Once DNS and SSL are configured, verify everything works:

- [ ] `dig yourdomain.com +short` returns your static IP
- [ ] `dig www.yourdomain.com +short` returns your static IP
- [ ] https://yourdomain.com loads with 🔒 padlock (no security warnings)
- [ ] https://www.yourdomain.com loads with 🔒 padlock
- [ ] http://yourdomain.com redirects to https://yourdomain.com
- [ ] Moodle installation wizard is accessible
- [ ] SSL certificate shows valid (click padlock → View certificate)

---

## 🚀 Next Steps After DNS/SSL Setup

1. **Complete Moodle Installation**
   - Visit https://yourdomain.com/install.php
   - Follow Moodle installation wizard

2. **Run Security Hardening**
   ```bash
   gcloud compute ssh moodle-vm --zone=us-central1-a \
       --command="sudo bash /opt/moodle-deployment/security-hardening.sh"
   ```

3. **Configure Monitoring**
   ```bash
   gcloud compute ssh moodle-vm --zone=us-central1-a \
       --command="sudo bash /opt/moodle-deployment/monitoring-setup.sh"
   ```

4. **Migrate Credentials to Secret Manager**
   ```bash
   gcloud compute ssh moodle-vm --zone=us-central1-a \
       --command="sudo bash /opt/moodle-deployment/secrets-manager-setup.sh"
   ```

5. **Configure Backups**
   - Automated backups are already configured (daily at 2 AM)
   - Test restore: `sudo bash /opt/moodle-deployment/restore-vm.sh`

6. **Update Moodle Site URL**
   - Log in as admin
   - Go to: Site administration → Server → Support contact
   - Update site URL to https://yourdomain.com

---

## 💡 Pro Tips

### Faster DNS Propagation

- Use lower TTL values (300-600 seconds) when testing
- After everything works, increase TTL to 3600+ for better caching

### Multiple Environments

For staging/testing environments, use subdomains:
- `staging.yourdomain.com` → Staging VM static IP
- `test.yourdomain.com` → Test VM static IP

### DNS Failover

For high availability, consider:
- [Cloudflare Load Balancing](https://www.cloudflare.com/load-balancing/)
- [AWS Route53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
- [Google Cloud Load Balancer](https://cloud.google.com/load-balancing)

### Security

- **Never share your static IP in public repositories**
- **Use DNS CAA records** to restrict which CAs can issue certificates:
  ```
  Type: CAA
  Name: @
  Value: 0 issue "letsencrypt.org"
  ```
- **Enable DNSSEC** if your provider supports it (prevents DNS spoofing)

---

## ❓ Still Need Help?

If you're stuck:

1. **Check deployment info file**: `cat ~/.moodle-vm-deployments/moodle-vm.txt`
2. **Check VM logs**: `gcloud compute ssh moodle-vm --command="sudo tail -100 /var/log/moodle-deployment.log"`
3. **Test DNS from multiple locations**: Use https://dnschecker.org/
4. **Verify firewall rules**: `gcloud compute firewall-rules list`
5. **Check Moodle forums**: https://moodle.org/forums/
6. **Review Google Cloud docs**: https://cloud.google.com/dns/docs

---

## 📝 Summary

DNS configuration is a critical step for production Moodle deployment:

1. ✅ **Find your static IP** from deployment info or gcloud
2. ✅ **Create A records** (@ and www) pointing to static IP
3. ✅ **Wait for propagation** (15-30 minutes typical)
4. ✅ **Verify with dig/nslookup** that DNS resolves correctly
5. ✅ **Run ssl-setup.sh** to obtain Let's Encrypt certificate
6. ✅ **Test HTTPS** access to your domain

**Remember**: Static IPs are permanent and won't change on VM restart!

---

**Generated by**: Moodle VM Deployment Package
**Last Updated**: 2025-01-17
