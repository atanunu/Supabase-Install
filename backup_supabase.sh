#!/bin/bash
# backup_supabase.sh - Enhanced database backup script with compression and retention
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️  Config file not found. Using defaults..."
    BACKUP_DIR="/var/backups/supabase"
    LOG_DIR="/var/log/supabase"
    DB_CONTAINER_NAME="supabase-db"
    DB_USER="postgres"
    DB_NAME="postgres"
    BACKUP_RETENTION_DAYS=30
    BACKUP_COMPRESSION=true
fi

# Create directories if they don't exist
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Logging setup
LOG_FILE="${LOG_DIR}/backup.log"
DATE=$(date +%F-%H-%M-%S)
FILENAME="supabase_backup_${DATE}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "❌ BACKUP FAILED: $1"
    send_notification "FAILED" "Backup failed: $1"
    exit 1
}

# Success notification
backup_success() {
    log "✅ BACKUP COMPLETED: $1"
    send_notification "SUCCESS" "Backup completed successfully: $1"
}

# Send notification (webhook, email, etc.)
send_notification() {
    local status="$1"
    local message="$2"
    
    # Use the notification script if available
    if [[ -f "${SCRIPT_DIR}/notify.sh" ]]; then
        "${SCRIPT_DIR}/notify.sh" "Supabase Backup" "$message" "$status" 2>/dev/null || true
    fi
    
    # Legacy webhook support
    if [[ "${NOTIFICATION_ENABLED:-false}" == "true" ]]; then
        if [[ -n "${WEBHOOK_URL:-}" ]]; then
            curl -s -X POST "$WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "{\"text\": \"[$status] Supabase Backup: $message\"}" || true
        fi
        
        if [[ -n "${BACKUP_NOTIFICATION_EMAIL:-}" ]]; then
            echo "$message" | mail -s "[$status] Supabase Backup" "$BACKUP_NOTIFICATION_EMAIL" || true
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker is not running or not accessible"
    fi
    
    # Check if database container exists and is running
    if ! docker ps --format "table {{.Names}}" | grep -q "^${DB_CONTAINER_NAME}$"; then
        error_exit "Database container '${DB_CONTAINER_NAME}' is not running"
    fi
    
    # Check available disk space (minimum 1GB)
    available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then
        error_exit "Insufficient disk space in backup directory. At least 1GB required."
    fi
    
    log "✅ Prerequisites check passed"
}

# Get database size
get_db_size() {
    local size_bytes
    size_bytes=$(docker exec "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT pg_database_size('$DB_NAME');" | tr -d ' ')
    echo $((size_bytes / 1024 / 1024)) # Convert to MB
}

# Create database backup
create_backup() {
    log "🗄️  Starting database backup..."
    
    local db_size_mb
    db_size_mb=$(get_db_size)
    log "📊 Database size: ${db_size_mb}MB"
    
    # Create SQL dump
    local backup_file="${BACKUP_DIR}/${FILENAME}.sql"
    
    if docker exec "$DB_CONTAINER_NAME" pg_dump -U "$DB_USER" -d "$DB_NAME" --verbose > "$backup_file" 2>>"$LOG_FILE"; then
        log "✅ SQL dump created: $backup_file"
    else
        error_exit "Failed to create SQL dump"
    fi
    
    # Compress backup if enabled
    if [[ "${BACKUP_COMPRESSION}" == "true" ]]; then
        log "🗜️  Compressing backup..."
        
        if gzip "$backup_file"; then
            backup_file="${backup_file}.gz"
            log "✅ Backup compressed: $backup_file"
        else
            error_exit "Failed to compress backup"
        fi
    fi
    
    # Get final backup size
    local backup_size_mb
    backup_size_mb=$(du -m "$backup_file" | cut -f1)
    
    log "📁 Final backup size: ${backup_size_mb}MB"
    log "💾 Backup saved to: $backup_file"
    
    # Verify backup integrity
    verify_backup "$backup_file"
    
    echo "$backup_file"
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    log "🔍 Verifying backup integrity..."
    
    if [[ "$backup_file" == *.gz ]]; then
        if gzip -t "$backup_file" 2>/dev/null; then
            log "✅ Compressed backup integrity verified"
        else
            error_exit "Backup file is corrupted"
        fi
    else
        if [[ -s "$backup_file" ]] && head -n 1 "$backup_file" | grep -q "PostgreSQL database dump"; then
            log "✅ SQL backup integrity verified"
        else
            error_exit "Backup file appears to be corrupted or empty"
        fi
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "🧹 Cleaning up old backups (keeping last ${BACKUP_RETENTION_DAYS} days)..."
    
    local deleted_count=0
    
    # Find and delete old backup files
    while IFS= read -r -d '' file; do
        rm "$file"
        ((deleted_count++))
        log "🗑️  Deleted old backup: $(basename "$file")"
    done < <(find "$BACKUP_DIR" -name "supabase_backup_*.sql*" -type f -mtime +${BACKUP_RETENTION_DAYS} -print0)
    
    if [[ $deleted_count -gt 0 ]]; then
        log "✅ Cleaned up $deleted_count old backup(s)"
    else
        log "ℹ️  No old backups to clean up"
    fi
}

# Monitor disk usage
monitor_disk_usage() {
    if [[ "${MONITOR_DISK_USAGE:-true}" == "true" ]]; then
        local usage_percent
        usage_percent=$(df "$BACKUP_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
        
        log "💿 Disk usage in backup directory: ${usage_percent}%"
        
        if [[ $usage_percent -gt ${DISK_USAGE_THRESHOLD:-80} ]]; then
            log "⚠️  Warning: Disk usage is above ${DISK_USAGE_THRESHOLD:-80}%"
            send_notification "WARNING" "Backup disk usage is at ${usage_percent}%"
        fi
    fi
}

# Upload to cloud storage
upload_to_cloud() {
    local backup_file="$1"
    
    if [[ "${CLOUD_BACKUP_ENABLED:-false}" == "true" ]]; then
        log "☁️  Uploading backup to cloud storage..."
        
        if [[ -f "${SCRIPT_DIR}/cloud_backup.sh" ]]; then
            if "${SCRIPT_DIR}/cloud_backup.sh" "$backup_file"; then
                log "✅ Cloud upload completed successfully"
                return 0
            else
                log "❌ Cloud upload failed"
                send_notification "ERROR" "Cloud backup upload failed for $(basename "$backup_file")"
                return 1
            fi
        else
            log "⚠️  Cloud backup script not found"
            return 1
        fi
    else
        log "ℹ️  Cloud backup is disabled"
        return 0
    fi
}
    
# Create backup manifest
create_manifest() {
    local backup_file="$1"
    local manifest_file="${BACKUP_DIR}/backup_manifest.json"
    
    # Create or update manifest
    cat > "$manifest_file" << EOF
{
  "last_backup": {
    "timestamp": "$(date -Iseconds)",
    "file": "$(basename "$backup_file")",
    "size_bytes": $(stat -c%s "$backup_file"),
    "database_size_mb": $(get_db_size),
    "compressed": $(if [[ "$backup_file" == *.gz ]]; then echo "true"; else echo "false"; fi),
    "cloud_uploaded": $(if [[ "${CLOUD_BACKUP_ENABLED:-false}" == "true" ]]; then echo "true"; else echo "false"; fi)
  },
  "retention_days": ${BACKUP_RETENTION_DAYS},
  "backup_directory": "$BACKUP_DIR",
  "cloud_provider": "${CLOUD_PROVIDER:-none}"
}
EOF
    
    log "📝 Backup manifest updated: $manifest_file"
}
}

# Main backup process
main() {
    local start_time
    start_time=$(date +%s)
    
    log "🚀 Starting Supabase backup process..."
    log "📍 Backup directory: $BACKUP_DIR"
    log "📍 Database container: $DB_CONTAINER_NAME"
    log "📍 Compression enabled: ${BACKUP_COMPRESSION}"
    log "📍 Retention period: ${BACKUP_RETENTION_DAYS} days"
    
    check_prerequisites
    monitor_disk_usage
    
    local backup_file
    backup_file=$(create_backup)
    
    cleanup_old_backups
    upload_to_cloud "$backup_file"
    create_manifest "$backup_file"
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    backup_success "Duration: ${duration}s, File: $(basename "$backup_file")"
    
    log "🎉 Backup process completed successfully in ${duration} seconds!"
    log "📊 Summary:"
    log "   - Backup file: $(basename "$backup_file")"
    log "   - File size: $(du -h "$backup_file" | cut -f1)"
    log "   - Duration: ${duration} seconds"
    log "   - Log file: $LOG_FILE"
}

# Trap errors and cleanup
trap 'error_exit "Script interrupted"' INT TERM

# Run main function
main "$@"
