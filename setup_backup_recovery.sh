#!/bin/bash
# Quick deployment script for backup and recovery on Ubuntu 24 LTS

set -euo pipefail

echo "🔄 Deploying Comprehensive Backup & Recovery System..."

# Make deployment script executable
chmod +x deploy_backup_recovery.sh

# Run deployment with logging
./deploy_backup_recovery.sh deploy 2>&1 | tee backup_deployment.log

echo "
✅ Backup and Recovery System Deployed!

🚀 Quick Commands:
- Full backup: supabase-backup full
- PITR restore: supabase-wal restore '2024-01-15 14:30:00' time
- Test backups: supabase-validate 
- Cross-region sync: supabase-sync

📋 Check status:
- Services: docker ps | grep backup
- Logs: tail -f /var/log/backup_*.log

📖 Recovery procedures: backup_recovery/DISASTER_RECOVERY_PROCEDURES.md
"
