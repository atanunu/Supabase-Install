#!/bin/bash

# ============================================================================
# SERVER PREPARATION SCRIPT FOR SUPABASE ENTERPRISE
# Prepares production server for Supabase deployment
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/supabase-server-prep.log"
DOCKER_VERSION="24.0.0"
DOCKER_COMPOSE_VERSION="2.20.0"

# Default values
INSTALL_DOCKER="true"
INSTALL_DOCKER_COMPOSE="true"
SETUP_FIREWALL="true"
CREATE_DIRECTORIES="true"
SETUP_SSL="false"
DOMAIN_NAME=""
EMAIL=""

# Print functions
print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
SERVER PREPARATION SCRIPT FOR SUPABASE ENTERPRISE

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --no-docker              Skip Docker installation
    --no-compose             Skip Docker Compose installation
    --no-firewall           Skip firewall configuration
    --no-directories        Skip directory creation
    --setup-ssl             Setup SSL certificates with Let's Encrypt
    --domain <DOMAIN>       Domain name for SSL certificate
    --email <EMAIL>         Email for SSL certificate registration
    --help                  Show this help message

EXAMPLES:
    # Basic server preparation
    $0

    # Full setup with SSL
    $0 --setup-ssl --domain myapp.example.com --email admin@example.com

    # Minimal setup without firewall
    $0 --no-firewall

REQUIREMENTS:
    - Ubuntu 20.04+ or CentOS 8+ or similar Linux distribution
    - Root or sudo access
    - Internet connection for package downloads

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-docker)
                INSTALL_DOCKER="false"
                shift
                ;;
            --no-compose)
                INSTALL_DOCKER_COMPOSE="false"
                shift
                ;;
            --no-firewall)
                SETUP_FIREWALL="false"
                shift
                ;;
            --no-directories)
                CREATE_DIRECTORIES="false"
                shift
                ;;
            --setup-ssl)
                SETUP_SSL="true"
                shift
                ;;
            --domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    # Validate SSL setup requirements
    if [[ "$SETUP_SSL" == "true" ]]; then
        if [[ -z "$DOMAIN_NAME" ]] || [[ -z "$EMAIL" ]]; then
            print_error "SSL setup requires --domain and --email options"
            exit 1
        fi
    fi
}

# Check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "Cannot detect operating system"
        exit 1
    fi
    
    print_info "Detected OS: $OS $VER"
}

# Update system packages
update_system() {
    print_info "Updating system packages..."
    
    case "$OS" in
        ubuntu|debian)
            apt-get update
            apt-get upgrade -y
            apt-get install -y curl wget gnupg lsb-release ca-certificates
            ;;
        centos|rhel|fedora)
            yum update -y
            yum install -y curl wget gnupg ca-certificates
            ;;
        *)
            print_warning "Unsupported OS for automatic package management: $OS"
            ;;
    esac
    
    print_success "System packages updated"
}

# Install Docker
install_docker() {
    if [[ "$INSTALL_DOCKER" != "true" ]]; then
        print_info "Skipping Docker installation"
        return 0
    fi
    
    print_info "Installing Docker..."
    
    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        print_info "Docker is already installed: $(docker --version)"
        return 0
    fi
    
    case "$OS" in
        ubuntu|debian)
            # Add Docker's official GPG key
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Add Docker repository
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel)
            # Add Docker repository
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            
            # Install Docker
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora)
            # Install Docker
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            print_error "Unsupported OS for Docker installation: $OS"
            return 1
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [[ "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER"
        print_info "Added $SUDO_USER to docker group (logout/login required)"
    fi
    
    print_success "Docker installed successfully: $(docker --version)"
}

# Install Docker Compose
install_docker_compose() {
    if [[ "$INSTALL_DOCKER_COMPOSE" != "true" ]]; then
        print_info "Skipping Docker Compose installation"
        return 0
    fi
    
    print_info "Installing Docker Compose..."
    
    # Check if Docker Compose is already installed
    if command -v docker-compose >/dev/null 2>&1; then
        print_info "Docker Compose is already installed: $(docker-compose --version)"
        return 0
    fi
    
    # Download and install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for easier access
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    print_success "Docker Compose installed successfully: $(docker-compose --version)"
}

# Setup firewall
setup_firewall() {
    if [[ "$SETUP_FIREWALL" != "true" ]]; then
        print_info "Skipping firewall configuration"
        return 0
    fi
    
    print_info "Configuring firewall..."
    
    # Check if ufw is available (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        # Reset UFW to defaults
        ufw --force reset
        
        # Set default policies
        ufw default deny incoming
        ufw default allow outgoing
        
        # Allow SSH (be careful not to lock yourself out)
        ufw allow ssh
        
        # Allow HTTP and HTTPS
        ufw allow 80/tcp
        ufw allow 443/tcp
        
        # Allow Supabase specific ports
        ufw allow 8000/tcp   # Kong API Gateway
        ufw allow 3000/tcp   # PostgREST
        ufw allow 9999/tcp   # GoTrue Auth
        ufw allow 4000/tcp   # Realtime
        ufw allow 5000/tcp   # Storage
        
        # Allow monitoring ports (restrict to localhost if needed)
        ufw allow from 127.0.0.1 to any port 9090  # Prometheus
        ufw allow from 127.0.0.1 to any port 3001  # Grafana
        
        # Enable firewall
        ufw --force enable
        
        print_success "UFW firewall configured and enabled"
        
    # Check if firewalld is available (CentOS/RHEL/Fedora)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        # Start and enable firewalld
        systemctl start firewalld
        systemctl enable firewalld
        
        # Add HTTP and HTTPS services
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --permanent --add-service=ssh
        
        # Add Supabase specific ports
        firewall-cmd --permanent --add-port=8000/tcp   # Kong API Gateway
        firewall-cmd --permanent --add-port=3000/tcp   # PostgREST
        firewall-cmd --permanent --add-port=9999/tcp   # GoTrue Auth
        firewall-cmd --permanent --add-port=4000/tcp   # Realtime
        firewall-cmd --permanent --add-port=5000/tcp   # Storage
        
        # Reload firewall rules
        firewall-cmd --reload
        
        print_success "Firewalld configured and enabled"
        
    else
        print_warning "No supported firewall found (ufw or firewalld)"
        print_info "Please configure your firewall manually to allow:"
        print_info "  - SSH (port 22)"
        print_info "  - HTTP (port 80)"
        print_info "  - HTTPS (port 443)"
        print_info "  - Supabase ports (3000, 4000, 5000, 8000, 9999)"
    fi
}

# Create necessary directories
create_directories() {
    if [[ "$CREATE_DIRECTORIES" != "true" ]]; then
        print_info "Skipping directory creation"
        return 0
    fi
    
    print_info "Creating necessary directories..."
    
    # Main directories
    mkdir -p /opt/supabase
    mkdir -p /var/lib/supabase/{db_data,storage_data,redis_data,prometheus_data,grafana_data}
    mkdir -p /var/log/supabase
    mkdir -p /var/backups/supabase-deploy
    mkdir -p /etc/supabase
    
    # Configuration directories
    mkdir -p /opt/supabase/{ssl,database/init,database/config}
    mkdir -p /opt/supabase/{functions,monitoring/prometheus,monitoring/grafana}
    mkdir -p /opt/supabase/{nginx/conf.d,static,kong}
    
    # Set proper permissions
    chown -R root:root /opt/supabase
    chown -R root:root /var/lib/supabase
    chown -R root:root /var/log/supabase
    chown -R root:root /var/backups/supabase-deploy
    chown -R root:root /etc/supabase
    
    chmod 755 /opt/supabase
    chmod 755 /var/lib/supabase
    chmod 755 /var/log/supabase
    chmod 755 /var/backups/supabase-deploy
    chmod 755 /etc/supabase
    
    print_success "Directories created successfully"
}

# Setup SSL certificates with Let's Encrypt
setup_ssl_certificates() {
    if [[ "$SETUP_SSL" != "true" ]]; then
        print_info "Skipping SSL certificate setup"
        return 0
    fi
    
    print_info "Setting up SSL certificates with Let's Encrypt..."
    
    # Install Certbot
    case "$OS" in
        ubuntu|debian)
            apt-get install -y certbot python3-certbot-nginx
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y certbot python3-certbot-nginx
            else
                yum install -y certbot python3-certbot-nginx
            fi
            ;;
        *)
            print_error "Unsupported OS for Certbot installation: $OS"
            return 1
            ;;
    esac
    
    # Obtain SSL certificate
    print_info "Obtaining SSL certificate for $DOMAIN_NAME..."
    
    # Create a simple nginx configuration for verification
    cat > /etc/nginx/sites-available/temp-ssl << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    location / {
        return 200 'SSL Setup in Progress';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Enable the temporary configuration
    ln -sf /etc/nginx/sites-available/temp-ssl /etc/nginx/sites-enabled/
    systemctl reload nginx || true
    
    # Obtain certificate
    certbot certonly --nginx -d "$DOMAIN_NAME" --email "$EMAIL" --agree-tos --non-interactive
    
    if [[ $? -eq 0 ]]; then
        print_success "SSL certificate obtained successfully"
        
        # Copy certificates to Supabase SSL directory
        cp /etc/letsencrypt/live/"$DOMAIN_NAME"/fullchain.pem /opt/supabase/ssl/
        cp /etc/letsencrypt/live/"$DOMAIN_NAME"/privkey.pem /opt/supabase/ssl/
        chmod 644 /opt/supabase/ssl/fullchain.pem
        chmod 600 /opt/supabase/ssl/privkey.pem
        
        # Setup automatic renewal
        echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -
        
        print_success "SSL certificates configured and auto-renewal setup"
    else
        print_error "Failed to obtain SSL certificate"
        return 1
    fi
    
    # Clean up temporary nginx configuration
    rm -f /etc/nginx/sites-enabled/temp-ssl
    rm -f /etc/nginx/sites-available/temp-ssl
}

# Configure system limits and optimization
configure_system_optimization() {
    print_info "Configuring system optimization..."
    
    # Increase file limits for containers
    cat >> /etc/security/limits.conf << EOF

# Supabase Enterprise - Increased limits for containers
* soft nofile 65536
* hard nofile 65536
* soft nproc 32768
* hard nproc 32768
EOF
    
    # Configure kernel parameters for better performance
    cat >> /etc/sysctl.conf << EOF

# Supabase Enterprise - Network and memory optimization
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3
vm.swappiness = 10
vm.dirty_ratio = 80
vm.dirty_background_ratio = 5
EOF
    
    # Apply sysctl changes
    sysctl -p
    
    print_success "System optimization configured"
}

# Create service user for Supabase
create_service_user() {
    print_info "Creating service user for Supabase..."
    
    # Create supabase user if it doesn't exist
    if ! id "supabase" &>/dev/null; then
        useradd -r -s /bin/false -d /opt/supabase -c "Supabase Service User" supabase
        print_success "Created supabase service user"
    else
        print_info "Supabase service user already exists"
    fi
    
    # Add supabase user to docker group
    usermod -aG docker supabase
    
    # Set proper ownership
    chown -R supabase:supabase /opt/supabase
    chown -R supabase:supabase /var/lib/supabase
    chown -R supabase:supabase /var/log/supabase
}

# Create systemd service for Supabase
create_systemd_service() {
    print_info "Creating systemd service for Supabase..."
    
    cat > /etc/systemd/system/supabase.service << EOF
[Unit]
Description=Supabase Enterprise Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
User=supabase
Group=supabase
WorkingDirectory=/opt/supabase
ExecStart=/usr/local/bin/docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d
ExecStop=/usr/local/bin/docker-compose -f docker-compose.yml -f docker-compose.production.yml down
TimeoutStartSec=300
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable supabase.service
    
    print_success "Systemd service created and enabled"
}

# Display completion summary
show_completion_summary() {
    print_header "SERVER PREPARATION COMPLETED"
    
    print_success "Server is now ready for Supabase Enterprise deployment!"
    
    echo ""
    print_info "Summary of configurations:"
    
    if [[ "$INSTALL_DOCKER" == "true" ]]; then
        echo "  ✅ Docker installed and configured"
    fi
    
    if [[ "$INSTALL_DOCKER_COMPOSE" == "true" ]]; then
        echo "  ✅ Docker Compose installed"
    fi
    
    if [[ "$SETUP_FIREWALL" == "true" ]]; then
        echo "  ✅ Firewall configured with required ports"
    fi
    
    if [[ "$CREATE_DIRECTORIES" == "true" ]]; then
        echo "  ✅ Directory structure created"
    fi
    
    if [[ "$SETUP_SSL" == "true" ]]; then
        echo "  ✅ SSL certificates configured for $DOMAIN_NAME"
    fi
    
    echo "  ✅ System optimization applied"
    echo "  ✅ Service user created"
    echo "  ✅ Systemd service configured"
    
    echo ""
    print_info "Next steps:"
    print_info "1. Use the deploy_ssh.sh script to deploy Supabase"
    print_info "2. Configure your domain DNS to point to this server"
    print_info "3. Update environment variables in .env.production"
    
    if [[ "$SUDO_USER" ]]; then
        print_warning "Note: User $SUDO_USER needs to logout/login to use Docker without sudo"
    fi
    
    echo ""
    print_info "Log file: $LOG_FILE"
}

# Main function
main() {
    print_header "SUPABASE ENTERPRISE SERVER PREPARATION"
    
    log "Starting server preparation"
    
    # Create log file
    touch "$LOG_FILE"
    
    # Execute preparation steps
    check_privileges
    detect_os
    update_system
    install_docker
    install_docker_compose
    setup_firewall
    create_directories
    setup_ssl_certificates
    configure_system_optimization
    create_service_user
    create_systemd_service
    
    show_completion_summary
    
    log "Server preparation completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi
