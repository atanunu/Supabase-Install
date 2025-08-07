# 🐧 Ubuntu 24 LTS Deployment Guide for Supabase

This guide provides step-by-step instructions for deploying your enhanced Supabase setup on Ubuntu 24 LTS.

## 📋 Prerequisites

### System Requirements
- Ubuntu 24.04 LTS (Noble Numbat)
- Minimum 4GB RAM (8GB recommended)
- 20GB free disk space
- Root or sudo access
- Domain name (for production SSL)

### Initial Setup
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget git unzip

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install -y docker-compose-plugin

# Reboot to apply group changes
sudo reboot
```

## 🚀 Quick Deployment

### 1. Clone and Setup
```bash
# Navigate to your project directory
cd /path/to/your/SupabaseInstall

# Make scripts executable
chmod +x *.sh

# Run the automated SSL setup
./ubuntu_ssl_setup.sh
```

### 2. Configure Environment
```bash
# Copy and edit environment variables
cp .env.example .env
nano .env

# Update these critical variables:
POSTGRES_PASSWORD=your_secure_password
JWT_SECRET=your_jwt_secret_key
ANON_KEY=your_anon_key
SERVICE_ROLE_KEY=your_service_role_key
SITE_URL=https://your-domain.com
```

### 3. Deploy Services
```bash
# Deploy with SSL and monitoring
sudo docker compose --profile production --profile monitoring up -d

# Verify deployment
sudo docker compose ps
```

## 🔧 Ubuntu-Specific Configurations

### Firewall Setup (UFW)
```bash
# Enable UFW
sudo ufw enable

# Allow SSH
sudo ufw allow ssh

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow monitoring ports (optional, restrict as needed)
sudo ufw allow 3001/tcp  # Grafana
sudo ufw allow 9090/tcp  # Prometheus

# Check status
sudo ufw status
```

### System Limits
```bash
# Increase file limits for database
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf

# Add kernel parameters for better performance
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
echo "vm.dirty_ratio=15" | sudo tee -a /etc/sysctl.conf
echo "vm.dirty_background_ratio=5" | sudo tee -a /etc/sysctl.conf

# Apply changes
sudo sysctl -p
```

### Systemd Service (Optional)
```bash
# Create systemd service for auto-start
sudo tee /etc/systemd/system/supabase.service << EOF
[Unit]
Description=Supabase Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/path/to/your/SupabaseInstall
ExecStart=/usr/bin/docker compose --profile production up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl enable supabase.service
sudo systemctl start supabase.service
```

## 📊 Monitoring Setup

### Access Monitoring Dashboards
```bash
# Grafana: http://your-server:3001
# Username: admin
# Password: admin (change immediately)

# Prometheus: http://your-server:9090
```

### Log Management
```bash
# View logs
sudo docker compose logs -f

# Specific service logs
sudo docker compose logs -f db
sudo docker compose logs -f kong
sudo docker compose logs -f auth

# Log rotation setup
sudo logrotate -d /etc/logrotate.d/docker
```

## 🔐 Security Hardening

### Automatic Security Updates
```bash
# Install unattended upgrades
sudo apt install -y unattended-upgrades

# Configure automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades
```

### Fail2Ban Setup
```bash
# Install Fail2Ban
sudo apt install -y fail2ban

# Create custom config
sudo tee /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
EOF

# Restart fail2ban
sudo systemctl restart fail2ban
```

## 📁 Directory Structure
```
/opt/supabase/                 # Recommended installation path
├── ssl/
│   ├── nginx/                 # Nginx SSL certificates
│   └── postgresql/            # PostgreSQL SSL certificates
├── nginx/
│   ├── nginx.conf             # Nginx configuration
│   └── logs/                  # Nginx logs
├── monitoring/
│   ├── prometheus.yml         # Prometheus config
│   ├── grafana/               # Grafana configs
│   └── loki/                  # Loki configs
├── backups/                   # Local backups
├── scripts/                   # Management scripts
└── docker-compose.yml         # Main compose file
```

## 🔄 Backup and Maintenance

### Automated Backups
```bash
# Set up daily backups
(crontab -l 2>/dev/null; echo "0 2 * * * cd /path/to/SupabaseInstall && ./backup_supabase.sh") | crontab -

# Weekly cloud backup
(crontab -l 2>/dev/null; echo "0 3 * * 0 cd /path/to/SupabaseInstall && ./cloud_backup.sh") | crontab -
```

### Maintenance Tasks
```bash
# Weekly maintenance script
cat > /usr/local/bin/supabase-maintenance.sh << 'EOF'
#!/bin/bash
cd /path/to/SupabaseInstall

# Update containers
docker compose pull
docker compose up -d

# Clean up old images
docker image prune -f

# Backup before maintenance
./backup_supabase.sh

# Check health
./health_check.sh --full
EOF

chmod +x /usr/local/bin/supabase-maintenance.sh

# Schedule weekly maintenance
(crontab -l 2>/dev/null; echo "0 4 * * 1 /usr/local/bin/supabase-maintenance.sh") | crontab -
```

## 🧪 Testing and Validation

### Health Checks
```bash
# Test all endpoints
curl -k https://your-domain.com/health
curl -k https://your-domain.com/rest/v1/
curl -k https://your-domain.com/auth/v1/health

# Database connection test
docker exec supabase-db psql -U postgres -c "SELECT version();"

# Redis test
docker exec supabase-redis redis-cli ping
```

### Performance Testing
```bash
# Install Apache Bench
sudo apt install -y apache2-utils

# Test API performance
ab -n 100 -c 10 https://your-domain.com/rest/v1/

# Test auth endpoint
ab -n 50 -c 5 https://your-domain.com/auth/v1/health
```

## 🚨 Troubleshooting

### Common Issues
```bash
# Port conflicts
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443

# Certificate issues
openssl x509 -in ssl/nginx/certificate.crt -text -noout
sudo nginx -t

# Container issues
sudo docker compose logs nginx
sudo docker compose restart nginx

# Database connection issues
sudo docker compose logs db
sudo docker exec supabase-db pg_isready -U postgres
```

### Recovery Procedures
```bash
# Restore from backup
./restore_backup.sh /path/to/backup/file

# Reset SSL certificates
rm -rf ssl/
./ubuntu_ssl_setup.sh

# Complete reset (careful!)
sudo docker compose down -v
sudo docker system prune -af
# Then redeploy
```

## 📞 Support and Resources

- **Supabase Documentation**: https://supabase.com/docs
- **Docker Documentation**: https://docs.docker.com/
- **Ubuntu Documentation**: https://help.ubuntu.com/
- **Nginx Documentation**: https://nginx.org/en/docs/

## 🎯 Next Steps

1. ✅ Complete SSL setup with `./ubuntu_ssl_setup.sh`
2. ✅ Deploy with `sudo docker compose --profile production up -d`
3. 🔄 Set up monitoring and alerting
4. 🔄 Configure backup schedules
5. 🔄 Implement security hardening
6. 🔄 Set up CI/CD pipeline

Your Supabase installation is now production-ready on Ubuntu 24 LTS! 🎉
