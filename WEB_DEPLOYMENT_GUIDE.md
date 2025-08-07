# Supabase Enterprise Web Interface - Live URL Deployment Guide

## 🌐 Access Your Management Interface from Anywhere

Your HTML management interface can be hosted on your Ubuntu 24 VPS/dedicated server and accessed via a live URL. Here are multiple deployment options:

## 🚀 Quick Deployment (Automated)

### Option 1: One-Click Deployment Script

```bash
# Make the deployment script executable
chmod +x deploy_web_interface.sh

# Run the automated deployment
./deploy_web_interface.sh
```

**What this script does:**
- ✅ Installs and configures Nginx web server
- ✅ Sets up SSL certificates automatically (if domain provided)
- ✅ Configures firewall rules
- ✅ Creates systemd service for auto-restart
- ✅ Provides update mechanism
- ✅ Implements security headers

### Option 2: Manual Nginx Setup

```bash
# Install Nginx
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Create web directory
sudo mkdir -p /var/www/supabase-admin

# Copy your HTML file
sudo cp SETUP_GUIDE.html /var/www/supabase-admin/index.html

# Set permissions
sudo chown -R www-data:www-data /var/www/supabase-admin
sudo chmod -R 755 /var/www/supabase-admin
```

### Option 3: Python HTTP Server (Development)

```bash
# Simple HTTP server for testing
cd /path/to/your/html/file
python3 -m http.server 8080

# Access via: http://your-server-ip:8080
```

## 🔧 Nginx Configuration

Create `/etc/nginx/sites-available/supabase-admin`:

```nginx
server {
    listen 80;
    server_name your-domain.com;  # Replace with your domain
    
    root /var/www/supabase-admin;
    index index.html;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # API proxy for Supabase backend
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable the site:
```bash
sudo ln -s /etc/nginx/sites-available/supabase-admin /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## 🔒 SSL Setup (HTTPS)

### Automatic SSL with Certbot:
```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Get SSL certificate
sudo certbot --nginx -d your-domain.com

# Auto-renewal (already configured)
sudo systemctl enable certbot.timer
```

### Manual SSL Setup:
```bash
# If you have your own certificates
sudo mkdir -p /etc/ssl/private
sudo cp your-certificate.crt /etc/ssl/certs/
sudo cp your-private.key /etc/ssl/private/
sudo chmod 600 /etc/ssl/private/your-private.key
```

## 🌍 DNS Configuration

Point your domain to your server:

### A Record (IPv4):
```
Type: A
Name: admin (or subdomain of choice)
Value: YOUR_SERVER_IP
TTL: 300
```

### AAAA Record (IPv6, if available):
```
Type: AAAA
Name: admin
Value: YOUR_IPV6_ADDRESS
TTL: 300
```

## 🔥 Firewall Configuration

```bash
# Enable UFW firewall
sudo ufw enable

# Allow SSH (important!)
sudo ufw allow ssh

# Allow HTTP and HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Allow Supabase ports
sudo ufw allow 3000   # Supabase Studio
sudo ufw allow 9090   # Prometheus

# Check status
sudo ufw status
```

## 📱 Access Methods

### 1. Domain Access (Recommended)
```
https://admin.yourdomain.com
http://admin.yourdomain.com  (if no SSL)
```

### 2. IP Access
```
http://YOUR_SERVER_IP
https://YOUR_SERVER_IP  (with SSL)
```

### 3. Custom Port
```
http://your-domain.com:8080
http://YOUR_SERVER_IP:8080
```

## 🔧 Advanced Configuration

### Basic Authentication (Optional Security Layer)

```bash
# Install apache2-utils
sudo apt install apache2-utils

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd admin

# Add to Nginx config
location / {
    auth_basic "Supabase Admin Area";
    auth_basic_user_file /etc/nginx/.htpasswd;
    try_files $uri $uri/ =404;
}
```

### Rate Limiting

Add to Nginx config:
```nginx
http {
    limit_req_zone $binary_remote_addr zone=login:10m rate=5r/m;
    
    server {
        location / {
            limit_req zone=login burst=5 nodelay;
            # ... rest of config
        }
    }
}
```

## 🔄 Updates and Maintenance

### Update the Interface:
```bash
# Copy new version
sudo cp SETUP_GUIDE.html /var/www/supabase-admin/index.html

# Reload Nginx (zero downtime)
sudo systemctl reload nginx
```

### Monitor Access:
```bash
# View access logs
sudo tail -f /var/log/nginx/access.log

# View error logs
sudo tail -f /var/log/nginx/error.log
```

### Backup:
```bash
# Backup web files
sudo tar -czf /tmp/supabase-admin-backup-$(date +%Y%m%d).tar.gz /var/www/supabase-admin
```

## 🚨 Security Best Practices

1. **Enable HTTPS Only**:
   ```nginx
   # Redirect HTTP to HTTPS
   server {
       listen 80;
       server_name your-domain.com;
       return 301 https://$server_name$request_uri;
   }
   ```

2. **Hide Server Version**:
   ```nginx
   # In nginx.conf
   server_tokens off;
   ```

3. **Set Strong Security Headers**:
   ```nginx
   add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
   add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline';" always;
   ```

4. **Regular Updates**:
   ```bash
   sudo apt update && sudo apt upgrade
   sudo certbot renew --dry-run
   ```

## 📊 Monitoring Setup

### Log Rotation:
```bash
# Already configured in Ubuntu, but verify:
sudo logrotate -d /etc/logrotate.d/nginx
```

### System Monitoring:
```bash
# Add to crontab for health checks
*/5 * * * * curl -f http://localhost/health || systemctl restart nginx
```

## 🎯 Example Access URLs

After deployment, you can access your management interface at:

- **Production**: `https://admin.yourdomain.com`
- **Staging**: `https://staging-admin.yourdomain.com`
- **Development**: `http://your-server-ip:8080`

## 🆘 Troubleshooting

### Nginx Won't Start:
```bash
# Check configuration
sudo nginx -t

# Check error logs
sudo journalctl -u nginx -f
```

### SSL Issues:
```bash
# Test SSL
openssl s_client -connect your-domain.com:443

# Renew certificate
sudo certbot renew --force-renewal
```

### Port Issues:
```bash
# Check what's using port 80
sudo netstat -tulpn | grep :80

# Kill process if needed
sudo pkill -f nginx
```

Your enterprise Supabase management interface is now accessible from anywhere in the world with professional-grade security and performance! 🚀
