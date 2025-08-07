#!/bin/bash

# Enterprise Supabase Web Interface Deployment Script
# Deploy the HTML management interface to Ubuntu 24 VPS/Dedicated Server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WEB_DIR="/var/www/supabase-admin"
NGINX_CONF="/etc/nginx/sites-available/supabase-admin"
SERVICE_NAME="supabase-admin"
DEFAULT_PORT="8080"

echo -e "${BLUE}🚀 Enterprise Supabase Web Interface Deployment${NC}"
echo -e "${BLUE}=================================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root for security reasons"
    print_status "Please run as a regular user with sudo privileges"
    exit 1
fi

# Get configuration from user
get_config() {
    echo -e "${BLUE}Configuration Setup${NC}"
    echo "===================="
    
    read -p "Enter your domain name (e.g., admin.yourdomain.com) or press Enter for IP access: " DOMAIN_NAME
    read -p "Enter port number (default: 8080): " PORT
    PORT=${PORT:-$DEFAULT_PORT}
    
    if [[ -z "$DOMAIN_NAME" ]]; then
        SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipecho.net/plain 2>/dev/null || echo "YOUR_SERVER_IP")
        DOMAIN_NAME="$SERVER_IP"
        print_warning "No domain provided. Using IP: $SERVER_IP"
    fi
    
    echo
    print_status "Configuration:"
    print_status "  Domain/IP: $DOMAIN_NAME"
    print_status "  Port: $PORT"
    print_status "  Web Directory: $WEB_DIR"
    echo
    
    read -p "Continue with this configuration? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        print_error "Deployment cancelled"
        exit 1
    fi
}

# Install required packages
install_dependencies() {
    print_status "Installing dependencies..."
    
    sudo apt update
    sudo apt install -y nginx certbot python3-certbot-nginx ufw
    
    print_status "Dependencies installed successfully"
}

# Create web directory and copy files
setup_web_files() {
    print_status "Setting up web files..."
    
    # Create web directory
    sudo mkdir -p $WEB_DIR
    
    # Copy HTML file
    if [[ -f "SETUP_GUIDE.html" ]]; then
        sudo cp SETUP_GUIDE.html $WEB_DIR/index.html
        print_status "Web interface copied to $WEB_DIR"
    else
        print_error "SETUP_GUIDE.html not found in current directory"
        exit 1
    fi
    
    # Set proper permissions
    sudo chown -R www-data:www-data $WEB_DIR
    sudo chmod -R 755 $WEB_DIR
    
    print_status "File permissions set correctly"
}

# Configure Nginx
configure_nginx() {
    print_status "Configuring Nginx..."
    
    # Create Nginx configuration
    sudo tee $NGINX_CONF > /dev/null <<EOF
server {
    listen $PORT;
    server_name $DOMAIN_NAME;
    
    root $WEB_DIR;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied expired no-cache no-store private must-revalidate auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # API proxy for backend calls (if needed)
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # Static assets caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }
}
EOF
    
    # Enable the site
    sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    if sudo nginx -t; then
        print_status "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
    
    print_status "Nginx configured successfully"
}

# Configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Enable UFW if not already enabled
    sudo ufw --force enable
    
    # Allow SSH
    sudo ufw allow ssh
    
    # Allow HTTP and HTTPS
    sudo ufw allow 80
    sudo ufw allow 443
    
    # Allow custom port
    sudo ufw allow $PORT
    
    # Allow Supabase ports
    sudo ufw allow 3000
    sudo ufw allow 9090
    
    print_status "Firewall configured successfully"
}

# Setup SSL certificate (if domain provided)
setup_ssl() {
    if [[ "$DOMAIN_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_warning "IP address detected, skipping SSL setup"
        print_status "Access your interface at: http://$DOMAIN_NAME:$PORT"
        return
    fi
    
    print_status "Setting up SSL certificate for $DOMAIN_NAME..."
    
    # Get SSL certificate
    if sudo certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME; then
        print_status "SSL certificate installed successfully"
        print_status "Access your interface at: https://$DOMAIN_NAME"
    else
        print_warning "SSL setup failed. You can access via HTTP: http://$DOMAIN_NAME:$PORT"
        print_warning "To retry SSL later, run: sudo certbot --nginx -d $DOMAIN_NAME"
    fi
}

# Create systemd service for auto-restart
create_service() {
    print_status "Creating systemd service..."
    
    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null <<EOF
[Unit]
Description=Supabase Admin Web Interface
After=network.target nginx.service
Requires=nginx.service

[Service]
Type=forking
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    
    print_status "Systemd service created and enabled"
}

# Start services
start_services() {
    print_status "Starting services..."
    
    sudo systemctl restart nginx
    sudo systemctl enable nginx
    
    if sudo systemctl is-active --quiet nginx; then
        print_status "Nginx started successfully"
    else
        print_error "Failed to start Nginx"
        exit 1
    fi
}

# Create update script
create_update_script() {
    print_status "Creating update script..."
    
    sudo tee /usr/local/bin/update-supabase-admin > /dev/null <<EOF
#!/bin/bash
# Update Supabase Admin Interface

set -e

WEB_DIR="$WEB_DIR"
BACKUP_DIR="/tmp/supabase-admin-backup-\$(date +%Y%m%d-%H%M%S)"

echo "Creating backup..."
cp -r \$WEB_DIR \$BACKUP_DIR

echo "Updating interface..."
if [[ -f "SETUP_GUIDE.html" ]]; then
    cp SETUP_GUIDE.html \$WEB_DIR/index.html
    chown www-data:www-data \$WEB_DIR/index.html
    chmod 644 \$WEB_DIR/index.html
    echo "Interface updated successfully"
    echo "Backup saved to: \$BACKUP_DIR"
else
    echo "Error: SETUP_GUIDE.html not found"
    exit 1
fi

systemctl reload nginx
echo "Nginx reloaded"
EOF
    
    sudo chmod +x /usr/local/bin/update-supabase-admin
    print_status "Update script created at /usr/local/bin/update-supabase-admin"
}

# Main deployment function
main() {
    echo -e "${BLUE}Starting deployment...${NC}"
    echo
    
    get_config
    install_dependencies
    setup_web_files
    configure_nginx
    configure_firewall
    start_services
    create_service
    create_update_script
    setup_ssl
    
    echo
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${GREEN}=================================${NC}"
    echo
    print_status "Access your Supabase Admin Interface:"
    
    if [[ "$DOMAIN_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "  ${BLUE}🌐 URL:${NC} http://$DOMAIN_NAME:$PORT"
    else
        echo -e "  ${BLUE}🌐 URL:${NC} https://$DOMAIN_NAME (with SSL)"
        echo -e "  ${BLUE}🌐 Fallback:${NC} http://$DOMAIN_NAME:$PORT"
    fi
    
    echo
    print_status "Management Commands:"
    echo -e "  ${BLUE}Update interface:${NC} sudo /usr/local/bin/update-supabase-admin"
    echo -e "  ${BLUE}Restart Nginx:${NC} sudo systemctl restart nginx"
    echo -e "  ${BLUE}View logs:${NC} sudo journalctl -u nginx -f"
    echo -e "  ${BLUE}SSL renewal:${NC} sudo certbot renew"
    
    echo
    print_status "Security Notes:"
    echo "  - Consider setting up basic authentication for production"
    echo "  - Review firewall rules regularly"
    echo "  - Monitor access logs for suspicious activity"
    echo "  - Keep SSL certificates updated automatically"
    
    echo
    print_status "Next Steps:"
    echo "  1. Access the interface using the URL above"
    echo "  2. Configure your domain settings in the interface"
    echo "  3. Test all functionality with your Supabase deployment"
    echo "  4. Set up monitoring for the web interface"
}

# Run main function
main "$@"
