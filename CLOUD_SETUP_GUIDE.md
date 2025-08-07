# Supabase Cloud Backup Setup Guide

This guide covers setting up your preferred cloud storage providers for Supabase backups.

## ✅ Fully Supported Providers

### 1. AWS S3 (Native Support)

**Setup Steps:**
```bash
# 1. Install AWS CLI (automatic via scripts)
# 2. Configure AWS credentials
aws configure

# 3. In config.env, set:
CLOUD_PROVIDER="aws"
AWS_S3_BUCKET="your-backup-bucket"
AWS_REGION="us-east-1"
```

**Features:**
- ✅ Server-side encryption (AES256)
- ✅ Intelligent tiering
- ✅ Upload verification
- ✅ Automatic cleanup

---

### 2. OneDrive (via rclone)

**Setup Steps:**
```bash
# 1. Install rclone (automatic via scripts)
# 2. Configure OneDrive remote
rclone config

# Follow prompts:
# - Choose "Microsoft OneDrive"
# - Authenticate via browser
# - Name your remote (e.g., "onedrive")

# 3. In config.env, set:
CLOUD_PROVIDER="rclone"
RCLONE_REMOTE_NAME="onedrive"
RCLONE_REMOTE_PATH="Apps/Supabase/backups"
```

**Features:**
- ✅ Personal and Business accounts
- ✅ Auto-authentication
- ✅ Progress monitoring
- ✅ Resume capability

---

### 3. Dropbox (via rclone)

**Setup Steps:**
```bash
# 1. Configure Dropbox remote
rclone config

# Follow prompts:
# - Choose "Dropbox"
# - Authenticate via browser
# - Name your remote (e.g., "dropbox")

# 2. In config.env, set:
CLOUD_PROVIDER="rclone"
RCLONE_REMOTE_NAME="dropbox"
RCLONE_REMOTE_PATH="Apps/Supabase"
```

**Features:**
- ✅ Personal and Business accounts
- ✅ File versioning
- ✅ Bandwidth limiting
- ✅ Progress monitoring

---

### 4. Hetzner Object Storage (S3-compatible)

**Setup Steps:**
```bash
# 1. Login to Hetzner Cloud Console
# 2. Go to Object Storage → Create bucket
# 3. Generate access credentials

# 4. In config.env, set:
CLOUD_PROVIDER="hetzner"
HETZNER_S3_BUCKET="your-bucket-name"
HETZNER_S3_ENDPOINT="https://fsn1.your-objectstorage.com"
HETZNER_S3_REGION="fsn1"
HETZNER_ACCESS_KEY="your-access-key"
HETZNER_SECRET_KEY="your-secret-key"
```

**Features:**
- ✅ S3-compatible API
- ✅ European data centers
- ✅ Competitive pricing
- ✅ Upload verification

---

### 5. Hetzner Storage Box (SFTP)

**Setup Steps:**
```bash
# 1. Login to Hetzner Robot Console
# 2. Order Storage Box or use existing
# 3. Note your SFTP credentials

# 4. In config.env, set:
CLOUD_PROVIDER="hetzner-sftp"
HETZNER_STORAGEBOX_HOST="your-backup.your-storagebox.de"
HETZNER_STORAGEBOX_USER="your-username"
HETZNER_STORAGEBOX_PASS="your-password"
HETZNER_STORAGEBOX_PATH="/backups/supabase"
```

**Features:**
- ✅ SFTP protocol
- ✅ Large storage capacity
- ✅ European data centers
- ✅ SSH key authentication support

---

## 🚀 Multi-Cloud Setup (Recommended)

For maximum redundancy, you can backup to multiple providers simultaneously:

```bash
# In config.env, set:
MULTI_CLOUD_ENABLED=true
MULTI_CLOUD_PROVIDERS="aws,onedrive,hetzner"

# Configure each provider as described above
```

**Benefits:**
- 🛡️ **Redundancy**: Multiple backup locations
- 🌍 **Geographic distribution**: Data in different regions
- 💰 **Cost optimization**: Mix of storage types
- ⚡ **Performance**: Fastest available provider for restores

---

## 📋 Quick Configuration Commands

### Interactive Setup
```bash
./setup_notifications.sh
```

### Test Configuration
```bash
# Test cloud connectivity
./cloud_backup.sh --test

# Test with actual backup
./backup_supabase.sh
```

### Manual Configuration
```bash
# Copy and edit config
cp config.env.example config.env
nano config.env
```

---

## 🔧 Advanced Configuration

### Custom rclone Configuration

For advanced rclone setups (custom endpoints, encryption, etc.):

```bash
# Advanced rclone config
rclone config

# Example: Encrypted remote
rclone config create mycrypt crypt remote=onedrive:encrypted password=mypassword

# Use encrypted remote
RCLONE_REMOTE_NAME="mycrypt"
```

### AWS S3 with Custom Endpoint

For S3-compatible services other than AWS:

```bash
# Example: DigitalOcean Spaces
export AWS_ENDPOINT_URL="https://fra1.digitaloceanspaces.com"
```

### Bandwidth Limiting

```bash
# In rclone config or via flags
rclone config set myremote bwlimit 10M
```

---

## 🔍 Monitoring and Logs

### View Upload Progress
```bash
tail -f /var/log/supabase/cloud_backup.log
```

### Check Backup Status
```bash
./health_check.sh
```

### Manual Cleanup
```bash
./cloud_backup.sh --cleanup
```

---

## 💡 Tips and Best Practices

1. **Start with rclone** for OneDrive/Dropbox - it's the most flexible
2. **Use multi-cloud** for critical data - redundancy is key
3. **Test restores regularly** - verify your backups work
4. **Monitor costs** - cloud storage can add up
5. **Use compression** - reduce transfer time and storage costs
6. **Set up notifications** - know when backups succeed/fail

---

## 🆘 Troubleshooting

### Common Issues

**rclone authentication fails:**
```bash
rclone config reconnect remotename
```

**AWS credentials not found:**
```bash
aws configure list
export AWS_PROFILE=default
```

**Hetzner endpoint errors:**
```bash
# Verify endpoint URL format
curl -I https://fsn1.your-objectstorage.com
```

**SFTP connection timeouts:**
```bash
# Test SFTP connection
sftp user@your-backup.your-storagebox.de
```

---

## 📞 Support

For provider-specific issues:
- **AWS**: [AWS Support](https://aws.amazon.com/support/)
- **Hetzner**: [Hetzner Docs](https://docs.hetzner.com/)
- **rclone**: [rclone Forum](https://forum.rclone.org/)

For script issues:
```bash
# Enable debug logging
export DEBUG=1
./cloud_backup.sh --test
```
