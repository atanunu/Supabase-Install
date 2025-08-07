#!/bin/bash
# Comprehensive Backup Manager for Supabase PostgreSQL
# Handles full backups, WAL archiving, and PITR setup

set -euo pipefail

# Configuration
BACKUP_DIR="/backups"
WAL_ARCHIVE_DIR="/wal_archive"
LOG_FILE="/var/log/backup_manager.log"
DATE=$(date +%Y%m%d_%H%M%S)
HOSTNAME=$(hostname)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create required directories
mkdir -p "$BACKUP_DIR" "$WAL_ARCHIVE_DIR"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log "Starting backup manager..."

# Function to perform full PostgreSQL backup
perform_full_backup() {
    local backup_name="full_backup_${DATE}.sql.gz"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Starting full backup: $backup_name"
    
    # Create backup with compression
    pg_dump \
        -h postgres \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --verbose \
        --no-password \
        --format=custom \
        --compress=9 \
        --lock-wait-timeout=300000 \
        --file="$backup_path.custom"
    
    # Also create SQL dump for easier restoration testing
    pg_dump \
        -h postgres \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        --verbose \
        --no-password \
        --format=plain \
        --no-owner \
        --no-privileges | gzip > "$backup_path"
    
    # Verify backup integrity
    if gzip -t "$backup_path" && pg_restore --list "$backup_path.custom" > /dev/null; then
        log "Backup completed successfully: $backup_name"
        
        # Upload to S3 if configured
        if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
            upload_to_s3 "$backup_path" "postgres/full-backups/"
            upload_to_s3 "$backup_path.custom" "postgres/full-backups/"
        fi
        
        # Create backup metadata
        create_backup_metadata "$backup_name" "full" "$backup_path"
        
        return 0
    else
        log "ERROR: Backup verification failed: $backup_name"
        return 1
    fi
}

# Function to perform incremental backup (WAL)
perform_wal_backup() {
    log "Starting WAL archive backup"
    
    # Find new WAL files
    local wal_files=$(find "$WAL_ARCHIVE_DIR" -name "*.gz" -newer "$BACKUP_DIR/.last_wal_backup" 2>/dev/null || find "$WAL_ARCHIVE_DIR" -name "*.gz")
    
    if [[ -n "$wal_files" ]]; then
        local wal_backup_dir="$BACKUP_DIR/wal_${DATE}"
        mkdir -p "$wal_backup_dir"
        
        # Copy WAL files
        echo "$wal_files" | xargs -I {} cp {} "$wal_backup_dir/"
        
        # Create archive
        tar -czf "$wal_backup_dir.tar.gz" -C "$BACKUP_DIR" "wal_${DATE}"
        rm -rf "$wal_backup_dir"
        
        # Upload to S3
        if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
            upload_to_s3 "$wal_backup_dir.tar.gz" "postgres/wal-backups/"
        fi
        
        # Update timestamp
        touch "$BACKUP_DIR/.last_wal_backup"
        
        log "WAL backup completed: wal_${DATE}.tar.gz"
    else
        log "No new WAL files to backup"
    fi
}

# Function to upload files to S3
upload_to_s3() {
    local file_path="$1"
    local s3_prefix="$2"
    local s3_key="${s3_prefix}$(basename "$file_path")"
    
    log "Uploading to S3: s3://${AWS_S3_BUCKET}/${s3_key}"
    
    if aws s3 cp "$file_path" "s3://${AWS_S3_BUCKET}/${s3_key}" \
        --storage-class STANDARD_IA \
        --metadata "backup-date=${DATE},hostname=${HOSTNAME}"; then
        log "S3 upload successful: $s3_key"
        
        # Upload to cross-region bucket if configured
        if [[ "${CROSS_REGION_BACKUP:-}" == "true" && -n "${CROSS_REGION_BUCKET:-}" ]]; then
            aws s3 cp "$file_path" "s3://${CROSS_REGION_BUCKET}/${s3_key}" \
                --region "${CROSS_REGION}" \
                --storage-class STANDARD_IA \
                --metadata "backup-date=${DATE},hostname=${HOSTNAME},source-region=${AWS_REGION}"
            log "Cross-region backup uploaded: ${CROSS_REGION_BUCKET}/${s3_key}"
        fi
    else
        log "ERROR: S3 upload failed: $s3_key"
        return 1
    fi
}

# Function to create backup metadata
create_backup_metadata() {
    local backup_name="$1"
    local backup_type="$2"
    local backup_path="$3"
    
    local metadata_file="$BACKUP_DIR/${backup_name}.metadata.json"
    
    cat > "$metadata_file" << EOF
{
    "backup_name": "$backup_name",
    "backup_type": "$backup_type",
    "backup_date": "$DATE",
    "backup_path": "$backup_path",
    "hostname": "$HOSTNAME",
    "database": "$POSTGRES_DB",
    "size_bytes": $(stat -c%s "$backup_path"),
    "md5_checksum": "$(md5sum "$backup_path" | cut -d' ' -f1)",
    "postgres_version": "$(psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c 'SELECT version();' | xargs)",
    "pitr_enabled": "${PITR_ENABLED:-false}"
}
EOF
    
    # Upload metadata to S3
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        upload_to_s3 "$metadata_file" "postgres/metadata/"
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    local retention_days="${BACKUP_RETENTION_DAYS:-30}"
    
    log "Cleaning up backups older than $retention_days days"
    
    # Local cleanup
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime "+$retention_days" -delete
    find "$BACKUP_DIR" -name "*.custom" -mtime "+$retention_days" -delete
    find "$BACKUP_DIR" -name "wal_*.tar.gz" -mtime "+$retention_days" -delete
    find "$BACKUP_DIR" -name "*.metadata.json" -mtime "+$retention_days" -delete
    
    # S3 cleanup (using lifecycle policies is recommended for production)
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        local cutoff_date=$(date -d "$retention_days days ago" +%Y-%m-%d)
        aws s3api list-objects-v2 \
            --bucket "$AWS_S3_BUCKET" \
            --prefix "postgres/" \
            --query "Contents[?LastModified<='$cutoff_date'].Key" \
            --output text | \
        xargs -I {} aws s3 rm "s3://${AWS_S3_BUCKET}/{}"
    fi
    
    log "Backup cleanup completed"
}

# Function to send backup notifications
send_notification() {
    local status="$1"
    local message="$2"
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🔄 Supabase Backup $status: $message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    # Email notification (requires configured mail system)
    if [[ -n "${EMAIL_ALERTS:-}" && -x "$(command -v mail)" ]]; then
        echo "$message" | mail -s "Supabase Backup $status" "$EMAIL_ALERTS" || true
    fi
}

# Function to setup WAL archiving
setup_wal_archiving() {
    if [[ "${PITR_ENABLED:-}" == "true" ]]; then
        log "Setting up WAL archiving for PITR"
        
        # Configure PostgreSQL for WAL archiving
        psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
            ALTER SYSTEM SET wal_level = 'replica';
            ALTER SYSTEM SET archive_mode = 'on';
            ALTER SYSTEM SET archive_command = 'gzip < %p > ${WAL_ARCHIVE_DIR}/%f.gz';
            ALTER SYSTEM SET max_wal_senders = 3;
            ALTER SYSTEM SET wal_keep_size = '1GB';
            SELECT pg_reload_conf();
        "
        
        log "WAL archiving configured successfully"
    fi
}

# Main backup process
main() {
    log "=== Backup Manager Started ==="
    
    # Setup WAL archiving if enabled
    setup_wal_archiving
    
    # Check if it's time for a full backup (daily by default)
    local current_hour=$(date +%H)
    local backup_hour=$(echo "${BACKUP_SCHEDULE:-0 2 * * *}" | cut -d' ' -f2)
    
    if [[ "$current_hour" == "$backup_hour" ]] || [[ "${1:-}" == "full" ]]; then
        if perform_full_backup; then
            send_notification "SUCCESS" "Full backup completed successfully"
        else
            send_notification "FAILED" "Full backup failed - check logs"
            exit 1
        fi
    fi
    
    # Always perform WAL backup
    perform_wal_backup
    
    # Cleanup old backups
    cleanup_old_backups
    
    log "=== Backup Manager Completed ==="
}

# Signal handlers
trap 'log "Backup interrupted"; exit 1' INT TERM

# Run main function or start as daemon
if [[ "${1:-}" == "daemon" ]]; then
    # Run as daemon with cron-like scheduling
    while true; do
        main
        sleep 3600  # Check every hour
    done
else
    main "$@"
fi
