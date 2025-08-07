#!/bin/bash

# 🔐 Automated SSL Certificate Setup for Supabase
# This script automatically generates and installs SSL certificates
# Supports both Let's Encrypt (production) and self-signed (development)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSL_DIR="${SCRIPT_DIR}/ssl"
NGINX_SSL_DIR="${SSL_DIR}/nginx"
POSTGRES_SSL_DIR="${SSL_DIR}/postgresql"
NGINX_CONFIG_DIR="${SCRIPT_DIR}/nginx"
LOG_FILE="${SCRIPT_DIR}/ssl_setup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Success message
success() {
    log "SUCCESS: $1" "$GREEN"
}

# Warning message
warn() {
    log "WARNING: $1" "$YELLOW"
}

# Info message
info() {
    log "INFO: $1" "$BLUE"
}

# Check if running as root for Let's Encrypt
check_root() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Check if domain is accessible
check_domain_accessibility() {
    local domain="$1"
    info "Checking domain accessibility: $domain"
    
    if command -v dig >/dev/null 2>&1; then
        local ip=$(dig +short "$domain" | tail -n1)
        if [[ -n "$ip" ]]; then
            success "Domain $domain resolves to IP: $ip"
            return 0
        fi
    elif command -v nslookup >/dev/null 2>&1; then
        if nslookup "$domain" >/dev/null 2>&1; then
            success "Domain $domain is accessible"
            return 0
        fi
    fi
    
    warn "Domain $domain may not be accessible externally"
    return 1
}

# Install dependencies
install_dependencies() {
    info "Installing dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        if ! command -v certbot >/dev/null 2>&1; then
            info "Installing certbot..."
            apt-get update
            apt-get install -y certbot python3-certbot-nginx
        fi
        
        if ! command -v openssl >/dev/null 2>&1; then
            info "Installing openssl..."
            apt-get install -y openssl
        fi
        
    elif command -v yum >/dev/null 2>&1; then
        # RHEL/CentOS
        if ! command -v certbot >/dev/null 2>&1; then
            info "Installing certbot..."
            yum install -y epel-release
            yum install -y certbot python3-certbot-nginx
        fi
        
        if ! command -v openssl >/dev/null 2>&1; then
            info "Installing openssl..."
            yum install -y openssl
        fi
        
    elif command -v brew >/dev/null 2>&1; then
        # macOS
        if ! command -v certbot >/dev/null 2>&1; then
            info "Installing certbot..."
            brew install certbot
        fi
        
    else
        warn "Package manager not detected. Please install certbot and openssl manually."
    fi
    
    success "Dependencies installed"
}

# Create SSL directories
create_ssl_directories() {
    info "Creating SSL directories..."
    
    mkdir -p "$NGINX_SSL_DIR"
    mkdir -p "$POSTGRES_SSL_DIR"
    mkdir -p "$NGINX_CONFIG_DIR"
    
    # Set appropriate permissions
    chmod 755 "$SSL_DIR"
    chmod 750 "$NGINX_SSL_DIR"
    chmod 750 "$POSTGRES_SSL_DIR"
    
    success "SSL directories created"
}

# Generate self-signed certificates
generate_self_signed_certificates() {
    local domain="${1:-localhost}"
    
    info "Generating self-signed certificates for domain: $domain"
    
    # Generate private key for Nginx
    openssl genrsa -out "$NGINX_SSL_DIR/private.key" 2048
    
    # Generate certificate signing request
    openssl req -new -key "$NGINX_SSL_DIR/private.key" \
        -out "$NGINX_SSL_DIR/certificate.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$domain" \
        -config <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
OU = OrgUnit
CN = $domain

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
)
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 \
        -in "$NGINX_SSL_DIR/certificate.csr" \
        -signkey "$NGINX_SSL_DIR/private.key" \
        -out "$NGINX_SSL_DIR/certificate.crt" \
        -extensions v3_req \
        -extfile <(cat <<EOF
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain
DNS.2 = localhost
DNS.3 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF
)
    
    # Generate DH parameters for better security
    openssl dhparam -out "$NGINX_SSL_DIR/dhparam.pem" 2048
    
    # Create combined certificate file
    cat "$NGINX_SSL_DIR/certificate.crt" > "$NGINX_SSL_DIR/fullchain.pem"
    
    # Set appropriate permissions
    chmod 600 "$NGINX_SSL_DIR/private.key"
    chmod 644 "$NGINX_SSL_DIR/certificate.crt"
    chmod 644 "$NGINX_SSL_DIR/fullchain.pem"
    chmod 644 "$NGINX_SSL_DIR/dhparam.pem"
    
    success "Self-signed certificates generated for $domain"
}

# Generate Let's Encrypt certificates
generate_letsencrypt_certificates() {
    local domain="$1"
    local email="$2"
    
    info "Generating Let's Encrypt certificates for domain: $domain"
    
    # Stop nginx if running to free port 80
    if docker ps | grep -q supabase-nginx; then
        warn "Stopping nginx container to free port 80..."
        docker stop supabase-nginx || true
    fi
    
    # Generate certificates using standalone mode
    certbot certonly \
        --standalone \
        --agree-tos \
        --no-eff-email \
        --email "$email" \
        -d "$domain" \
        --non-interactive
    
    # Copy certificates to our SSL directory
    cp "/etc/letsencrypt/live/$domain/privkey.pem" "$NGINX_SSL_DIR/private.key"
    cp "/etc/letsencrypt/live/$domain/fullchain.pem" "$NGINX_SSL_DIR/fullchain.pem"
    cp "/etc/letsencrypt/live/$domain/cert.pem" "$NGINX_SSL_DIR/certificate.crt"
    
    # Generate DH parameters if not exists
    if [[ ! -f "$NGINX_SSL_DIR/dhparam.pem" ]]; then
        info "Generating DH parameters..."
        openssl dhparam -out "$NGINX_SSL_DIR/dhparam.pem" 2048
    fi
    
    # Set appropriate permissions
    chmod 600 "$NGINX_SSL_DIR/private.key"
    chmod 644 "$NGINX_SSL_DIR/certificate.crt"
    chmod 644 "$NGINX_SSL_DIR/fullchain.pem"
    chmod 644 "$NGINX_SSL_DIR/dhparam.pem"
    
    success "Let's Encrypt certificates generated for $domain"
}

# Generate PostgreSQL SSL certificates
generate_postgresql_certificates() {
    local domain="${1:-localhost}"
    
    info "Generating PostgreSQL SSL certificates..."
    
    # Generate private key
    openssl genrsa -out "$POSTGRES_SSL_DIR/server.key" 2048
    
    # Generate certificate signing request
    openssl req -new -key "$POSTGRES_SSL_DIR/server.key" \
        -out "$POSTGRES_SSL_DIR/server.csr" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=PostgreSQL/CN=$domain"
    
    # Generate self-signed certificate
    openssl x509 -req -days 365 \
        -in "$POSTGRES_SSL_DIR/server.csr" \
        -signkey "$POSTGRES_SSL_DIR/server.key" \
        -out "$POSTGRES_SSL_DIR/server.crt"
    
    # Create root CA for PostgreSQL (optional but recommended)
    openssl req -new -x509 -days 3650 -nodes \
        -out "$POSTGRES_SSL_DIR/root.crt" \
        -keyout "$POSTGRES_SSL_DIR/root.key" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=PostgreSQL-CA/CN=PostgreSQL-Root-CA"
    
    # Set appropriate permissions for PostgreSQL
    chmod 600 "$POSTGRES_SSL_DIR/server.key" "$POSTGRES_SSL_DIR/root.key"
    chmod 644 "$POSTGRES_SSL_DIR/server.crt" "$POSTGRES_SSL_DIR/root.crt"
    
    # PostgreSQL requires specific ownership (postgres user)
    # This will be handled by the container
    
    success "PostgreSQL SSL certificates generated"
}

# Update Nginx configuration for SSL
update_nginx_config() {
    local domain="${1:-localhost}"
    
    info "Updating Nginx configuration for SSL..."
    
    cat > "$NGINX_CONFIG_DIR/nginx.conf" << EOF
# Nginx configuration for Supabase with SSL
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Basic settings
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    
    # Performance settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 50M;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
    
    # Security headers
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' wss: https:;" always;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=auth:10m rate=5r/s;
    limit_req_zone \$binary_remote_addr zone=admin:10m rate=2r/s;
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_dhparam /etc/nginx/ssl/dhparam.pem;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Upstream definitions
    upstream supabase_kong {
        server kong:8000;
        keepalive 32;
    }
    
    upstream supabase_studio {
        server studio:3000;
        keepalive 32;
    }
    
    # HTTP to HTTPS redirect
    server {
        listen 80;
        server_name $domain;
        
        # Health check endpoint (no redirect)
        location /health {
            access_log off;
            return 200 "healthy\\n";
            add_header Content-Type text/plain;
        }
        
        # Redirect all other HTTP traffic to HTTPS
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }
    
    # HTTPS server for API
    server {
        listen 443 ssl http2;
        server_name $domain;
        
        # SSL configuration
        ssl_certificate /etc/nginx/ssl/fullchain.pem;
        ssl_certificate_key /etc/nginx/ssl/private.key;
        
        # API routes
        location /rest/ {
            limit_req zone=api burst=20 nodelay;
            proxy_pass http://supabase_kong;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
        
        # Auth routes with stricter rate limiting
        location /auth/ {
            limit_req zone=auth burst=10 nodelay;
            proxy_pass http://supabase_kong;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
        
        # Realtime WebSocket
        location /realtime/ {
            proxy_pass http://supabase_kong;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_read_timeout 86400;
        }
        
        # Storage
        location /storage/ {
            limit_req zone=api burst=30 nodelay;
            proxy_pass http://supabase_kong;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            client_max_body_size 50M;
        }
        
        # Health check
        location /health {
            access_log off;
            return 200 "healthy\\n";
            add_header Content-Type text/plain;
        }
        
        # Dashboard/Studio (optional, restrict access as needed)
        location /dashboard/ {
            limit_req zone=admin burst=5 nodelay;
            proxy_pass http://supabase_studio/;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            
            # Optional: Restrict dashboard access by IP
            # allow 192.168.1.0/24;
            # allow 10.0.0.0/8;
            # deny all;
        }
    }
}
EOF
    
    success "Nginx configuration updated for SSL"
}

# Setup certificate auto-renewal for Let's Encrypt
setup_auto_renewal() {
    info "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > "${SCRIPT_DIR}/renew_certificates.sh" << 'EOF'
#!/bin/bash

# Auto-renewal script for Let's Encrypt certificates
LOG_FILE="/var/log/letsencrypt-renewal.log"

echo "[$(date)] Starting certificate renewal..." >> "$LOG_FILE"

# Stop nginx to free port 80
docker stop supabase-nginx >> "$LOG_FILE" 2>&1

# Renew certificates
certbot renew --quiet >> "$LOG_FILE" 2>&1

# Copy renewed certificates
if [ -d "/etc/letsencrypt/live" ]; then
    for domain_dir in /etc/letsencrypt/live/*/; do
        domain=$(basename "$domain_dir")
        if [ "$domain" != "*" ]; then
            echo "[$(date)] Updating certificates for $domain..." >> "$LOG_FILE"
            cp "/etc/letsencrypt/live/$domain/privkey.pem" "./ssl/nginx/private.key" 2>/dev/null || true
            cp "/etc/letsencrypt/live/$domain/fullchain.pem" "./ssl/nginx/fullchain.pem" 2>/dev/null || true
            cp "/etc/letsencrypt/live/$domain/cert.pem" "./ssl/nginx/certificate.crt" 2>/dev/null || true
        fi
    done
fi

# Start nginx
docker start supabase-nginx >> "$LOG_FILE" 2>&1

# Reload nginx configuration
docker exec supabase-nginx nginx -s reload >> "$LOG_FILE" 2>&1

echo "[$(date)] Certificate renewal completed." >> "$LOG_FILE"
EOF
    
    chmod +x "${SCRIPT_DIR}/renew_certificates.sh"
    
    # Add to crontab (run twice daily)
    if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null; echo "0 2,14 * * * cd $SCRIPT_DIR && ./renew_certificates.sh") | crontab -
        success "Auto-renewal configured in crontab"
    else
        warn "Crontab not available. Please manually schedule: cd $SCRIPT_DIR && ./renew_certificates.sh"
    fi
}

# Main setup function
main() {
    log "🔐 Starting SSL Certificate Setup for Supabase" "$BLUE"
    log "Log file: $LOG_FILE" "$BLUE"
    
    # Parse command line arguments
    local cert_type="self-signed"
    local domain="localhost"
    local email=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                cert_type="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --email)
                email="$2"
                shift 2
                ;;
            --help)
                cat << EOF
SSL Certificate Setup for Supabase

Usage: $0 [OPTIONS]

Options:
    --type      Certificate type: 'letsencrypt' or 'self-signed' (default: self-signed)
    --domain    Domain name (default: localhost)
    --email     Email for Let's Encrypt registration (required for letsencrypt)
    --help      Show this help message

Examples:
    # Self-signed certificates for development
    $0 --type self-signed --domain localhost

    # Let's Encrypt certificates for production
    $0 --type letsencrypt --domain yourdomain.com --email admin@yourdomain.com

EOF
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    # Validate inputs
    if [[ "$cert_type" == "letsencrypt" ]]; then
        if [[ -z "$email" ]]; then
            error_exit "Email is required for Let's Encrypt certificates. Use --email option."
        fi
        if [[ "$domain" == "localhost" ]]; then
            error_exit "A valid domain name is required for Let's Encrypt certificates. Use --domain option."
        fi
        if ! check_root; then
            error_exit "Root privileges required for Let's Encrypt certificate generation. Run with sudo."
        fi
    fi
    
    # Create SSL directories
    create_ssl_directories
    
    # Install dependencies if needed
    if [[ "$cert_type" == "letsencrypt" ]]; then
        install_dependencies
        check_domain_accessibility "$domain"
    fi
    
    # Generate certificates based on type
    case "$cert_type" in
        "letsencrypt")
            generate_letsencrypt_certificates "$domain" "$email"
            setup_auto_renewal
            ;;
        "self-signed")
            generate_self_signed_certificates "$domain"
            ;;
        *)
            error_exit "Invalid certificate type: $cert_type. Use 'letsencrypt' or 'self-signed'."
            ;;
    esac
    
    # Generate PostgreSQL certificates
    generate_postgresql_certificates "$domain"
    
    # Update Nginx configuration
    update_nginx_config "$domain"
    
    # Final instructions
    log "🎉 SSL Certificate Setup Complete!" "$GREEN"
    echo
    echo "📋 Next Steps:"
    echo "1. Start Supabase with SSL enabled:"
    echo "   docker compose --profile production up -d"
    echo
    echo "2. Test SSL configuration:"
    echo "   curl -k https://$domain/health"
    echo
    echo "3. Verify certificates:"
    echo "   openssl x509 -in $NGINX_SSL_DIR/certificate.crt -text -noout"
    echo
    if [[ "$cert_type" == "letsencrypt" ]]; then
        echo "4. Monitor auto-renewal:"
        echo "   tail -f /var/log/letsencrypt-renewal.log"
        echo
    fi
    echo "📁 Certificate files:"
    echo "   Nginx SSL: $NGINX_SSL_DIR/"
    echo "   PostgreSQL SSL: $POSTGRES_SSL_DIR/"
    echo "   Nginx config: $NGINX_CONFIG_DIR/nginx.conf"
    echo
    if [[ "$cert_type" == "self-signed" ]]; then
        warn "Self-signed certificates will show security warnings in browsers."
        echo "   For production, use: $0 --type letsencrypt --domain yourdomain.com --email admin@yourdomain.com"
    fi
}

# Run main function with all arguments
main "$@"
