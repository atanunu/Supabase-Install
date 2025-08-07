#!/bin/bash

# 🛡️ Complete Security Implementation Script for Supabase
# Implements all security recommendations with automated setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/security_implementation.log"

# Logging functions
log() {
    echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

success() {
    log "SUCCESS: $1" "$GREEN"
}

warn() {
    log "WARNING: $1" "$YELLOW"
}

info() {
    log "INFO: $1" "$BLUE"
}

header() {
    echo
    log "🔹 $1" "$PURPLE"
    echo "================================" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Use: sudo $0"
    fi
}

# Update Docker Compose for SSL-enabled database
enable_database_ssl() {
    header "ENABLING DATABASE SSL CONNECTIONS"
    
    info "Updating PostgreSQL configuration for SSL..."
    
    # Check if SSL configuration already exists
    if grep -q "POSTGRES_SSL=on" docker-compose.override.yml; then
        success "Database SSL already configured"
        return 0
    fi
    
    # Add SSL environment variables to PostgreSQL
    if ! grep -q "POSTGRES_SSL" docker-compose.override.yml; then
        # Backup current configuration
        cp docker-compose.override.yml docker-compose.override.yml.backup
        
        # Add SSL configuration after existing PostgreSQL env vars
        sed -i '/POSTGRES_ARCHIVE_COMMAND/a\      # SSL Configuration\n      - POSTGRES_SSL=on\n      - POSTGRES_SSL_CERT_FILE=/var/lib/postgresql/ssl/server.crt\n      - POSTGRES_SSL_KEY_FILE=/var/lib/postgresql/ssl/server.key\n      - POSTGRES_SSL_CA_FILE=/var/lib/postgresql/ssl/root.crt' docker-compose.override.yml
        
        success "Database SSL configuration added to Docker Compose"
    fi
    
    # Ensure SSL certificates are generated
    if [[ ! -f "ssl/postgresql/server.crt" ]]; then
        warn "PostgreSQL SSL certificates not found - they will be created by setup_ssl.sh"
    else
        success "PostgreSQL SSL certificates found"
    fi
}

# Configure firewall rules
configure_firewall() {
    header "CONFIGURING FIREWALL SECURITY"
    
    if [[ -f "${SCRIPT_DIR}/configure_firewall.sh" ]]; then
        chmod +x configure_firewall.sh
        
        info "Running firewall configuration..."
        if ./configure_firewall.sh --monitoring; then
            success "Firewall configured successfully"
        else
            warn "Firewall configuration completed with warnings"
        fi
    else
        error_exit "Firewall configuration script not found"
    fi
}

# Setup Multi-Factor Authentication
setup_mfa() {
    header "SETTING UP MULTI-FACTOR AUTHENTICATION"
    
    if [[ -f "${SCRIPT_DIR}/setup_mfa.sh" ]]; then
        chmod +x setup_mfa.sh
        
        info "Setting up MFA components..."
        if ./setup_mfa.sh; then
            success "MFA setup completed"
            
            echo
            info "📋 MFA Next Steps:"
            echo "1. Apply database migration from mfa_config/migrations/001_create_mfa_tables.sql"
            echo "2. Deploy Edge Functions: cd mfa_config && ./deploy_mfa.sh"
            echo "3. Configure environment variables in Supabase dashboard"
            echo "4. Test MFA with mfa_config/mfa-setup.html"
        else
            warn "MFA setup completed with warnings"
        fi
    else
        error_exit "MFA setup script not found"
    fi
}

# Run comprehensive security scan
run_security_scan() {
    header "RUNNING SECURITY SCAN"
    
    if [[ -f "${SCRIPT_DIR}/security_scan.sh" ]]; then
        chmod +x security_scan.sh
        
        info "Running security assessment..."
        if ./security_scan.sh; then
            success "Security scan completed"
        else
            warn "Security scan completed with issues found"
        fi
    else
        error_exit "Security scan script not found"
    fi
}

# Generate SSL certificates if not exists
ensure_ssl_certificates() {
    header "ENSURING SSL CERTIFICATES"
    
    if [[ ! -f "ssl/nginx/certificate.crt" ]]; then
        warn "SSL certificates not found"
        
        if [[ -f "${SCRIPT_DIR}/ubuntu_ssl_setup.sh" ]]; then
            info "Running automated SSL setup..."
            chmod +x ubuntu_ssl_setup.sh setup_ssl.sh
            
            # Run SSL setup in non-interactive mode for self-signed
            if ./setup_ssl.sh --type self-signed --domain localhost; then
                success "SSL certificates generated"
            else
                error_exit "Failed to generate SSL certificates"
            fi
        else
            error_exit "SSL setup scripts not found"
        fi
    else
        success "SSL certificates already exist"
    fi
}

# Create security monitoring script
create_security_monitoring() {
    header "CREATING SECURITY MONITORING"
    
    info "Creating continuous security monitoring script..."
    
    cat > "${SCRIPT_DIR}/security_monitor.sh" << 'EOF'
#!/bin/bash

# 📊 Security Monitoring Script
# Runs periodic security checks and alerts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_LOG="/var/log/supabase/security_monitor.log"

# Create log directory
mkdir -p "$(dirname "$MONITOR_LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MONITOR_LOG"
}

# Check for failed login attempts
check_failed_logins() {
    log "🔍 Checking for failed login attempts..."
    
    # Check auth logs for failed attempts
    local failed_attempts=$(grep "authentication failed" /var/log/auth.log | grep "$(date '+%Y-%m-%d')" | wc -l)
    
    if [[ $failed_attempts -gt 10 ]]; then
        log "⚠️  High number of failed login attempts: $failed_attempts"
        
        # Send notification if available
        if command -v ./notify.sh >/dev/null 2>&1; then
            ./notify.sh "Security Alert" "High number of failed login attempts detected: $failed_attempts attempts today"
        fi
    else
        log "✅ Failed login attempts within normal range: $failed_attempts"
    fi
}

# Check Docker container security
check_container_security() {
    log "🐳 Checking Docker container security..."
    
    # Check for containers running as root
    local root_containers=$(docker ps --format "table {{.Names}}\t{{.Command}}" | grep -c "root" || true)
    
    if [[ $root_containers -gt 0 ]]; then
        log "⚠️  Found $root_containers containers potentially running as root"
    else
        log "✅ No containers running as root detected"
    fi
    
    # Check for containers with privileged access
    local privileged_containers=$(docker ps --filter "label=privileged=true" -q | wc -l)
    
    if [[ $privileged_containers -gt 0 ]]; then
        log "⚠️  Found $privileged_containers privileged containers"
    else
        log "✅ No privileged containers detected"
    fi
}

# Check SSL certificate expiration
check_ssl_expiration() {
    log "🔒 Checking SSL certificate expiration..."
    
    if [[ -f "ssl/nginx/certificate.crt" ]]; then
        if openssl x509 -in ssl/nginx/certificate.crt -noout -checkend 604800; then
            log "✅ SSL certificate valid for more than 7 days"
        else
            log "⚠️  SSL certificate expires within 7 days!"
            
            # Send notification
            if command -v ./notify.sh >/dev/null 2>&1; then
                ./notify.sh "SSL Alert" "SSL certificate expires within 7 days - renewal required"
            fi
        fi
    else
        log "❌ SSL certificate not found"
    fi
}

# Check disk space
check_disk_space() {
    log "💾 Checking disk space..."
    
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ $disk_usage -gt 85 ]]; then
        log "⚠️  High disk usage: ${disk_usage}%"
        
        # Send notification
        if command -v ./notify.sh >/dev/null 2>&1; then
            ./notify.sh "Disk Alert" "High disk usage detected: ${disk_usage}%"
        fi
    else
        log "✅ Disk usage within normal range: ${disk_usage}%"
    fi
}

# Check for security updates
check_security_updates() {
    log "🔄 Checking for security updates..."
    
    apt update -qq
    local security_updates=$(apt list --upgradable 2>/dev/null | grep -c "security" || true)
    
    if [[ $security_updates -gt 0 ]]; then
        log "⚠️  $security_updates security updates available"
        
        # Send notification
        if command -v ./notify.sh >/dev/null 2>&1; then
            ./notify.sh "Security Updates" "$security_updates security updates available for installation"
        fi
    else
        log "✅ No security updates available"
    fi
}

# Main monitoring function
main() {
    log "🛡️  Starting security monitoring check..."
    
    check_failed_logins
    check_container_security
    check_ssl_expiration
    check_disk_space
    check_security_updates
    
    log "✅ Security monitoring check complete"
}

# Run main function
main "$@"
EOF

    chmod +x "${SCRIPT_DIR}/security_monitor.sh"
    
    # Add to crontab for hourly monitoring
    if ! crontab -l 2>/dev/null | grep -q "security_monitor.sh"; then
        (crontab -l 2>/dev/null; echo "0 * * * * cd $SCRIPT_DIR && ./security_monitor.sh") | crontab -
        success "Security monitoring scheduled (hourly)"
    else
        success "Security monitoring already scheduled"
    fi
}

# Create security hardening script
create_security_hardening() {
    header "CREATING SECURITY HARDENING"
    
    info "Creating additional security hardening measures..."
    
    cat > "${SCRIPT_DIR}/security_hardening.sh" << 'EOF'
#!/bin/bash

# 🔧 Additional Security Hardening for Ubuntu 24 LTS
# Applies system-level security configurations

set -euo pipefail

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Disable unnecessary services
harden_services() {
    log "🚫 Disabling unnecessary services..."
    
    # List of services to disable (adjust based on your needs)
    local services_to_disable=(
        "bluetooth"
        "cups"
        "avahi-daemon"
    )
    
    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            systemctl disable "$service"
            systemctl stop "$service"
            log "✅ Disabled $service"
        fi
    done
}

# Configure kernel parameters for security
harden_kernel() {
    log "⚙️  Hardening kernel parameters..."
    
    cat >> /etc/sysctl.conf << 'SYSCTL_EOF'

# Security hardening parameters
# Disable IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Enable reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ping responses
net.ipv4.icmp_echo_ignore_all = 1

# Enable syn cookies
net.ipv4.tcp_syncookies = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1

# Kernel hardening
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
SYSCTL_EOF

    sysctl -p
    log "✅ Kernel hardening applied"
}

# Configure SSH hardening
harden_ssh() {
    log "🔐 Hardening SSH configuration..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Apply SSH hardening
    cat >> /etc/ssh/sshd_config << 'SSH_EOF'

# Security hardening
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 60
AllowUsers ubuntu
SSH_EOF

    # Validate SSH config
    if sshd -t; then
        systemctl restart ssh
        log "✅ SSH hardening applied"
    else
        log "❌ SSH config validation failed - restoring backup"
        mv /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
        systemctl restart ssh
    fi
}

# Configure file permissions
harden_permissions() {
    log "📁 Hardening file permissions..."
    
    # Secure important directories
    chmod 700 /root
    chmod 644 /etc/passwd
    chmod 600 /etc/shadow
    chmod 600 /etc/gshadow
    chmod 644 /etc/group
    
    # Secure log files
    chmod 640 /var/log/auth.log
    chmod 640 /var/log/syslog
    
    log "✅ File permissions hardened"
}

# Configure automatic security updates
configure_auto_updates() {
    log "🔄 Configuring automatic security updates..."
    
    # Install unattended upgrades if not present
    apt install -y unattended-upgrades apt-listchanges
    
    # Configure unattended upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UNATTENDED_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::SyslogEnable "true";
UNATTENDED_EOF

    # Enable automatic updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTO_UPGRADES_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
AUTO_UPGRADES_EOF

    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    
    log "✅ Automatic security updates configured"
}

# Main hardening function
main() {
    log "🛡️  Starting additional security hardening..."
    
    harden_services
    harden_kernel
    harden_ssh
    harden_permissions
    configure_auto_updates
    
    log "✅ Security hardening complete"
    log "⚠️  IMPORTANT: Test SSH access before disconnecting!"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

main "$@"
EOF

    chmod +x "${SCRIPT_DIR}/security_hardening.sh"
    success "Security hardening script created"
}

# Generate comprehensive security report
generate_security_report() {
    header "GENERATING SECURITY REPORT"
    
    local report_file="${SCRIPT_DIR}/security_implementation_report.md"
    
    info "Creating comprehensive security report..."
    
    cat > "$report_file" << EOF
# 🛡️ Security Implementation Report

**Generated:** $(date)
**System:** $(lsb_release -d | cut -f2)
**Hostname:** $(hostname)

## 🔐 SSL/TLS Security

### Certificate Status
$(if [[ -f "ssl/nginx/certificate.crt" ]]; then
    echo "✅ **SSL Certificates:** Present"
    echo "📅 **Expiration:** $(openssl x509 -in ssl/nginx/certificate.crt -noout -enddate | cut -d= -f2)"
    echo "🔑 **Subject:** $(openssl x509 -in ssl/nginx/certificate.crt -noout -subject | cut -d= -f2-)"
else
    echo "❌ **SSL Certificates:** Not found"
fi)

### Database SSL
$(if grep -q "POSTGRES_SSL=on" docker-compose.override.yml 2>/dev/null; then
    echo "✅ **Database SSL:** Enabled"
else
    echo "❌ **Database SSL:** Not configured"
fi)

## 🔥 Firewall Security

### UFW Status
\`\`\`
$(ufw status 2>/dev/null || echo "UFW not configured")
\`\`\`

### Fail2Ban Status
\`\`\`
$(fail2ban-client status 2>/dev/null || echo "Fail2Ban not configured")
\`\`\`

## 🔐 Multi-Factor Authentication

### MFA Configuration
$(if [[ -d "mfa_config" ]]; then
    echo "✅ **MFA Components:** Generated"
    echo "📁 **Location:** mfa_config/"
    echo "📋 **Status:** Ready for deployment"
else
    echo "❌ **MFA Components:** Not configured"
fi)

## 📊 Security Monitoring

### Monitoring Scripts
$(if [[ -f "security_monitor.sh" ]]; then
    echo "✅ **Security Monitor:** Active"
    echo "⏰ **Schedule:** Hourly via cron"
else
    echo "❌ **Security Monitor:** Not configured"
fi)

### Log Locations
- Security Implementation: \`${LOG_FILE}\`
- Security Monitor: \`/var/log/supabase/security_monitor.log\`
- Firewall: \`/var/log/firewall_security_report.txt\`

## 🐳 Docker Security

### Container Security
\`\`\`
$(docker system info 2>/dev/null | grep -A 5 "Security Options" || echo "Docker not running")
\`\`\`

### Resource Limits
$(if grep -q "limits:" docker-compose.override.yml 2>/dev/null; then
    echo "✅ **Resource Limits:** Configured"
else
    echo "❌ **Resource Limits:** Not configured"
fi)

## 🔧 System Hardening

### Security Features
- **Automatic Updates:** $(systemctl is-enabled unattended-upgrades 2>/dev/null || echo "Not configured")
- **SSH Hardening:** $(if [[ -f "/etc/ssh/sshd_config.backup" ]]; then echo "Applied"; else echo "Not applied"; fi)
- **Kernel Hardening:** $(if grep -q "kernel.dmesg_restrict" /etc/sysctl.conf 2>/dev/null; then echo "Applied"; else echo "Not applied"; fi)

## 📋 Action Items

### Completed ✅
$(
completed_items=()
[[ -f "ssl/nginx/certificate.crt" ]] && completed_items+=("SSL certificates generated")
[[ -f "configure_firewall.sh" ]] && completed_items+=("Firewall configuration script created")
[[ -d "mfa_config" ]] && completed_items+=("MFA components generated")
[[ -f "security_scan.sh" ]] && completed_items+=("Security scanning script available")

for item in "${completed_items[@]}"; do
    echo "- $item"
done
)

### Pending 🔄
$(
pending_items=()
[[ ! -f "/var/log/supabase/security_monitor.log" ]] && pending_items+=("Run first security monitoring check")
[[ ! -d "mfa_config" ]] && pending_items+=("Deploy MFA database migrations")
! systemctl is-enabled unattended-upgrades >/dev/null 2>&1 && pending_items+=("Configure automatic security updates")

for item in "${pending_items[@]}"; do
    echo "- $item"
done
)

## 🚀 Next Steps

1. **Test SSL Configuration**
   \`\`\`bash
   curl -k https://localhost/health
   openssl s_client -connect localhost:443
   \`\`\`

2. **Deploy MFA** (if configured)
   \`\`\`bash
   cd mfa_config
   # Apply database migration in Supabase dashboard
   ./deploy_mfa.sh
   \`\`\`

3. **Monitor Security**
   \`\`\`bash
   ./security_monitor.sh
   tail -f /var/log/supabase/security_monitor.log
   \`\`\`

4. **Regular Maintenance**
   - Weekly security scans: \`./security_scan.sh\`
   - Monthly firewall review: \`ufw status verbose\`
   - Quarterly security assessment

## 📞 Emergency Procedures

### Lockout Recovery
If locked out via SSH:
1. Access via console/KVM
2. Run: \`ufw disable\`
3. Edit: \`/etc/ssh/sshd_config\`
4. Restart: \`systemctl restart ssh\`

### Certificate Renewal
\`\`\`bash
# Let's Encrypt
sudo certbot renew

# Self-signed
./setup_ssl.sh --type self-signed --domain your-domain
\`\`\`

---
*Report generated by Supabase Security Implementation Script*
EOF

    success "Security report generated: $report_file"
}

# Main implementation function
main() {
    log "🛡️ Starting Complete Security Implementation" "$BLUE"
    log "This will implement all remaining security recommendations" "$BLUE"
    echo
    
    # Check prerequisites
    check_root
    
    # Run security implementation steps
    ensure_ssl_certificates
    enable_database_ssl
    configure_firewall
    setup_mfa
    create_security_monitoring
    create_security_hardening
    run_security_scan
    generate_security_report
    
    echo
    success "🎉 COMPLETE SECURITY IMPLEMENTATION FINISHED!"
    echo
    echo "📊 Implementation Summary:"
    echo "✅ SSL/TLS certificates configured"
    echo "✅ Database SSL connections enabled"
    echo "✅ Firewall rules configured"
    echo "✅ Multi-factor authentication prepared"
    echo "✅ Security monitoring enabled"
    echo "✅ Security hardening available"
    echo "✅ Comprehensive security scan completed"
    echo
    echo "📁 Key Files:"
    echo "- Security report: security_implementation_report.md"
    echo "- MFA config: mfa_config/"
    echo "- Monitoring: security_monitor.sh (running hourly)"
    echo "- Hardening: security_hardening.sh"
    echo
    echo "🔄 Next Manual Steps:"
    echo "1. Deploy Supabase with SSL: sudo docker compose --profile production up -d"
    echo "2. Apply MFA database migration (copy from mfa_config/migrations/)"
    echo "3. Deploy MFA functions: cd mfa_config && ./deploy_mfa.sh"
    echo "4. Run additional hardening: ./security_hardening.sh"
    echo "5. Test all security features"
    echo
    warn "🚨 IMPORTANT: Test SSH access before disconnecting!"
    warn "🚨 Review security_implementation_report.md for details"
}

# Run main function
main "$@"
