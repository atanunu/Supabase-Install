#!/bin/bash

# Quick Web Interface Deployment for Ubuntu 24 VPS
# One-command deployment of Supabase Enterprise Management Interface

set -e

echo "🚀 Quick Supabase Web Interface Deployment"
echo "=========================================="

# Get server details
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "UNKNOWN")
echo "Server IP: $SERVER_IP"

# Quick installation
echo "📦 Installing Nginx..."
sudo apt update >/dev/null 2>&1
sudo apt install -y nginx >/dev/null 2>&1

echo "📁 Setting up web directory..."
sudo mkdir -p /var/www/supabase-admin
sudo cp SETUP_GUIDE.html /var/www/supabase-admin/index.html
sudo chown -R www-data:www-data /var/www/supabase-admin

echo "⚙️ Configuring Nginx..."
sudo tee /etc/nginx/sites-available/supabase-admin >/dev/null <<EOF
server {
    listen 80;
    server_name _;
    
    root /var/www/supabase-admin;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/supabase-admin /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

echo "🔥 Configuring firewall..."
sudo ufw --force enable >/dev/null 2>&1
sudo ufw allow ssh >/dev/null 2>&1
sudo ufw allow 80 >/dev/null 2>&1
sudo ufw allow 443 >/dev/null 2>&1
sudo ufw allow 3000 >/dev/null 2>&1

echo "🚦 Starting services..."
sudo nginx -t && sudo systemctl restart nginx
sudo systemctl enable nginx

echo ""
echo "✅ Deployment Complete!"
echo "======================="
echo ""
echo "🌐 Access your Supabase Management Interface:"
echo "   http://$SERVER_IP"
echo ""
echo "🔧 Management Commands:"
echo "   Update: sudo cp SETUP_GUIDE.html /var/www/supabase-admin/index.html"
echo "   Restart: sudo systemctl restart nginx"
echo "   Logs: sudo tail -f /var/log/nginx/access.log"
echo ""
echo "🔒 For SSL/HTTPS setup:"
echo "   ./deploy_web_interface.sh"
echo ""
echo "🎯 Your enterprise interface is now live!"
