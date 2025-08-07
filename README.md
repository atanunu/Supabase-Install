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
   ```

2. **Configure Environment**
   - Edit `.env` file in the supabase/docker directory
   - Set required variables (see Configuration section)

3. **Start Supabase**
   ```bash
   cd supabase/docker
   docker compose up -d
   ```

4. **Setup Notifications and Cloud Backup**
   ```bash
   ./setup_notifications.sh
   ```

5. **Setup Automated Tasks**
   ```bash
   sudo crontab -e
   # Add contents from crontab file
   ```

## 📋 Configuration

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
