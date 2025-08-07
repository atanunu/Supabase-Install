# 🚀 Enterprise Supabase Deployment Suite

[![Production Ready](https://img.shields.io/badge/Production-Ready-brightgreen.svg)](https://github.com/atanunu/Supabase-Install)
[![Security Grade](https://img.shields.io/badge/Security-A+-blue.svg)](https://github.com/atanunu/Supabase-Install)
[![Deployment Time](https://img.shields.io/badge/Deploy%20Time-5%20minutes-orange.svg)](https://github.com/atanunu/Supabase-Install)
[![Web Interface](https://img.shields.io/badge/Web%20Interface-Included-purple.svg)](https://github.com/atanunu/Supabase-Install)

Complete enterprise-grade Supabase deployment solution with professional web management interface, automated security hardening, and production-ready monitoring stack.

## 🎯 **Quick Start (5 Minutes to Production)**

### **Option 1: One-Command Web Interface Deployment**
```bash
# Clone and deploy web interface
git clone https://github.com/atanunu/Supabase-Install.git
cd Supabase-Install
chmod +x quick_web_deploy.sh
sudo ./quick_web_deploy.sh

# Access at: http://YOUR-SERVER-IP
```

### **Option 2: Full Enterprise Deployment**
```bash
# Deploy complete enterprise system
chmod +x deploy_operations.sh
./deploy_operations.sh deploy

# Access web interface: https://your-domain.com
```

## 📋 **Complete Step-by-Step Server Setup**

### **Prerequisites**
- Ubuntu 20.04+ / CentOS 8+ / RHEL 8+ / Debian 11+
- Minimum 4GB RAM, 20GB disk space
- Root or sudo access
- Domain name (optional but recommended)

### **Step 1: Prepare Your Server**

#### 1.1 Update System
```bash
# Update package lists and upgrade system
sudo apt update && sudo apt upgrade -y

# Install essential tools
sudo apt install -y curl wget git unzip htop
```

#### 1.2 Create Project Directory
```bash
# Create project directory
sudo mkdir -p /opt/supabase
sudo chown $USER:$USER /opt/supabase
cd /opt/supabase
```

### **Step 2: Clone and Setup Project**

#### 2.1 Clone Repository
```bash
# Clone the repository
git clone https://github.com/atanunu/Supabase-Install.git .

# Make all scripts executable
chmod +x *.sh
```

#### 2.2 Run Server Preparation (Automated)
```bash
# Option A: Basic server preparation
sudo ./prepare_server.sh

# Option B: With SSL certificate setup
sudo ./prepare_server.sh --setup-ssl --domain yourdomain.com --email admin@yourdomain.com

# Option C: Custom configuration
sudo ./prepare_server.sh --no-firewall --domain yourdomain.com --email admin@yourdomain.com
```

### **Step 3: Configure Environment Variables**

#### 3.1 Copy Production Environment Template
```bash
# Copy the production environment template
cp .env.production .env

# Open for editing
nano .env
```

#### 3.2 Required Configuration Changes
Edit these essential variables in `.env`:

```bash
# Domain Configuration
SITE_URL=https://yourdomain.com
API_EXTERNAL_URL=https://yourdomain.com

# Database Security (Generate strong passwords)
POSTGRES_PASSWORD=your_super_secure_postgres_password_here

# JWT Configuration (Generate 32+ character secret)
JWT_SECRET=your_jwt_secret_256_bit_minimum_length_here

# API Keys (Generate from Supabase CLI or Dashboard)
ANON_KEY=your_anon_key_here
SERVICE_ROLE_KEY=your_service_role_key_here

# Email Configuration
SMTP_ADMIN_EMAIL=admin@yourdomain.com
SMTP_HOST=smtp.yourdomain.com
SMTP_USER=noreply@yourdomain.com
SMTP_PASS=your_smtp_password
SMTP_SENDER_NAME="Your App Name"

# Dashboard Security
DASHBOARD_PASSWORD=your_dashboard_password_here
GRAFANA_ADMIN_PASSWORD=your_grafana_password
```

#### 3.3 Generate Secure Keys
```bash
# Generate PostgreSQL password
openssl rand -base64 32

# Generate JWT secret
openssl rand -base64 32

# Generate backup encryption key
openssl rand -base64 32
```

#### 3.4 Complete Configuration Examples

**For Development/Testing:**
```bash
# Basic configuration for testing
SITE_URL=http://localhost
API_EXTERNAL_URL=http://localhost:8000
POSTGRES_PASSWORD=dev_password_123
JWT_SECRET=dev_jwt_secret_minimum_32_characters
DASHBOARD_PASSWORD=admin123
DISABLE_SIGNUP=false
DEBUG=true
```

**For Production:**
```bash
# Production configuration example
SITE_URL=https://myapp.example.com
API_EXTERNAL_URL=https://myapp.example.com
POSTGRES_PASSWORD=P@ssw0rd_Gener4ted_Fr0m_0penSSL
JWT_SECRET=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9_generated_secret
ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB0a2h3cWl3eXdxcnduZmNlOWV0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE2NDE0Mjk5MzQsImV4cCI6MTk1NzAwNTkzNH0.secret
SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB0a2h3cWl3eXdxcnduZmNlOWV0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTY0MTQyOTkzNCwiZXhwIjoxOTU3MDA1OTM0fQ.secret
DASHBOARD_PASSWORD=Str0ng_D4shb0ard_P@ssw0rd
GRAFANA_ADMIN_PASSWORD=Gr4f4n4_Adm1n_P@ss
DISABLE_SIGNUP=true
DEBUG=false
ENABLE_AUDIT_LOGS=true
ENABLE_WAF=true
```

**Email Configuration Examples:**

*Gmail SMTP:*
```bash
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=yourapp@gmail.com
SMTP_PASS=your_app_password
SMTP_SENDER_NAME="Your App Name"
```

*AWS SES:*
```bash
SMTP_HOST=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_USER=AKIA...
SMTP_PASS=BLfG...
SMTP_SENDER_NAME="Your App Name"
```

*SendGrid:*
```bash
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=SG.your_sendgrid_api_key
SMTP_SENDER_NAME="Your App Name"
```

**Storage Configuration Examples:**

*Local File Storage:*
```bash
STORAGE_BACKEND=file
STORAGE_FILE_SIZE_LIMIT=52428800
FILE_SIZE_LIMIT=50MB
```

*AWS S3 Storage:*
```bash
STORAGE_BACKEND=s3
STORAGE_S3_BUCKET=your-supabase-storage
STORAGE_S3_REGION=us-east-1
STORAGE_S3_ENDPOINT=https://s3.amazonaws.com
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=your_secret_key
```

**Monitoring Configuration:**
```bash
# Prometheus
PROMETHEUS_PORT=9090
PROMETHEUS_RETENTION=30d

# Grafana
GRAFANA_PORT=3000
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=secure_grafana_password

# Logging
LOG_LEVEL=info
ENABLE_AUDIT_LOGS=true
```

#### 3.5 Validate Configuration
```bash
# Check configuration syntax
./validate_deployment.sh --config-only

# Test database connection
docker-compose exec db psql -U postgres -c "SELECT version();"

# Test SMTP configuration
./notify.sh "Test email" "info" "Test message from Supabase"
```

### **Step 4: Deploy Supabase**

#### 4.1 Standard Deployment
```bash
# Deploy using the installation script
./install_supabase.sh
```

#### 4.2 Production Deployment with Monitoring
```bash
# Deploy complete enterprise system
./deploy_operations.sh deploy
```

#### 4.3 SSH Deployment (For Remote Servers)
```bash
# Deploy to remote server via SSH
./deploy_ssh.sh --server your-server.com --key ~/.ssh/production.pem
```

### **Step 5: Verify Deployment**

#### 5.1 Check Service Status
```bash
# Check if all containers are running
docker-compose ps

# View service logs
docker-compose logs --tail=50

# Check individual service
docker-compose logs -f kong
```

#### 5.2 Run Health Check
```bash
# Basic health check
./health_check.sh

# Enhanced health check with metrics
./health_check_enhanced.sh

# Production deployment validation
./validate_deployment.sh --production
```

#### 5.3 Test Web Interface
```bash
# Check if web interface is accessible
curl http://localhost
curl https://yourdomain.com

# Check API endpoints
curl http://localhost:8000/rest/v1/
curl http://localhost:9999/health
```

### **Step 6: Configure SSL (If Not Done Automatically)**

#### 6.1 Install Certbot
```bash
# Install Certbot for Let's Encrypt
sudo apt install certbot python3-certbot-nginx -y
```

#### 6.2 Obtain SSL Certificate
```bash
# Stop nginx temporarily
sudo systemctl stop nginx

# Obtain certificate
sudo certbot certonly --standalone -d yourdomain.com --email admin@yourdomain.com --agree-tos --non-interactive

# Copy certificates to project
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ./ssl/
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ./ssl/
sudo chown $USER:$USER ./ssl/*
```

#### 6.3 Setup Auto-Renewal
```bash
# Add auto-renewal to crontab
echo "0 12 * * * /usr/bin/certbot renew --quiet" | sudo crontab -
```

### **Step 7: Setup Monitoring and Backups**

#### 7.1 Configure Monitoring
```bash
# Deploy monitoring stack
./implement_monitoring.sh

# Setup performance monitoring
./implement_performance.sh
```

#### 7.2 Setup Automated Backups
```bash
# Configure backup system
./setup_backup_recovery.sh

# Test backup functionality
./backup_supabase.sh
```

#### 7.3 Setup Notifications
```bash
# Interactive notification setup
./setup_notifications.sh

# Test notifications
./notify.sh "Test notification" "success"
```

### **Step 8: Configure Automated Tasks**

#### 8.1 Setup Cron Jobs
```bash
# Install the provided crontab
sudo crontab -u root crontab

# Or manually add cron jobs
sudo crontab -e

# Add these lines:
# Daily backup at 2:00 AM
0 2 * * * /opt/supabase/backup_supabase.sh

# Weekly health check at 3:00 AM Sunday
0 3 * * 0 /opt/supabase/health_check_enhanced.sh

# Monthly cleanup at 4:00 AM first day of month
0 4 1 * * /opt/supabase/cleanup_old_backups.sh
```

#### 8.2 Setup Log Rotation
```bash
# Create log rotation configuration
sudo tee /etc/logrotate.d/supabase << EOF
/opt/supabase/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
}
EOF
```

### **Step 9: Security Hardening**

#### 9.1 Configure Firewall
```bash
# Enable UFW firewall
sudo ufw enable

# Allow essential ports
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check firewall status
sudo ufw status
```

#### 9.2 Setup Security Scanning
```bash
# Run security scan
./security_scan.sh

# Configure MFA (if needed)
./setup_mfa.sh
```

#### 9.3 Harden Database
```bash
# Connect to database and change passwords
docker-compose exec db psql -U postgres

# Inside PostgreSQL:
ALTER USER postgres PASSWORD 'your_new_secure_password';
\q
```

### **Step 10: Final Verification and Testing**

#### 10.1 Complete System Test
```bash
# Run comprehensive validation
./validate_deployment.sh --production --verbose

# Test all endpoints
curl -H "apikey: YOUR_ANON_KEY" https://yourdomain.com/rest/v1/
curl https://yourdomain.com/auth/v1/settings
curl https://yourdomain.com/storage/v1/
```

#### 10.2 Performance Testing
```bash
# Run performance tests
./test_performance.sh

# Monitor resource usage
docker stats
htop
```

#### 10.3 Backup Testing
```bash
# Test backup creation
./backup_supabase.sh

# Test backup restoration (in test environment)
./restore_backup.sh backup_20250807_020000.sql
```

### **🎉 Deployment Complete!**

Your Supabase Enterprise deployment is now ready. Access your services at:

- **Main Application**: https://yourdomain.com
- **Management Interface**: https://yourdomain.com/admin
- **API Endpoint**: https://yourdomain.com/rest/v1/
- **Grafana Monitoring**: https://yourdomain.com:3000
- **Health Check**: https://yourdomain.com/health

## 🔄 **Maintenance and Updates**

### **Regular Maintenance Tasks**

#### Daily
```bash
# Check system health
./health_check_enhanced.sh

# Monitor disk space
df -h

# Check service status
docker-compose ps
```

#### Weekly
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Docker images
docker-compose pull
docker-compose up -d

# Check backup integrity
./verify_backups.sh
```

#### Monthly
```bash
# Full system update
./update_supabase_enhanced.sh

# Security scan
./security_scan.sh

# Performance review
./test_performance.sh

# Clean old logs and backups
find /var/log -name "*.log" -type f -mtime +30 -delete
find /var/backups -name "*.sql" -type f -mtime +90 -delete
```

### **Update Procedures**

#### Update Supabase
```bash
# Standard update
./update_supabase.sh

# Enhanced update with rollback capability
./update_supabase_enhanced.sh

# Manual update
git pull origin main
docker-compose pull
docker-compose up -d
```

#### Update SSL Certificates
```bash
# Automatic renewal (runs via cron)
sudo certbot renew

# Manual renewal
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

#### Update Monitoring Stack
```bash
# Update Grafana dashboards
./update_monitoring_dashboards.sh

# Update Prometheus rules
./update_prometheus_rules.sh
```

### **Backup and Recovery**

#### Create Manual Backup
```bash
# Full system backup
./backup_supabase.sh

# Database only backup
docker-compose exec db pg_dump -U postgres postgres > backup_$(date +%Y%m%d).sql

# Configuration backup
tar -czf config_backup_$(date +%Y%m%d).tar.gz .env docker-compose*.yml
```

#### Restore from Backup
```bash
# List available backups
ls -la /var/backups/supabase/

# Restore from specific backup
./restore_backup.sh /var/backups/supabase/backup_20250807_020000.sql

# Emergency restore
docker-compose down
docker volume rm supabase_db_data
docker-compose up -d db
# Wait for database to start
./restore_backup.sh /path/to/backup.sql
```

### **Monitoring and Alerts**

#### Check System Health
```bash
# Comprehensive health check
./health_check_enhanced.sh

# API endpoint monitoring
curl -f https://yourdomain.com/health || echo "API Down"

# Database connection test
docker-compose exec db pg_isready -U postgres || echo "Database Down"
```

#### Setup Alerts
```bash
# Configure email alerts
./setup_notifications.sh

# Test alert system
./notify.sh "System Alert Test" "warning" "Testing alert system"

# Setup monitoring alerts in Grafana
# Access: https://yourdomain.com:3000
# Default: admin / your_grafana_password
```

### **Performance Optimization**

#### Database Optimization
```bash
# Run database vacuum
docker-compose exec db psql -U postgres -c "VACUUM ANALYZE;"

# Check slow queries
docker-compose exec db psql -U postgres -c "
SELECT query, mean_time, calls 
FROM pg_stat_statements 
ORDER BY mean_time DESC 
LIMIT 10;"

# Update database statistics
docker-compose exec db psql -U postgres -c "ANALYZE;"
```

#### System Optimization
```bash
# Check resource usage
htop
docker stats

# Optimize Docker containers
docker system prune -f

# Check network performance
iftop
netstat -i
```

### **Security Maintenance**

#### Security Updates
```bash
# System security updates
sudo apt update && sudo apt upgrade -y

# Security audit
./security_scan.sh

# Check for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/tmp anchore/grype:latest /tmp
```

#### Access Management
```bash
# Review user access
docker-compose exec db psql -U postgres -c "SELECT * FROM auth.users;"

# Update admin passwords
docker-compose exec db psql -U postgres -c "
UPDATE auth.users SET encrypted_password = crypt('new_password', gen_salt('bf'))
WHERE email = 'admin@yourdomain.com';"

# Check failed login attempts
grep "failed" /var/log/auth.log
```

### **Troubleshooting Quick Reference**

#### Service Issues
```bash
# Restart all services
docker-compose restart

# Restart specific service
docker-compose restart [service-name]

# View service logs
docker-compose logs -f [service-name]

# Check service health
curl http://localhost:8000/health
```

#### Database Issues
```bash
# Check database status
docker-compose exec db pg_isready -U postgres

# Connect to database
docker-compose exec db psql -U postgres

# Check database size
docker-compose exec db psql -U postgres -c "
SELECT pg_size_pretty(pg_database_size('postgres'));"
```

#### Network Issues
```bash
# Check port availability
netstat -tulpn | grep :80
netstat -tulpn | grep :443

# Test DNS resolution
nslookup yourdomain.com

# Check firewall rules
sudo ufw status verbose
```
   # Add contents from crontab file
   ```

## �️ **Troubleshooting Guide**

### **Common Issues and Solutions**

#### **Issue 1: Docker Installation Fails**
```bash
# Remove old Docker versions
sudo apt remove docker docker-engine docker.io containerd runc

# Install Docker using official script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER
logout
# Log back in
```

#### **Issue 2: Port Already in Use**
```bash
# Check what's using the port
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443
sudo netstat -tulpn | grep :5432

# Stop conflicting services
sudo systemctl stop apache2
sudo systemctl stop nginx
sudo systemctl stop postgresql

# Or change ports in docker-compose.yml
```

#### **Issue 3: Permission Denied Errors**
```bash
# Fix file permissions
sudo chown -R $USER:$USER /opt/supabase
chmod +x /opt/supabase/*.sh

# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock
```

#### **Issue 4: SSL Certificate Issues**
```bash
# Check certificate status
sudo certbot certificates

# Renew certificates manually
sudo certbot renew --dry-run
sudo certbot renew --force-renewal

# Fix certificate permissions
sudo chmod 644 /etc/letsencrypt/live/yourdomain.com/fullchain.pem
sudo chmod 600 /etc/letsencrypt/live/yourdomain.com/privkey.pem
```

#### **Issue 5: Database Connection Issues**
```bash
# Check PostgreSQL container
docker-compose logs db

# Reset database container
docker-compose stop db
docker-compose rm db
docker volume rm supabase_db_data
docker-compose up -d db

# Test database connection
docker-compose exec db psql -U postgres -c "SELECT version();"
```

#### **Issue 6: Services Won't Start**
```bash
# Check container status
docker-compose ps

# View service logs
docker-compose logs [service-name]

# Restart specific service
docker-compose restart [service-name]

# Rebuild and restart all services
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

#### **Issue 7: Firewall Blocking Connections**
```bash
# Check firewall status
sudo ufw status verbose

# Allow required ports
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw allow 8000/tcp # Kong API
sudo ufw allow 3000/tcp # Grafana

# Reset firewall if needed
sudo ufw --force reset
sudo ufw enable
```

#### **Issue 8: Out of Disk Space**
```bash
# Check disk usage
df -h
du -sh /opt/supabase/*

# Clean Docker system
docker system prune -a
docker volume prune

# Clean old logs
sudo find /var/log -name "*.log" -type f -mtime +30 -delete
```

#### **Issue 9: Memory Issues**
```bash
# Check memory usage
free -h
docker stats

# Optimize Docker memory usage
# Edit /etc/docker/daemon.json
{
  "default-ulimits": {
    "memlock": {
      "Hard": -1,
      "Name": "memlock",
      "Soft": -1
    }
  }
}

# Restart Docker
sudo systemctl restart docker
```

#### **Issue 10: Backup Failures**
```bash
# Check backup script permissions
chmod +x backup_supabase.sh

# Test backup manually
./backup_supabase.sh

# Check backup directory permissions
sudo mkdir -p /var/backups/supabase
sudo chown $USER:$USER /var/backups/supabase

# Check database connectivity
docker-compose exec db pg_isready -U postgres
```

### **Health Check Commands**

```bash
# Quick system check
./health_check.sh

# Detailed health check
./health_check_enhanced.sh

# Validate entire deployment
./validate_deployment.sh --production

# Check individual components
curl http://localhost:8000/health    # Kong
curl http://localhost:9999/health    # Auth
curl http://localhost:3000/rest/v1/  # PostgREST
curl http://localhost:4000/api/health # Realtime
```

### **Log Locations**

```bash
# Application logs
tail -f /opt/supabase/logs/supabase.log

# Docker container logs
docker-compose logs -f [service-name]

# System logs
sudo tail -f /var/log/syslog
sudo tail -f /var/log/auth.log

# Nginx logs (if using reverse proxy)
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### **Performance Monitoring**

```bash
# Monitor resource usage
htop
docker stats

# Check database performance
docker-compose exec db psql -U postgres -c "
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';"

# Monitor API response times
curl -w "Time: %{time_total}s
" -o /dev/null -s http://localhost:8000/rest/v1/
```

### **Emergency Recovery**

```bash
# Complete system reset (WARNING: This will delete all data)
docker-compose down -v
docker system prune -a
rm -rf /opt/supabase
# Re-run installation from Step 2

# Restore from backup
./restore_backup.sh /path/to/backup.sql

# Rollback to previous version
git checkout HEAD~1
docker-compose down
docker-compose build
docker-compose up -d
```

## 📚 Documentation

### Required Environment Variables
```bash
# Database
POSTGRES_PASSWORD=your_secure_password
POSTGRES_DB=postgres

# Authentication
JWT_SECRET=your_jwt_secret_at_least_32_characters_long
ANON_KEY=your_anon_key
SERVICE_ROLE_KEY=your_service_role_key

# Site Configuration
SITE_URL=https://your-domain.com
API_EXTERNAL_URL=https://your-api-domain.com

# Email (optional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
```

### Path Configuration
Edit these paths in the scripts to match your setup:
- `INSTALL_DIR`: Where Supabase will be installed
- `BACKUP_DIR`: Where backups will be stored
- `LOG_DIR`: Where logs will be stored

## 📁 Project Structure

```
SupabaseInstall/
├── install_supabase.sh     # One-time installation script
├── backup_supabase.sh      # Database backup script with cloud upload
├── cloud_backup.sh         # Cloud backup utility (rclone, AWS, GCP, Azure)
├── notify.sh              # Comprehensive notification system
├── setup_notifications.sh # Interactive setup for notifications/cloud
├── update_supabase.sh      # Update and restart script
├── crontab                 # Cron job configuration
├── config.env             # Configuration file
├── docker-compose.override.yml  # Custom Docker configuration
└── README.md              # This file
```

## 🔧 Scripts Overview

### install_supabase.sh
- Installs Docker and dependencies
- Clones Supabase repository
- Sets up initial configuration
- Creates necessary directories

### backup_supabase.sh
- Creates timestamped database backups
- Compresses backups to save space
- Manages backup retention (keeps last 30 days)
- Uploads to cloud storage (rclone, AWS S3, GCP, Azure)
- Sends notifications on success/failure
- Verifies backup integrity

### cloud_backup.sh
- Supports multiple cloud providers (rclone, AWS S3, Google Cloud, Azure)
- Automatic installation of required tools
- Upload verification and integrity checks
- Automated cleanup of old cloud backups
- Comprehensive error handling and logging

### notify.sh
- Multi-channel notifications (Email, Slack, Telegram, Discord, Teams)
- Configurable message formatting
- Status-based color coding
- Test functionality for all channels
- Easy integration with all scripts

### setup_notifications.sh
- Interactive setup for all notification channels
- Cloud backup configuration wizard
- Configuration validation and testing
- Step-by-step guidance for external service setup

### update_supabase.sh
- Updates Supabase to latest version
- Gracefully stops services
- Pulls latest Docker images
- Restarts services with health checks

## 📅 Scheduled Tasks

The crontab file includes:
- **Daily backups** at 2:00 AM
- **Weekly updates** on Sunday at 3:00 AM
- **Monthly cleanup** of old backups

## 🔍 Monitoring

Logs are stored in:
- Installation: `/var/log/supabase/install.log`
- Backups: `/var/log/supabase/backup.log`
- Updates: `/var/log/supabase/update.log`

## 🔔 Notifications

The system supports multiple notification channels:

### Email Notifications
- SMTP support for Gmail, Outlook, and custom servers
- HTML and plain text formatting
- Priority levels and custom subjects

### Slack Integration
- Webhook-based notifications
- Rich message formatting with attachments
- Channel and username customization
- Status-based color coding

### Telegram Bot
- Real-time notifications via Telegram bot
- Markdown formatting support
- Chat ID-based targeting
- Emoji status indicators

### Discord Webhooks
- Rich embed messages
- Color-coded status alerts
- Server integration via webhooks
- Timestamp and server information

### Microsoft Teams
- MessageCard format for rich notifications
- Theme color based on alert status
- Integration with Teams channels
- Professional formatting

## ☁️ Cloud Backup

### Supported Providers

#### rclone (Recommended)
- Supports 40+ cloud storage providers
- Google Drive, Dropbox, OneDrive, Box, etc.
- Automatic encryption and compression
- Resume interrupted transfers
- Bandwidth limiting and progress monitoring

#### AWS S3
- Server-side encryption (AES256)
- Intelligent tiering for cost optimization
- Cross-region replication support
- Lifecycle policies for automated cleanup

#### Google Cloud Storage
- Multi-regional storage options
- Nearline and Coldline storage classes
- Strong consistency guarantees
- Integration with Google Cloud ecosystem

#### Azure Blob Storage
- Hot, cool, and archive access tiers
- Immutable blob storage options
- Integration with Azure ecosystem
- Geo-redundant storage options

### Features
- **Automatic Upload**: Seamless integration with backup process
- **Integrity Verification**: Hash-based verification of uploaded files
- **Retention Management**: Automatic cleanup of old cloud backups
- **Resume Capability**: Resume interrupted uploads
- **Compression**: Automatic compression before upload
- **Monitoring**: Upload progress and status reporting

### Common Issues

1. **Permission Denied**
   ```bash
   sudo chmod +x *.sh
   ```

2. **Docker Not Found**
   ```bash
   sudo systemctl start docker
   sudo systemctl enable docker
   ```

3. **Port Conflicts**
   - Check if ports 3000, 8000, 5432 are available
   - Modify `docker-compose.override.yml` if needed

4. **Backup Failures**
   - Check disk space in backup directory
   - Verify database container is running
   - Check database credentials

### Health Checks

Check service status:
```bash
cd supabase/docker
docker compose ps
docker compose logs
```

## � Documentation

Complete documentation is available in the [`documentation/`](./documentation/) folder:

| Guide | Description |
|-------|-------------|
| [**SSH Deployment Guide**](./documentation/DEPLOYMENT_GUIDE.md) | Complete production deployment via SSH |
| [**Production Guide**](./documentation/PRODUCTION_GUIDE.md) | Enterprise production configuration |
| [**Performance Guide**](./documentation/PERFORMANCE_README.md) | Performance optimization and tuning |
| [**Operations Guide**](./documentation/OPERATIONS_COMPLETE.md) | Operational capabilities and procedures |
| [**Cloud Setup Guide**](./documentation/CLOUD_SETUP_GUIDE.md) | Cloud provider deployment |
| [**Web Deployment Guide**](./documentation/WEB_DEPLOYMENT_GUIDE.md) | Web interface deployment |
| [**Best Practices**](./documentation/RECOMMENDATIONS.md) | Security and operational recommendations |

👉 **[Browse All Documentation](./documentation/README.md)**

## �🔒 Security Considerations

- Use strong passwords for all services
- Enable firewall and limit exposed ports
- Regularly update the system and Docker
- Monitor logs for suspicious activity
- Use HTTPS in production

## 📞 Support

For issues:
1. Check the logs in `/var/log/supabase/`
2. Verify Docker container status
3. Check Supabase documentation
4. Review this README for common solutions
5. **Consult the [comprehensive documentation](./documentation/README.md)**
