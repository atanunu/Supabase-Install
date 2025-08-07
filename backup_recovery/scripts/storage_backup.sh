#!/bin/bash
# Storage Backup Manager for Supabase Storage
# Handles file uploads, avatars, and other stored content

set -euo pipefail

STORAGE_SOURCE="/storage_data"
BACKUP_DIR="/storage_backups"
LOG_FILE="/var/log/storage_backup.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log "Starting storage backup..."

# Function to perform incremental storage backup
perform_storage_backup() {
    local backup_name="storage_backup_${DATE}"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Starting storage backup: $backup_name"
    
    # Create backup directory
    mkdir -p "$backup_path"
    
    # Sync storage data with rsync for incremental backup
    if rsync -av --delete \
        --link-dest="$BACKUP_DIR/latest" \
        "$STORAGE_SOURCE/" \
        "$backup_path/"; then
        
        # Update latest symlink
        rm -f "$BACKUP_DIR/latest"
        ln -s "$backup_name" "$BACKUP_DIR/latest"
        
        # Create archive for cloud storage
        tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$backup_name"
        
        # Calculate backup size and file count
        local size=$(du -sh "$backup_path" | cut -f1)
        local file_count=$(find "$backup_path" -type f | wc -l)
        
        log "Storage backup completed: $backup_name (Size: $size, Files: $file_count)"
        
        # Upload to S3 if configured
        if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
            upload_storage_to_s3 "$backup_path.tar.gz" "storage/backups/"
        fi
        
        # Create metadata
        create_storage_metadata "$backup_name" "$backup_path" "$size" "$file_count"
        
        return 0
    else
        log "ERROR: Storage backup failed: $backup_name"
        return 1
    fi
}

# Function to upload storage backup to S3
upload_storage_to_s3() {
    local file_path="$1"
    local s3_prefix="$2"
    local s3_key="${s3_prefix}$(basename "$file_path")"
    
    log "Uploading storage backup to S3: s3://${AWS_S3_BUCKET}/${s3_key}"
    
    if aws s3 cp "$file_path" "s3://${AWS_S3_BUCKET}/${s3_key}" \
        --storage-class STANDARD_IA \
        --metadata "backup-date=${DATE},type=storage"; then
        log "S3 upload successful: $s3_key"
        return 0
    else
        log "ERROR: S3 upload failed: $s3_key"
        return 1
    fi
}

# Function to create storage metadata
create_storage_metadata() {
    local backup_name="$1"
    local backup_path="$2"
    local size="$3"
    local file_count="$4"
    
    local metadata_file="$BACKUP_DIR/${backup_name}.metadata.json"
    
    cat > "$metadata_file" << EOF
{
    "backup_name": "$backup_name",
    "backup_type": "storage_incremental",
    "backup_date": "$DATE",
    "backup_path": "$backup_path",
    "size_human": "$size",
    "file_count": $file_count,
    "size_bytes": $(du -sb "$backup_path" | cut -f1),
    "archive_path": "$backup_path.tar.gz",
    "archive_md5": "$(md5sum "$backup_path.tar.gz" | cut -d' ' -f1)"
}
EOF
    
    # Upload metadata to S3
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        aws s3 cp "$metadata_file" "s3://${AWS_S3_BUCKET}/storage/metadata/" || true
    fi
}

# Function to restore storage from backup
restore_storage_backup() {
    local backup_name="$1"
    local restore_path="${2:-/storage_data_restored}"
    
    log "Restoring storage backup: $backup_name to $restore_path"
    
    # Check if backup exists locally
    local backup_path="$BACKUP_DIR/$backup_name"
    if [[ ! -d "$backup_path" ]]; then
        # Try to download from S3
        if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
            local archive_name="${backup_name}.tar.gz"
            log "Downloading backup from S3: $archive_name"
            
            if aws s3 cp "s3://${AWS_S3_BUCKET}/storage/backups/$archive_name" "$BACKUP_DIR/"; then
                # Extract archive
                tar -xzf "$BACKUP_DIR/$archive_name" -C "$BACKUP_DIR/"
            else
                log "ERROR: Failed to download backup from S3"
                return 1
            fi
        else
            log "ERROR: Backup not found locally and no S3 configuration"
            return 1
        fi
    fi
    
    # Create restore directory
    mkdir -p "$restore_path"
    
    # Copy files
    if rsync -av "$backup_path/" "$restore_path/"; then
        log "Storage backup restored successfully to: $restore_path"
        return 0
    else
        log "ERROR: Storage restore failed"
        return 1
    fi
}

# Function to cleanup old storage backups
cleanup_old_storage_backups() {
    local retention_days="${STORAGE_RETENTION_DAYS:-90}"
    
    log "Cleaning up storage backups older than $retention_days days"
    
    # Find and remove old backup directories
    find "$BACKUP_DIR" -maxdepth 1 -name "storage_backup_*" -type d -mtime "+$retention_days" | while read -r old_backup; do
        log "Removing old backup: $(basename "$old_backup")"
        rm -rf "$old_backup"
        
        # Remove associated archive and metadata
        rm -f "${old_backup}.tar.gz"
        rm -f "${old_backup}.metadata.json"
    done
    
    # S3 cleanup
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        local cutoff_date=$(date -d "$retention_days days ago" +%Y-%m-%d)
        aws s3api list-objects-v2 \
            --bucket "$AWS_S3_BUCKET" \
            --prefix "storage/" \
            --query "Contents[?LastModified<='$cutoff_date'].Key" \
            --output text | \
        xargs -I {} aws s3 rm "s3://${AWS_S3_BUCKET}/{}" || true
    fi
    
    log "Storage backup cleanup completed"
}

# Function to verify storage backup integrity
verify_storage_backup() {
    local backup_name="$1"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Verifying storage backup: $backup_name"
    
    if [[ ! -d "$backup_path" ]]; then
        log "ERROR: Backup directory not found: $backup_path"
        return 1
    fi
    
    # Check if archive exists and is valid
    local archive_path="${backup_path}.tar.gz"
    if [[ -f "$archive_path" ]]; then
        if tar -tzf "$archive_path" > /dev/null; then
            log "Archive verification successful: $archive_path"
        else
            log "ERROR: Archive verification failed: $archive_path"
            return 1
        fi
    fi
    
    # Verify a sample of files
    local sample_files=$(find "$backup_path" -type f | head -10)
    local failed_files=0
    
    for file in $sample_files; do
        if [[ ! -r "$file" ]]; then
            log "WARNING: File not readable: $file"
            ((failed_files++))
        fi
    done
    
    if [[ $failed_files -eq 0 ]]; then
        log "Storage backup verification successful: $backup_name"
        return 0
    else
        log "WARNING: $failed_files files failed verification in backup: $backup_name"
        return 1
    fi
}

# Function to sync storage to cross-region
sync_cross_region() {
    if [[ "${CROSS_REGION_BACKUP:-}" == "true" && -n "${CROSS_REGION_BUCKET:-}" ]]; then
        log "Syncing storage to cross-region bucket"
        
        # Sync latest backup to cross-region
        local latest_backup=$(readlink "$BACKUP_DIR/latest" 2>/dev/null || echo "")
        if [[ -n "$latest_backup" && -f "$BACKUP_DIR/${latest_backup}.tar.gz" ]]; then
            aws s3 cp "$BACKUP_DIR/${latest_backup}.tar.gz" \
                "s3://${CROSS_REGION_BUCKET}/storage/backups/" \
                --region "${CROSS_REGION}" \
                --storage-class STANDARD_IA
            
            log "Cross-region sync completed for: $latest_backup"
        fi
    fi
}

# Main function
main() {
    local action="${1:-backup}"
    
    case "$action" in
        "backup")
            if perform_storage_backup; then
                sync_cross_region
                cleanup_old_storage_backups
                return 0
            else
                return 1
            fi
            ;;
        "restore")
            local backup_name="${2:-}"
            local restore_path="${3:-}"
            if [[ -n "$backup_name" ]]; then
                restore_storage_backup "$backup_name" "$restore_path"
            else
                log "ERROR: Backup name required for restore"
                exit 1
            fi
            ;;
        "verify")
            local backup_name="${2:-}"
            if [[ -n "$backup_name" ]]; then
                verify_storage_backup "$backup_name"
            else
                log "ERROR: Backup name required for verification"
                exit 1
            fi
            ;;
        "cleanup")
            cleanup_old_storage_backups
            ;;
        "daemon")
            # Run storage backup daemon
            while true; do
                # Check schedule
                local current_hour=$(date +%H)
                local backup_hour=$(echo "${STORAGE_BACKUP_SCHEDULE:-0 3 * * *}" | cut -d' ' -f2)
                
                if [[ "$current_hour" == "$backup_hour" ]]; then
                    main backup
                fi
                
                sleep 3600  # Check every hour
            done
            ;;
        *)
            log "Usage: $0 {backup|restore|verify|cleanup|daemon}"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "Storage backup interrupted"; exit 1' INT TERM

# Create required directories
mkdir -p "$BACKUP_DIR"

# Run main function
main "$@"
