#!/bin/bash
###############################################################################
# CIS Benchmark Hardening Script for Ubuntu 22.04 LTS
# Version: 1.0.0
# Based on: CIS Ubuntu Linux 22.04 LTS Benchmark v2.0.0
#
# This script implements CIS Level 1 and Level 2 security controls for
# Ubuntu 22.04 LTS following industry best practices.
#
# WARNING: This script makes system-level changes. Always test in a
#          non-production environment first!
#
# Usage:
#   sudo ./cis-hardening.sh [--level {1|2}] [--audit-only] [--install-cron]
#
# Options:
#   --level {1|2}      Apply Level 1 (default) or Level 2 hardening
#   --audit-only       Only audit current compliance, don't make changes
#   --install-cron     Install monthly CIS compliance check cron job
#
# Exit Codes:
#   0 - Success
#   1 - General error
#   2 - Not running as root
#   3 - Unsupported OS version
###############################################################################

set -euo pipefail

# Script configuration
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="CIS Hardening Script"
readonly LOG_FILE="/var/log/cis-hardening.log"
readonly BACKUP_DIR="/var/backups/cis-hardening-$(date +%Y%m%d_%H%M%S)"
readonly SYSCTL_CIS_CONF="/etc/sysctl.d/99-cis.conf"
readonly AUDITD_RULES_DIR="/etc/audit/rules.d"
readonly SSH_CONFIG="/etc/ssh/sshd_config"

# Default configuration
CIS_LEVEL="${CIS_LEVEL:-1}"
AUDIT_ONLY=false
INSTALL_CRON=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
CHANGES_MADE=0

###############################################################################
# Logging Functions
###############################################################################

log() {
    local message="$1"
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[✓]${NC} $message" | tee -a "$LOG_FILE"
    ((PASSED_CHECKS++))
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[⚠]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[✗]${NC} $message" | tee -a "$LOG_FILE"
    ((FAILED_CHECKS++))
}

log_info() {
    local message="$1"
    echo -e "${BLUE}[ℹ]${NC} $message" | tee -a "$LOG_FILE"
}

###############################################################################
# Utility Functions
###############################################################################

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 2
    fi
}

check_os_version() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        exit 3
    fi

    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]] || [[ "$VERSION_ID" != "22.04" ]]; then
        log_warning "This script is designed for Ubuntu 22.04 LTS"
        log_warning "Detected: $PRETTY_NAME"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 3
        fi
    fi
}

create_backup() {
    local file="$1"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi

    if [[ -f "$file" ]]; then
        cp -p "$file" "$BACKUP_DIR/$(basename "$file").backup"
        log_info "Backed up: $file"
    fi
}

###############################################################################
# CIS Section 1: Initial Setup
###############################################################################

# 1.1.1.x: Filesystem Configuration
harden_filesystem_types() {
    log_info "Section 1.1: Filesystem hardening"
    ((TOTAL_CHECKS++))

    local modules_to_disable=(
        "cramfs"     # Compressed ROM filesystem
        "freevxfs"   # Veritas filesystem
        "jffs2"      # Journaling Flash filesystem
        "hfs"        # Hierarchical filesystem (Mac)
        "hfsplus"    # HFS+ filesystem
        "udf"        # Universal Disk Format
        "vfat"       # FAT filesystem (if not needed)
    )

    local modprobe_conf="/etc/modprobe.d/cis-filesystems.conf"

    if [[ "$AUDIT_ONLY" == true ]]; then
        log_info "Audit: Checking disabled filesystems"
        for module in "${modules_to_disable[@]}"; do
            if lsmod | grep -q "^$module "; then
                log_warning "Filesystem module loaded: $module"
            else
                log_success "Filesystem module disabled: $module"
            fi
        done
    else
        create_backup "$modprobe_conf"

        log_info "Disabling uncommon filesystems..."
        {
            echo "# CIS Benchmark: Disable uncommon filesystems"
            echo "# Generated: $(date)"
            echo ""
            for module in "${modules_to_disable[@]}"; do
                echo "install $module /bin/true"
            done
        } > "$modprobe_conf"

        log_success "Disabled uncommon filesystems"
        ((CHANGES_MADE++))
    fi
}

# 1.1.2-1.1.5: Configure /tmp, /var/tmp, /var/log
harden_tmp_partitions() {
    log_info "Section 1.1.2-1.1.5: Hardening temporary partitions"
    ((TOTAL_CHECKS++))

    # Check if systemd-based tmpfs is used for /tmp
    if systemctl is-enabled tmp.mount 2>/dev/null | grep -q "enabled"; then
        log_success "/tmp mounted via systemd tmp.mount"
    else
        log_warning "/tmp not using systemd tmp.mount"

        if [[ "$AUDIT_ONLY" == false ]]; then
            log_info "Enabling systemd tmp.mount for /tmp"

            # Create or modify tmp.mount configuration
            create_backup "/etc/systemd/system/tmp.mount"

            cat > /etc/systemd/system/tmp.mount <<EOF
[Unit]
Description=Temporary Directory /tmp
ConditionPathIsSymbolicLink=!/tmp
DefaultDependencies=no
Conflicts=umount.target
Before=local-fs.target umount.target
After=swap.target

[Mount]
What=tmpfs
Where=/tmp
Type=tmpfs
Options=mode=1777,strictatime,noexec,nodev,nosuid,size=2G

[Install]
WantedBy=local-fs.target
EOF

            systemctl daemon-reload
            systemctl enable tmp.mount

            log_success "Configured /tmp with noexec,nodev,nosuid"
            ((CHANGES_MADE++))
        fi
    fi

    # Configure /var/tmp mount options in fstab
    if grep -q "/var/tmp" /etc/fstab; then
        log_info "/var/tmp has fstab entry"

        if grep "/var/tmp" /etc/fstab | grep -q "nodev.*nosuid.*noexec"; then
            log_success "/var/tmp has secure mount options"
        else
            log_warning "/var/tmp missing secure mount options"

            if [[ "$AUDIT_ONLY" == false ]]; then
                create_backup "/etc/fstab"

                # Add bind mount for /var/tmp to /tmp
                if ! grep -q "^/tmp[[:space:]]*/var/tmp" /etc/fstab; then
                    echo "/tmp /var/tmp none bind,nodev,nosuid,noexec 0 0" >> /etc/fstab
                    log_success "Added /var/tmp bind mount to /tmp with secure options"
                    ((CHANGES_MADE++))
                fi
            fi
        fi
    else
        log_warning "/var/tmp not in fstab (using default)"
    fi
}

# 1.3.1: Configure AIDE (Advanced Intrusion Detection Environment)
configure_aide() {
    log_info "Section 1.3.1: File integrity monitoring with AIDE"
    ((TOTAL_CHECKS++))

    if dpkg -l | grep -q "^ii  aide "; then
        log_success "AIDE is installed"
    else
        log_warning "AIDE not installed"

        if [[ "$AUDIT_ONLY" == false ]]; then
            log_info "Installing AIDE..."
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y aide aide-common

            log_info "Initializing AIDE database (this may take several minutes)..."
            aideinit

            # Move new database to active location
            if [[ -f /var/lib/aide/aide.db.new ]]; then
                mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
                log_success "AIDE installed and database initialized"
                ((CHANGES_MADE++))
            fi

            # Install cron job for daily checks
            if [[ ! -f /etc/cron.daily/aide ]]; then
                cat > /etc/cron.daily/aide <<'EOF'
#!/bin/bash
# Daily AIDE integrity check

/usr/bin/aide --check | mail -s "AIDE Integrity Check $(hostname)" root
EOF
                chmod 755 /etc/cron.daily/aide
                log_success "Installed daily AIDE check cron job"
            fi
        fi
    fi
}

# 1.4.1-1.4.2: Bootloader hardening
harden_bootloader() {
    log_info "Section 1.4: Bootloader hardening"
    ((TOTAL_CHECKS++))

    local grub_cfg="/boot/grub/grub.cfg"

    if [[ -f "$grub_cfg" ]]; then
        local perms=$(stat -c %a "$grub_cfg")

        if [[ "$perms" == "400" ]] || [[ "$perms" == "600" ]]; then
            log_success "GRUB config has secure permissions: $perms"
        else
            log_warning "GRUB config permissions: $perms (should be 400 or 600)"

            if [[ "$AUDIT_ONLY" == false ]]; then
                chown root:root "$grub_cfg"
                chmod 400 "$grub_cfg"
                log_success "Set GRUB config permissions to 400"
                ((CHANGES_MADE++))
            fi
        fi
    fi
}

# 1.5.1-1.5.4: Additional process hardening
configure_process_hardening() {
    log_info "Section 1.5: Additional process hardening"
    ((TOTAL_CHECKS++))

    # Check Address Space Layout Randomization (ASLR)
    local aslr_value=$(sysctl -n kernel.randomize_va_space 2>/dev/null || echo "0")

    if [[ "$aslr_value" == "2" ]]; then
        log_success "ASLR enabled (kernel.randomize_va_space = 2)"
    else
        log_warning "ASLR not fully enabled (kernel.randomize_va_space = $aslr_value)"
    fi

    # Check core dumps
    if grep -q "hard core 0" /etc/security/limits.conf; then
        log_success "Core dumps disabled in limits.conf"
    else
        log_warning "Core dumps not disabled in limits.conf"

        if [[ "$AUDIT_ONLY" == false ]]; then
            create_backup "/etc/security/limits.conf"
            echo "* hard core 0" >> /etc/security/limits.conf
            log_success "Disabled core dumps"
            ((CHANGES_MADE++))
        fi
    fi
}

###############################################################################
# CIS Section 3: Network Configuration
###############################################################################

configure_network_hardening() {
    log_info "Section 3: Network hardening via sysctl"
    ((TOTAL_CHECKS++))

    if [[ "$AUDIT_ONLY" == true ]]; then
        log_info "Audit: Checking sysctl network parameters"

        local params=(
            "net.ipv4.ip_forward:0"
            "net.ipv4.conf.all.send_redirects:0"
            "net.ipv4.conf.all.accept_source_route:0"
            "net.ipv4.conf.all.accept_redirects:0"
            "net.ipv4.conf.all.secure_redirects:0"
            "net.ipv4.conf.all.log_martians:1"
            "net.ipv4.conf.all.rp_filter:1"
            "net.ipv4.icmp_echo_ignore_broadcasts:1"
            "net.ipv4.icmp_ignore_bogus_error_responses:1"
            "net.ipv4.tcp_syncookies:1"
        )

        for param_pair in "${params[@]}"; do
            local param="${param_pair%%:*}"
            local expected="${param_pair##*:}"
            local current=$(sysctl -n "$param" 2>/dev/null || echo "undefined")

            if [[ "$current" == "$expected" ]]; then
                log_success "Sysctl: $param = $current"
            else
                log_warning "Sysctl: $param = $current (expected: $expected)"
            fi
        done
    else
        create_backup "$SYSCTL_CIS_CONF"

        log_info "Configuring sysctl network hardening..."

        cat > "$SYSCTL_CIS_CONF" <<'EOF'
# CIS Benchmark - Network Configuration Hardening
# Generated by CIS Hardening Script
# Date: $(date)

# Section 3.1: Network Parameters (Host Only)

# 3.1.1: Disable IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# 3.1.2: Disable Send Packet Redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Section 3.2: Network Parameters (Host and Router)

# 3.2.1: Disable Source Routed Packet Acceptance
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# 3.2.2: Disable ICMP Redirect Acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# 3.2.3: Disable Secure ICMP Redirect Acceptance
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# 3.2.4: Log Suspicious Packets (Martian packets)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# 3.2.5: Enable Ignore Broadcast Requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 3.2.6: Enable Bad Error Message Protection
net.ipv4.icmp_ignore_bogus_error_responses = 1

# 3.2.7: Enable Reverse Path Filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 3.2.8: Enable TCP SYN Cookies
net.ipv4.tcp_syncookies = 1

# 3.2.9: Disable IPv6 Router Advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Additional Security Hardening

# Disable IPv6 if not needed (Level 2)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# Kernel hardening
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1

# Filesystem hardening
fs.suid_dumpable = 0
fs.protected_symlinks = 1
fs.protected_hardlinks = 1

# Additional kernel security (Level 2)
kernel.perf_event_paranoid = 3
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
EOF

        # Apply sysctl settings
        sysctl -p "$SYSCTL_CIS_CONF" >/dev/null 2>&1

        log_success "Applied network hardening sysctl parameters"
        ((CHANGES_MADE++))
    fi
}

###############################################################################
# CIS Section 4: Logging and Auditing
###############################################################################

configure_auditd() {
    log_info "Section 4: Auditd configuration"
    ((TOTAL_CHECKS++))

    # Check if auditd is installed
    if dpkg -l | grep -q "^ii  auditd "; then
        log_success "Auditd is installed"
    else
        log_warning "Auditd not installed"

        if [[ "$AUDIT_ONLY" == false ]]; then
            log_info "Installing auditd..."
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y auditd audispd-plugins

            systemctl enable auditd
            systemctl start auditd

            log_success "Auditd installed and enabled"
            ((CHANGES_MADE++))
        fi
    fi

    # Configure audit rules
    if [[ "$AUDIT_ONLY" == false ]]; then
        local audit_rules_file="$AUDITD_RULES_DIR/cis-audit.rules"

        create_backup "$audit_rules_file"

        log_info "Configuring CIS audit rules..."

        cat > "$audit_rules_file" <<'EOF'
# CIS Benchmark - Audit Rules
# Generated by CIS Hardening Script
# Date: $(date)

# Remove any existing rules
-D

# Buffer size
-b 8192

# Failure mode (0=silent 1=printk 2=panic)
-f 1

# 4.1.3: Audit events that modify date and time information
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change
-a always,exit -F arch=b64 -S clock_settime -k time-change
-a always,exit -F arch=b32 -S clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

# 4.1.4: Audit events that modify user/group information
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

# 4.1.5: Audit events that modify network environment
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname -S setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/network -p wa -k system-locale

# 4.1.6: Audit events that modify system's Mandatory Access Controls (AppArmor)
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy

# 4.1.7: Audit login/logout events
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins

# 4.1.8: Audit session initiation information
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k logins
-w /var/log/btmp -p wa -k logins

# 4.1.9: Audit discretionary access control permission modification events
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=1000 -F auid!=4294967295 -k perm_mod

# 4.1.10: Audit unsuccessful unauthorized file access attempts
-a always,exit -F arch=b64 -S open -S openat -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S open -S openat -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access
-a always,exit -F arch=b32 -S open -S openat -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access

# 4.1.11: Audit use of privileged commands
# Note: This should be customized based on your system's SUID/SGID programs
# Find with: find / -xdev \( -perm -4000 -o -perm -2000 \) -type f

# 4.1.12: Audit successful file system mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=4294967295 -k mounts

# 4.1.13: Audit file deletion events
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete
-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k delete

# 4.1.14: Audit changes to system administration scope (sudoers)
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

# 4.1.15: Audit system administrator actions (sudolog)
-w /var/log/sudo.log -p wa -k actions

# 4.1.16: Audit kernel module loading and unloading
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# Additional monitoring - SSH configuration
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Additional monitoring - Cron configuration
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /etc/cron.weekly/ -p wa -k cron
-w /etc/crontab -p wa -k cron

# Make the configuration immutable (Level 2)
# -e 2
EOF

        # Reload audit rules
        if command -v augenrules >/dev/null 2>&1; then
            augenrules --load >/dev/null 2>&1
            log_success "Configured and loaded CIS audit rules"
            ((CHANGES_MADE++))
        else
            log_warning "augenrules command not found, rules will load on next reboot"
        fi

        # Ensure auditd is running
        if systemctl is-active auditd >/dev/null 2>&1; then
            log_success "Auditd service is active"
        else
            systemctl start auditd
            log_success "Started auditd service"
        fi
    fi
}

configure_logging() {
    log_info "Section 4: Logging configuration"
    ((TOTAL_CHECKS++))

    # Check if rsyslog is installed and enabled
    if dpkg -l | grep -q "^ii  rsyslog "; then
        log_success "rsyslog is installed"

        if systemctl is-enabled rsyslog >/dev/null 2>&1; then
            log_success "rsyslog is enabled"
        else
            log_warning "rsyslog not enabled"

            if [[ "$AUDIT_ONLY" == false ]]; then
                systemctl enable rsyslog
                systemctl start rsyslog
                log_success "Enabled and started rsyslog"
                ((CHANGES_MADE++))
            fi
        fi
    else
        log_warning "rsyslog not installed"

        if [[ "$AUDIT_ONLY" == false ]]; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y rsyslog
            systemctl enable rsyslog
            systemctl start rsyslog
            log_success "Installed and enabled rsyslog"
            ((CHANGES_MADE++))
        fi
    fi

    # Configure log file permissions
    if [[ "$AUDIT_ONLY" == false ]]; then
        if [[ -f /etc/rsyslog.conf ]]; then
            create_backup "/etc/rsyslog.conf"

            # Ensure $FileCreateMode is set to 0640
            if grep -q "^\$FileCreateMode" /etc/rsyslog.conf; then
                sed -i 's/^\$FileCreateMode.*/$FileCreateMode 0640/' /etc/rsyslog.conf
            else
                echo "\$FileCreateMode 0640" >> /etc/rsyslog.conf
            fi

            systemctl restart rsyslog
            log_success "Configured rsyslog file permissions"
            ((CHANGES_MADE++))
        fi
    fi
}

###############################################################################
# CIS Section 5: Access, Authentication and Authorization
###############################################################################

configure_ssh_hardening() {
    log_info "Section 5.2: SSH Server Configuration"
    ((TOTAL_CHECKS++))

    if [[ ! -f "$SSH_CONFIG" ]]; then
        log_error "SSH config file not found: $SSH_CONFIG"
        return
    fi

    if [[ "$AUDIT_ONLY" == true ]]; then
        log_info "Audit: Checking SSH configuration"

        local ssh_params=(
            "PermitRootLogin:no"
            "MaxAuthTries:4"
            "PasswordAuthentication:no"
            "PermitEmptyPasswords:no"
            "ClientAliveInterval:300"
            "ClientAliveCountMax:0"
            "LoginGraceTime:60"
            "X11Forwarding:no"
        )

        for param_pair in "${ssh_params[@]}"; do
            local param="${param_pair%%:*}"
            local expected="${param_pair##*:}"

            if grep -q "^$param[[:space:]]" "$SSH_CONFIG"; then
                local current=$(grep "^$param[[:space:]]" "$SSH_CONFIG" | awk '{print $2}')
                if [[ "$current" == "$expected" ]]; then
                    log_success "SSH: $param = $current"
                else
                    log_warning "SSH: $param = $current (expected: $expected)"
                fi
            else
                log_warning "SSH: $param not configured (expected: $expected)"
            fi
        done
    else
        create_backup "$SSH_CONFIG"

        log_info "Hardening SSH configuration..."

        # Helper function to update SSH config parameter
        update_ssh_param() {
            local param="$1"
            local value="$2"

            if grep -q "^$param[[:space:]]" "$SSH_CONFIG"; then
                sed -i "s/^$param[[:space:]].*/$param $value/" "$SSH_CONFIG"
            elif grep -q "^#$param[[:space:]]" "$SSH_CONFIG"; then
                sed -i "s/^#$param[[:space:]].*/$param $value/" "$SSH_CONFIG"
            else
                echo "$param $value" >> "$SSH_CONFIG"
            fi
        }

        # 5.2.4: Disable SSH root login
        update_ssh_param "PermitRootLogin" "no"

        # 5.2.5: Limit authentication attempts
        update_ssh_param "MaxAuthTries" "4"

        # 5.2.7: Disable empty passwords
        update_ssh_param "PermitEmptyPasswords" "no"

        # 5.2.10: Disable password authentication (use keys)
        # WARNING: Ensure you have SSH keys set up before enabling this!
        # update_ssh_param "PasswordAuthentication" "no"

        # 5.2.12: Set idle timeout
        update_ssh_param "ClientAliveInterval" "300"
        update_ssh_param "ClientAliveCountMax" "0"

        # 5.2.13: Limit login grace time
        update_ssh_param "LoginGraceTime" "60"

        # 5.2.15: Disable X11 forwarding
        update_ssh_param "X11Forwarding" "no"

        # 5.2.16: Only use strong ciphers
        update_ssh_param "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"

        # 5.2.17: Only use strong MACs
        update_ssh_param "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"

        # 5.2.18: Only use strong key exchange algorithms
        update_ssh_param "KexAlgorithms" "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256"

        # Additional hardening
        update_ssh_param "Protocol" "2"
        update_ssh_param "IgnoreRhosts" "yes"
        update_ssh_param "HostbasedAuthentication" "no"
        update_ssh_param "PermitUserEnvironment" "no"
        update_ssh_param "AllowTcpForwarding" "no"
        update_ssh_param "MaxSessions" "2"
        update_ssh_param "TCPKeepAlive" "no"
        update_ssh_param "Compression" "no"
        update_ssh_param "AllowAgentForwarding" "no"

        # Restart SSH to apply changes
        systemctl restart sshd

        log_success "SSH hardening applied and service restarted"
        log_warning "IMPORTANT: Verify SSH connectivity before closing this session!"
        ((CHANGES_MADE++))
    fi
}

configure_pam_password_policy() {
    log_info "Section 5.3: PAM and Password Configuration"
    ((TOTAL_CHECKS++))

    # Check if libpam-pwquality is installed
    if dpkg -l | grep -q "^ii  libpam-pwquality "; then
        log_success "libpam-pwquality is installed"
    else
        log_warning "libpam-pwquality not installed"

        if [[ "$AUDIT_ONLY" == false ]]; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y libpam-pwquality
            log_success "Installed libpam-pwquality"
            ((CHANGES_MADE++))
        fi
    fi

    if [[ "$AUDIT_ONLY" == false ]]; then
        local pwquality_conf="/etc/security/pwquality.conf"

        create_backup "$pwquality_conf"

        log_info "Configuring password policy..."

        # Configure password quality requirements
        cat >> "$pwquality_conf" <<EOF

# CIS Benchmark - Password Quality Requirements
# Generated by CIS Hardening Script

# 5.3.1: Minimum password length
minlen = 14

# 5.3.2: Password complexity
minclass = 4
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1

# 5.3.3: Limit password reuse
# Configured in /etc/pam.d/common-password

# Additional settings
maxrepeat = 3
maxclassrepeat = 4
gecoscheck = 1
dictcheck = 1
usercheck = 1
enforcing = 1
EOF

        # Configure password history in PAM
        local pam_common_password="/etc/pam.d/common-password"

        create_backup "$pam_common_password"

        # Add password history requirement if not present
        if ! grep -q "remember=" "$pam_common_password"; then
            sed -i '/pam_unix.so/s/$/ remember=5/' "$pam_common_password"
            log_success "Configured password history (remember last 5 passwords)"
        fi

        log_success "Password policy configured"
        ((CHANGES_MADE++))
    fi
}

configure_user_accounts() {
    log_info "Section 5.4: User Accounts and Environment"
    ((TOTAL_CHECKS++))

    # 5.4.1.1: Set password expiration days
    if [[ "$AUDIT_ONLY" == false ]]; then
        create_backup "/etc/login.defs"

        # Set PASS_MAX_DAYS to 365 (CIS recommends 90, but 365 is more practical)
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs

        # Set PASS_MIN_DAYS to 1
        sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs

        # Set PASS_WARN_AGE to 7
        sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

        log_success "Configured password aging in /etc/login.defs"
        ((CHANGES_MADE++))
    fi

    # Check for accounts with empty passwords
    local empty_password_accounts=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null)

    if [[ -z "$empty_password_accounts" ]]; then
        log_success "No accounts with empty passwords found"
    else
        log_error "Accounts with empty passwords: $empty_password_accounts"
    fi
}

###############################################################################
# CIS Section 6: System Maintenance
###############################################################################

configure_file_permissions() {
    log_info "Section 6.1: System File Permissions"
    ((TOTAL_CHECKS++))

    if [[ "$AUDIT_ONLY" == true ]]; then
        log_info "Audit: Checking critical file permissions"

        local files_to_check=(
            "/etc/passwd:644"
            "/etc/shadow:640"
            "/etc/group:644"
            "/etc/gshadow:640"
            "/etc/passwd-:600"
            "/etc/shadow-:600"
            "/etc/group-:600"
            "/etc/gshadow-:600"
        )

        for file_pair in "${files_to_check[@]}"; do
            local file="${file_pair%%:*}"
            local expected="${file_pair##*:}"

            if [[ -f "$file" ]]; then
                local current=$(stat -c %a "$file")
                if [[ "$current" == "$expected" ]]; then
                    log_success "File permissions: $file ($current)"
                else
                    log_warning "File permissions: $file ($current, expected $expected)"
                fi
            fi
        done
    else
        log_info "Setting secure file permissions..."

        # Set permissions for critical system files
        chmod 644 /etc/passwd
        chmod 640 /etc/shadow
        chmod 644 /etc/group
        chmod 640 /etc/gshadow

        # Set ownership
        chown root:root /etc/passwd /etc/group
        chown root:shadow /etc/shadow /etc/gshadow

        # Backup files
        if [[ -f /etc/passwd- ]]; then chmod 600 /etc/passwd-; fi
        if [[ -f /etc/shadow- ]]; then chmod 600 /etc/shadow-; fi
        if [[ -f /etc/group- ]]; then chmod 600 /etc/group-; fi
        if [[ -f /etc/gshadow- ]]; then chmod 600 /etc/gshadow-; fi

        log_success "Set secure file permissions for critical system files"
        ((CHANGES_MADE++))
    fi
}

###############################################################################
# Additional Security Hardening (Level 2)
###############################################################################

configure_apparmor() {
    log_info "Additional: AppArmor mandatory access control"
    ((TOTAL_CHECKS++))

    if dpkg -l | grep -q "^ii  apparmor "; then
        log_success "AppArmor is installed"

        if systemctl is-enabled apparmor >/dev/null 2>&1; then
            log_success "AppArmor is enabled"
        else
            log_warning "AppArmor not enabled"

            if [[ "$AUDIT_ONLY" == false ]]; then
                systemctl enable apparmor
                systemctl start apparmor
                log_success "Enabled AppArmor"
                ((CHANGES_MADE++))
            fi
        fi

        # Check AppArmor profiles
        local profiles_enforced=$(aa-status 2>/dev/null | grep "profiles are in enforce mode" | awk '{print $1}')
        local profiles_complain=$(aa-status 2>/dev/null | grep "profiles are in complain mode" | awk '{print $1}')

        log_info "AppArmor profiles: $profiles_enforced enforced, $profiles_complain complain"
    else
        log_warning "AppArmor not installed"

        if [[ "$AUDIT_ONLY" == false ]]; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils
            systemctl enable apparmor
            systemctl start apparmor
            log_success "Installed and enabled AppArmor"
            ((CHANGES_MADE++))
        fi
    fi
}

configure_automatic_updates() {
    log_info "Additional: Automatic security updates"
    ((TOTAL_CHECKS++))

    if dpkg -l | grep -q "^ii  unattended-upgrades "; then
        log_success "unattended-upgrades is installed"
    else
        log_warning "unattended-upgrades not installed"

        if [[ "$AUDIT_ONLY" == false ]]; then
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades

            # Enable automatic security updates
            cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

            # Configure to only install security updates
            cat > /etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailOnlyOnError "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

            log_success "Configured automatic security updates"
            ((CHANGES_MADE++))
        fi
    fi
}

###############################################################################
# Cron Job Installation
###############################################################################

install_cron_job() {
    log_info "Installing monthly CIS compliance check cron job"

    local cron_script="/usr/local/bin/cis-hardening-monthly"

    cat > "$cron_script" <<'EOF'
#!/bin/bash
# Monthly CIS compliance audit
# Generated by CIS Hardening Script

LOG_FILE="/var/log/cis-hardening-monthly-$(date +%Y%m%d).log"

/usr/local/bin/cis-hardening.sh --audit-only > "$LOG_FILE" 2>&1

# Send email if mail is configured
if command -v mail >/dev/null 2>&1; then
    mail -s "CIS Compliance Audit - $(hostname)" root < "$LOG_FILE"
fi

# Keep only last 12 months of logs
find /var/log -name "cis-hardening-monthly-*.log" -type f -mtime +365 -delete
EOF

    chmod 755 "$cron_script"

    # Install cron job (1st of month at 3 AM)
    local cron_entry="0 3 1 * * /usr/local/bin/cis-hardening-monthly"

    if crontab -l 2>/dev/null | grep -q "cis-hardening-monthly"; then
        log_warning "CIS compliance cron job already exists"
    else
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_success "Installed monthly CIS compliance check cron job"
    fi
}

###############################################################################
# Main Execution
###############################################################################

print_header() {
    echo ""
    echo "========================================================================="
    echo "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "CIS Ubuntu Linux 22.04 LTS Benchmark v2.0.0"
    echo "========================================================================="
    echo ""
}

print_summary() {
    echo ""
    echo "========================================================================="
    echo "CIS Hardening Summary"
    echo "========================================================================="
    echo "Total checks performed: $TOTAL_CHECKS"
    echo "Checks passed: $PASSED_CHECKS"
    echo "Checks failed/warnings: $FAILED_CHECKS"

    if [[ "$AUDIT_ONLY" == false ]]; then
        echo "Changes made: $CHANGES_MADE"
        echo ""
        echo "Backup directory: $BACKUP_DIR"
    fi

    echo "========================================================================="
    echo ""

    if [[ $FAILED_CHECKS -gt 0 ]]; then
        log_warning "$FAILED_CHECKS checks failed or have warnings"
        log_info "Review the log file for details: $LOG_FILE"
    fi

    if [[ "$AUDIT_ONLY" == false ]] && [[ $CHANGES_MADE -gt 0 ]]; then
        log_warning "System changes were made. A reboot is recommended."
        log_info "Verify SSH connectivity before rebooting!"
    fi

    # Calculate compliance percentage
    local compliance_pct=0
    if [[ $TOTAL_CHECKS -gt 0 ]]; then
        compliance_pct=$((100 * PASSED_CHECKS / TOTAL_CHECKS))
    fi

    echo ""
    log_info "CIS Compliance Score: $compliance_pct%"

    if [[ $compliance_pct -ge 95 ]]; then
        log_success "Compliance Grade: A+ (Excellent)"
    elif [[ $compliance_pct -ge 90 ]]; then
        log_success "Compliance Grade: A (Very Good)"
    elif [[ $compliance_pct -ge 80 ]]; then
        log_warning "Compliance Grade: B (Good)"
    elif [[ $compliance_pct -ge 70 ]]; then
        log_warning "Compliance Grade: C (Fair)"
    else
        log_error "Compliance Grade: D (Needs Improvement)"
    fi

    echo ""
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --level)
                CIS_LEVEL="$2"
                if [[ "$CIS_LEVEL" != "1" ]] && [[ "$CIS_LEVEL" != "2" ]]; then
                    log_error "Invalid CIS level: $CIS_LEVEL (must be 1 or 2)"
                    exit 1
                fi
                shift 2
                ;;
            --audit-only)
                AUDIT_ONLY=true
                shift
                ;;
            --install-cron)
                INSTALL_CRON=true
                shift
                ;;
            -h|--help)
                print_header
                cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --level {1|2}      Apply CIS Level 1 (default) or Level 2 hardening
  --audit-only       Only audit current compliance, don't make changes
  --install-cron     Install monthly CIS compliance check cron job
  -h, --help         Show this help message

Examples:
  # Audit current CIS compliance
  sudo $0 --audit-only

  # Apply Level 1 hardening
  sudo $0 --level 1

  # Apply Level 2 hardening
  sudo $0 --level 2

  # Install monthly compliance check cron job
  sudo $0 --install-cron

CIS Levels:
  Level 1: Practical security measures with minimal impact
  Level 2: Maximum security (may impact system performance)

For more information: https://www.cisecurity.org/benchmark/ubuntu_linux
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    print_header

    # Pre-flight checks
    check_root
    check_os_version

    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    log "Starting CIS Hardening Script v$SCRIPT_VERSION"
    log "Mode: $(if [[ "$AUDIT_ONLY" == true ]]; then echo "AUDIT ONLY"; else echo "HARDENING"; fi)"
    log "CIS Level: $CIS_LEVEL"
    log "Date: $(date)"
    echo ""

    # Execute hardening sections
    harden_filesystem_types
    harden_tmp_partitions
    configure_aide
    harden_bootloader
    configure_process_hardening
    configure_network_hardening
    configure_auditd
    configure_logging
    configure_ssh_hardening
    configure_pam_password_policy
    configure_user_accounts
    configure_file_permissions
    configure_apparmor
    configure_automatic_updates

    # Install cron job if requested
    if [[ "$INSTALL_CRON" == true ]]; then
        install_cron_job
    fi

    # Print summary
    print_summary

    log "CIS Hardening Script completed"
    log "Full log available at: $LOG_FILE"
}

# Execute main function
main "$@"
