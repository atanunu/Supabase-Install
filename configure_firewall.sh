#!/bin/bash

# 🔥 Firewall Configuration Script for Ubuntu 24 LTS
# Configures UFW (Uncomplicated Firewall) for Supabase security

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log() {
    echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Use: sudo $0"
    fi
}

# Install UFW if not present
install_ufw() {
    if ! command -v ufw >/dev/null 2>&1; then
        info "Installing UFW..."
        apt update
        apt install -y ufw
    fi
    success "UFW is available"
}

# Configure basic firewall rules
configure_basic_rules() {
    info "Configuring basic firewall rules..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (critical - don't lock yourself out!)
    ufw allow ssh
    ufw allow 22/tcp
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    success "Basic rules configured"
}

# Configure application-specific rules
configure_app_rules() {
    info "Configuring application-specific rules..."
    
    # Database access (only from localhost and Docker network)
    ufw allow from 172.20.0.0/16 to any port 5432
    ufw allow from 127.0.0.1 to any port 5432
    
    # Redis (only from localhost and Docker network)
    ufw allow from 172.20.0.0/16 to any port 6379
    ufw allow from 127.0.0.1 to any port 6379
    
    success "Application rules configured"
}

# Configure monitoring rules (optional)
configure_monitoring_rules() {
    local enable_monitoring="${1:-false}"
    
    if [[ "$enable_monitoring" == "true" ]]; then
        info "Configuring monitoring access rules..."
        
        # Grafana (restrict to specific IPs if needed)
        ufw allow 3001/tcp
        
        # Prometheus (restrict to specific IPs if needed)
        ufw allow 9090/tcp
        
        success "Monitoring rules configured"
    else
        info "Monitoring rules skipped (use --monitoring to enable)"
    fi
}

# Configure admin access restrictions
configure_admin_access() {
    local admin_ips="$1"
    
    if [[ -n "$admin_ips" ]]; then
        info "Configuring admin access restrictions..."
        
        # Parse comma-separated IPs
        IFS=',' read -ra IPS <<< "$admin_ips"
        
        for ip in "${IPS[@]}"; do
            ip=$(echo "$ip" | xargs) # trim whitespace
            if [[ -n "$ip" ]]; then
                # Allow admin access to monitoring
                ufw allow from "$ip" to any port 3001 comment "Admin Grafana access"
                ufw allow from "$ip" to any port 9090 comment "Admin Prometheus access"
                
                # Allow admin SSH
                ufw allow from "$ip" to any port 22 comment "Admin SSH access"
                
                info "Added admin access for IP: $ip"
            fi
        done
        
        success "Admin access restrictions configured"
    fi
}

# Configure rate limiting using iptables
configure_rate_limiting() {
    info "Configuring rate limiting with iptables..."
    
    # Install iptables-persistent for Ubuntu
    apt install -y iptables-persistent
    
    # Rate limit SSH connections (max 3 attempts per minute)
    iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set --name SSH
    iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --rttl --name SSH -j DROP
    
    # Rate limit HTTP/HTTPS connections (max 25 per second)
    iptables -A INPUT -p tcp --dport 80 -m limit --limit 25/sec --limit-burst 100 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -m limit --limit 25/sec --limit-burst 100 -j ACCEPT
    
    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4
    
    success "Rate limiting configured"
}

# Configure fail2ban for additional protection
configure_fail2ban() {
    info "Installing and configuring Fail2Ban..."
    
    # Install fail2ban
    apt install -y fail2ban
    
    # Create custom configuration
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban time: 1 hour
bantime = 3600

# Find time: 10 minutes
findtime = 600

# Max retry attempts
maxretry = 3

# Ignore local IPs
ignoreip = 127.0.0.1/8 ::1 172.20.0.0/16

# Email notifications (configure if needed)
# destemail = admin@yourdomain.com
# sendername = Fail2Ban
# mta = sendmail

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 300
bantime = 600

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
protocol = tcp
chain = INPUT
ports = 0:65535
findtime = 86400
bantime = 604800
maxretry = 5
EOF

    # Start and enable fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    success "Fail2Ban configured and started"
}

# Configure Docker security
configure_docker_security() {
    info "Configuring Docker security settings..."
    
    # Create Docker daemon configuration
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp.json",
  "icc": false,
  "default-address-pools": [
    {
      "base": "172.20.0.0/16",
      "size": 24
    }
  ]
}
EOF

    # Download seccomp profile
    curl -fsSL https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json \
         -o /etc/docker/seccomp.json

    # Restart Docker
    systemctl restart docker
    
    success "Docker security configured"
}

# Generate security report
generate_security_report() {
    local report_file="/var/log/firewall_security_report.txt"
    
    info "Generating security report..."
    
    cat > "$report_file" << EOF
# Firewall Security Report
# Generated: $(date)

## UFW Status
$(ufw status verbose)

## Active iptables rules
$(iptables -L -n)

## Fail2Ban Status
$(fail2ban-client status)

## Open Ports
$(ss -tlnp)

## Docker Security
$(docker system info | grep -A 10 "Security Options")

## System Security
- AppArmor: $(aa-status --enabled && echo "Enabled" || echo "Disabled")
- SELinux: $(getenforce 2>/dev/null || echo "Not installed")

## Recommendations
- Regularly update fail2ban rules
- Monitor firewall logs: tail -f /var/log/ufw.log
- Check fail2ban logs: fail2ban-client status
- Review open ports monthly
- Update security patches regularly

EOF

    success "Security report generated: $report_file"
}

# Main function
main() {
    log "🔥 Starting Firewall Configuration for Supabase" "$BLUE"
    
    local monitoring=false
    local admin_ips=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --monitoring)
                monitoring=true
                shift
                ;;
            --admin-ips)
                admin_ips="$2"
                shift 2
                ;;
            --help)
                cat << EOF
Firewall Configuration Script for Supabase

Usage: sudo $0 [OPTIONS]

Options:
    --monitoring     Enable access to monitoring ports (3001, 9090)
    --admin-ips      Comma-separated list of admin IP addresses
    --help          Show this help message

Examples:
    # Basic setup
    sudo $0

    # With monitoring enabled
    sudo $0 --monitoring

    # With admin IP restrictions
    sudo $0 --monitoring --admin-ips "192.168.1.100,10.0.0.50"

EOF
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Check root privileges
    check_root
    
    # Install and configure firewall
    install_ufw
    configure_basic_rules
    configure_app_rules
    configure_monitoring_rules "$monitoring"
    configure_admin_access "$admin_ips"
    
    # Additional security measures
    configure_rate_limiting
    configure_fail2ban
    configure_docker_security
    
    # Enable UFW
    info "Enabling UFW firewall..."
    ufw --force enable
    
    # Generate report
    generate_security_report
    
    # Final status
    echo
    success "🔥 Firewall configuration complete!"
    echo
    echo "📊 Current UFW Status:"
    ufw status verbose
    echo
    echo "📋 Security Features Enabled:"
    echo "✅ UFW firewall with restrictive rules"
    echo "✅ Rate limiting for SSH, HTTP, HTTPS"
    echo "✅ Fail2Ban for intrusion detection"
    echo "✅ Docker security hardening"
    echo "✅ Application-specific port restrictions"
    echo
    echo "📁 Security report: /var/log/firewall_security_report.txt"
    echo
    warn "IMPORTANT: Test SSH access before disconnecting!"
    echo "If locked out, access via console and run: ufw disable"
}

# Run main function
main "$@"
