#!/bin/bash
# cloud_backup.sh - Cloud backup utility for Supabase backups
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
    CLOUD_BACKUP_ENABLED=false
fi

# Logging setup
LOG_FILE="${LOG_DIR}/cloud_backup.log"
mkdir -p "$LOG_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "❌ CLOUD BACKUP FAILED: $1"
    "${SCRIPT_DIR}/notify.sh" "Cloud Backup Failed" "Cloud backup failed: $1" "ERROR" 2>/dev/null || true
    exit 1
}

# Success notification
backup_success() {
    log "✅ CLOUD BACKUP COMPLETED: $1"
    "${SCRIPT_DIR}/notify.sh" "Cloud Backup Success" "Cloud backup completed: $1" "SUCCESS" 2>/dev/null || true
}

# Check if cloud backup is enabled
check_enabled() {
    if [[ "${CLOUD_BACKUP_ENABLED:-false}" != "true" ]]; then
        log "ℹ️  Cloud backup is disabled"
        exit 0
    fi
}

# Install rclone if needed
install_rclone() {
    if ! command -v rclone >/dev/null 2>&1; then
        log "📦 Installing rclone..."
        
        if command -v curl >/dev/null 2>&1; then
            curl https://rclone.org/install.sh | sudo bash
        elif command -v wget >/dev/null 2>&1; then
            wget -qO- https://rclone.org/install.sh | sudo bash
        else
            error_exit "Neither curl nor wget available for rclone installation"
        fi
        
        if command -v rclone >/dev/null 2>&1; then
            log "✅ rclone installed successfully"
        else
            error_exit "Failed to install rclone"
        fi
    fi
}

# Install AWS CLI if needed
install_aws_cli() {
    if ! command -v aws >/dev/null 2>&1; then
        log "📦 Installing AWS CLI..."
        
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install --user awscli
        elif command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y awscli
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y awscli
        else
            # Install using bundled installer
            local temp_dir
            temp_dir=$(mktemp -d)
            cd "$temp_dir"
            
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            
            cd - >/dev/null
            rm -rf "$temp_dir"
        fi
        
        if command -v aws >/dev/null 2>&1; then
            log "✅ AWS CLI installed successfully"
        else
            error_exit "Failed to install AWS CLI"
        fi
    fi
}

# Backup using rclone
backup_with_rclone() {
    local backup_file="$1"
    
    log "☁️  Uploading backup with rclone..."
    
    install_rclone
    
    # Check if remote is configured
    if ! rclone listremotes | grep -q "^${RCLONE_REMOTE_NAME}:$"; then
        error_exit "rclone remote '${RCLONE_REMOTE_NAME}' not configured. Run: rclone config"
    fi
    
    local remote_path="${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}/$(basename "$backup_file")"
    
    # Upload with progress and verification
    if rclone copy "$backup_file" "${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}" \
        --progress \
        --checksum \
        --log-level INFO \
        --log-file "$LOG_FILE"; then
        
        # Verify upload
        local local_size remote_size
        local_size=$(stat -c%s "$backup_file")
        remote_size=$(rclone size "${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}/$(basename "$backup_file")" --json | jq -r '.bytes')
        
        if [[ "$local_size" == "$remote_size" ]]; then
            log "✅ Upload verified: $(basename "$backup_file") (${local_size} bytes)"
            echo "$remote_path"
        else
            error_exit "Upload verification failed: size mismatch"
        fi
    else
        error_exit "rclone upload failed"
    fi
}

# Backup using AWS CLI
backup_with_aws() {
    local backup_file="$1"
    
    log "☁️  Uploading backup to AWS S3..."
    
    install_aws_cli
    
    # Check AWS configuration
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS CLI not configured. Run: aws configure"
    fi
    
    if [[ -z "${AWS_S3_BUCKET:-}" ]]; then
        error_exit "AWS_S3_BUCKET not configured"
    fi
    
    local s3_path="s3://${AWS_S3_BUCKET}/supabase-backups/$(basename "$backup_file")"
    
    # Upload with server-side encryption
    if aws s3 cp "$backup_file" "$s3_path" \
        --region "${AWS_REGION:-us-east-1}" \
        --server-side-encryption AES256 \
        --storage-class STANDARD_IA; then
        
        # Verify upload
        local local_size s3_size
        local_size=$(stat -c%s "$backup_file")
        s3_size=$(aws s3api head-object --bucket "$AWS_S3_BUCKET" --key "supabase-backups/$(basename "$backup_file")" --query 'ContentLength' --output text)
        
        if [[ "$local_size" == "$s3_size" ]]; then
            log "✅ Upload verified: $(basename "$backup_file") (${local_size} bytes)"
            echo "$s3_path"
        else
            error_exit "Upload verification failed: size mismatch"
        fi
    else
        error_exit "AWS S3 upload failed"
    fi
}

# Backup using Google Cloud Storage
backup_with_gcp() {
    local backup_file="$1"
    
    log "☁️  Uploading backup to Google Cloud Storage..."
    
    # Check if gsutil is available
    if ! command -v gsutil >/dev/null 2>&1; then
        error_exit "gsutil not found. Install Google Cloud SDK first."
    fi
    
    if [[ -z "${GCP_BUCKET:-}" ]]; then
        error_exit "GCP_BUCKET not configured"
    fi
    
    local gcs_path="gs://${GCP_BUCKET}/supabase-backups/$(basename "$backup_file")"
    
    # Upload with verification
    if gsutil -m cp "$backup_file" "$gcs_path"; then
        # Verify upload
        local local_hash gcs_hash
        local_hash=$(md5sum "$backup_file" | cut -d' ' -f1)
        gcs_hash=$(gsutil hash -m "$gcs_path" | grep "Hash (md5)" | cut -d: -f2 | tr -d ' ')
        
        if [[ "$local_hash" == "$gcs_hash" ]]; then
            log "✅ Upload verified: $(basename "$backup_file")"
            echo "$gcs_path"
        else
            error_exit "Upload verification failed: hash mismatch"
        fi
    else
        error_exit "Google Cloud Storage upload failed"
    fi
}

# Backup using Hetzner Object Storage (S3-compatible)
backup_with_hetzner_s3() {
    local backup_file="$1"
    
    log "☁️  Uploading backup to Hetzner Object Storage..."
    
    install_aws_cli
    
    if [[ -z "${HETZNER_S3_BUCKET:-}" ]]; then
        error_exit "HETZNER_S3_BUCKET not configured"
    fi
    
    if [[ -z "${HETZNER_S3_ENDPOINT:-}" ]]; then
        error_exit "HETZNER_S3_ENDPOINT not configured"
    fi
    
    local s3_path="s3://${HETZNER_S3_BUCKET}/supabase-backups/$(basename "$backup_file")"
    
    # Set Hetzner credentials for this session
    export AWS_ACCESS_KEY_ID="${HETZNER_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${HETZNER_SECRET_KEY}"
    
    # Upload with custom endpoint
    if aws s3 cp "$backup_file" "$s3_path" \
        --endpoint-url "$HETZNER_S3_ENDPOINT" \
        --region "${HETZNER_S3_REGION:-fsn1}" \
        --server-side-encryption AES256; then
        
        # Verify upload
        local local_size s3_size
        local_size=$(stat -c%s "$backup_file")
        s3_size=$(aws s3api head-object \
            --endpoint-url "$HETZNER_S3_ENDPOINT" \
            --bucket "$HETZNER_S3_BUCKET" \
            --key "supabase-backups/$(basename "$backup_file")" \
            --query 'ContentLength' --output text)
        
        # Reset AWS credentials
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        
        if [[ "$local_size" == "$s3_size" ]]; then
            log "✅ Upload verified: $(basename "$backup_file") (${local_size} bytes)"
            echo "$s3_path"
        else
            error_exit "Upload verification failed: size mismatch"
        fi
    else
        # Reset AWS credentials on failure
        unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
        error_exit "Hetzner Object Storage upload failed"
    fi
}

# Backup using Hetzner Storage Box (SFTP)
backup_with_hetzner_sftp() {
    local backup_file="$1"
    
    log "☁️  Uploading backup to Hetzner Storage Box (SFTP)..."
    
    install_rclone
    
    if [[ -z "${HETZNER_STORAGEBOX_HOST:-}" ]]; then
        error_exit "HETZNER_STORAGEBOX_HOST not configured"
    fi
    
    # Create temporary rclone config for Hetzner Storage Box
    local temp_config="/tmp/rclone_hetzner_$(date +%s).conf"
    cat > "$temp_config" << EOF
[hetzner_sftp]
type = sftp
host = ${HETZNER_STORAGEBOX_HOST}
user = ${HETZNER_STORAGEBOX_USER}
pass = $(echo -n "${HETZNER_STORAGEBOX_PASS}" | rclone obscure)
EOF
    
    local remote_path="hetzner_sftp:${HETZNER_STORAGEBOX_PATH}/$(basename "$backup_file")"
    
    # Upload with temporary config
    if rclone copy "$backup_file" "hetzner_sftp:${HETZNER_STORAGEBOX_PATH}" \
        --config "$temp_config" \
        --progress \
        --log-level INFO \
        --log-file "$LOG_FILE"; then
        
        # Verify upload
        local local_size remote_size
        local_size=$(stat -c%s "$backup_file")
        remote_size=$(rclone size "hetzner_sftp:${HETZNER_STORAGEBOX_PATH}/$(basename "$backup_file")" \
            --config "$temp_config" --json | jq -r '.bytes')
        
        # Cleanup temp config
        rm -f "$temp_config"
        
        if [[ "$local_size" == "$remote_size" ]]; then
            log "✅ Upload verified: $(basename "$backup_file") (${local_size} bytes)"
            echo "$remote_path"
        else
            error_exit "Upload verification failed: size mismatch"
        fi
    else
        # Cleanup temp config on failure
        rm -f "$temp_config"
        error_exit "Hetzner Storage Box SFTP upload failed"
    fi
}

# Multi-cloud backup function
backup_with_multi_cloud() {
    local backup_file="$1"
    local providers="${MULTI_CLOUD_PROVIDERS}"
    local success_count=0
    local total_count=0
    local failed_providers=""
    
    log "☁️  Starting multi-cloud backup to providers: $providers"
    
    # Split providers by comma
    IFS=',' read -ra PROVIDER_ARRAY <<< "$providers"
    
    for provider in "${PROVIDER_ARRAY[@]}"; do
        provider=$(echo "$provider" | xargs)  # Trim whitespace
        ((total_count++))
        
        log "📤 Uploading to $provider..."
        
        case "$provider" in
            "aws")
                if backup_with_aws "$backup_file" >/dev/null 2>&1; then
                    ((success_count++))
                    log "✅ AWS upload successful"
                else
                    failed_providers="$failed_providers $provider"
                    log "❌ AWS upload failed"
                fi
                ;;
            "hetzner")
                if backup_with_hetzner_s3 "$backup_file" >/dev/null 2>&1; then
                    ((success_count++))
                    log "✅ Hetzner Object Storage upload successful"
                else
                    failed_providers="$failed_providers $provider"
                    log "❌ Hetzner Object Storage upload failed"
                fi
                ;;
            "hetzner-sftp")
                if backup_with_hetzner_sftp "$backup_file" >/dev/null 2>&1; then
                    ((success_count++))
                    log "✅ Hetzner Storage Box upload successful"
                else
                    failed_providers="$failed_providers $provider"
                    log "❌ Hetzner Storage Box upload failed"
                fi
                ;;
            "onedrive"|"dropbox"|"googledrive")
                # These should be configured as rclone remotes
                local remote_name="$provider"
                if rclone copy "$backup_file" "${remote_name}:supabase-backups/" --progress >/dev/null 2>&1; then
                    ((success_count++))
                    log "✅ $provider upload successful"
                else
                    failed_providers="$failed_providers $provider"
                    log "❌ $provider upload failed"
                fi
                ;;
            *)
                log "⚠️  Unknown provider: $provider"
                failed_providers="$failed_providers $provider"
                ;;
        esac
    done
    
    log "📊 Multi-cloud backup summary: $success_count/$total_count successful"
    
    if [[ $success_count -eq 0 ]]; then
        error_exit "All cloud providers failed: $failed_providers"
    elif [[ $success_count -lt $total_count ]]; then
        log "⚠️  Some providers failed: $failed_providers"
        return 1
    else
        log "✅ All cloud providers successful"
        return 0
    fi
}

# Backup using Azure Blob Storage
backup_with_azure() {
    local backup_file="$1"
    
    log "☁️  Uploading backup to Azure Blob Storage..."
    
    # Check if az CLI is available
    if ! command -v az >/dev/null 2>&1; then
        error_exit "Azure CLI not found. Install Azure CLI first."
    fi
    
    if [[ -z "${AZURE_CONTAINER:-}" ]]; then
        error_exit "AZURE_CONTAINER not configured"
    fi
    
    local blob_name="supabase-backups/$(basename "$backup_file")"
    
    # Upload with verification
    if az storage blob upload \
        --file "$backup_file" \
        --container-name "$AZURE_CONTAINER" \
        --name "$blob_name" \
        --overwrite; then
        
        log "✅ Upload completed: $(basename "$backup_file")"
        echo "https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_CONTAINER}/${blob_name}"
    else
        error_exit "Azure Blob Storage upload failed"
    fi
}

# Clean up old cloud backups
cleanup_cloud_backups() {
    local retention_days="${BACKUP_RETENTION_DAYS:-30}"
    
    log "🧹 Cleaning up old cloud backups (older than $retention_days days)..."
    
    case "${CLOUD_PROVIDER:-rclone}" in
        "rclone")
            if command -v rclone >/dev/null 2>&1; then
                # List and delete old files
                rclone delete "${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}" \
                    --min-age "${retention_days}d" \
                    --include "supabase_backup_*.sql*" \
                    --dry-run=false
            fi
            ;;
        "aws")
            if command -v aws >/dev/null 2>&1; then
                # Delete old S3 objects
                local cutoff_date
                cutoff_date=$(date -d "$retention_days days ago" +%Y-%m-%d)
                
                aws s3api list-objects-v2 \
                    --bucket "$AWS_S3_BUCKET" \
                    --prefix "supabase-backups/" \
                    --query "Contents[?LastModified<='$cutoff_date'].Key" \
                    --output text | \
                while read -r key; do
                    if [[ -n "$key" && "$key" != "None" ]]; then
                        aws s3 rm "s3://${AWS_S3_BUCKET}/${key}"
                        log "🗑️  Deleted old backup: $key"
                    fi
                done
            fi
            ;;
        "gcp")
            if command -v gsutil >/dev/null 2>&1; then
                # Delete old GCS objects
                gsutil -m rm "gs://${GCP_BUCKET}/supabase-backups/supabase_backup_$(date -d "$retention_days days ago" +%Y-%m-%d)*" 2>/dev/null || true
            fi
            ;;
    esac
    
    log "✅ Cloud cleanup completed"
}

# Get backup file size and info
get_backup_info() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        error_exit "Backup file not found: $backup_file"
    fi
    
    local size_bytes size_human
    size_bytes=$(stat -c%s "$backup_file")
    size_human=$(du -h "$backup_file" | cut -f1)
    
    log "📊 Backup file info:"
    log "   - File: $(basename "$backup_file")"
    log "   - Size: $size_human ($size_bytes bytes)"
    log "   - Created: $(stat -c%y "$backup_file")"
}

# Main cloud backup function
upload_to_cloud() {
    local backup_file="$1"
    local start_time
    start_time=$(date +%s)
    
    log "🚀 Starting cloud backup upload..."
    
    get_backup_info "$backup_file"
    
    local cloud_path=""
    
    # Check for multi-cloud setup
    if [[ "${MULTI_CLOUD_ENABLED:-false}" == "true" && -n "${MULTI_CLOUD_PROVIDERS:-}" ]]; then
        cloud_path=$(backup_with_multi_cloud "$backup_file")
    else
        case "${CLOUD_PROVIDER:-rclone}" in
            "rclone")
                cloud_path=$(backup_with_rclone "$backup_file")
                ;;
            "aws")
                cloud_path=$(backup_with_aws "$backup_file")
                ;;
            "gcp")
                cloud_path=$(backup_with_gcp "$backup_file")
                ;;
            "azure")
                cloud_path=$(backup_with_azure "$backup_file")
                ;;
            "hetzner")
                cloud_path=$(backup_with_hetzner_s3 "$backup_file")
                ;;
            "hetzner-sftp")
                cloud_path=$(backup_with_hetzner_sftp "$backup_file")
                ;;
            *)
                error_exit "Unknown cloud provider: ${CLOUD_PROVIDER}"
                ;;
        esac
    fi
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log "🎉 Cloud backup completed successfully!"
    log "   - Provider: ${CLOUD_PROVIDER}"
    log "   - Location: $cloud_path"
    log "   - Duration: ${duration} seconds"
    
    # Cleanup old backups
    cleanup_cloud_backups
    
    backup_success "Provider: ${CLOUD_PROVIDER}, Duration: ${duration}s"
}

# Find latest backup file
find_latest_backup() {
    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "supabase_backup_*.sql*" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -z "$latest_backup" ]]; then
        error_exit "No backup files found in $BACKUP_DIR"
    fi
    
    echo "$latest_backup"
}

# Show usage
show_usage() {
    echo "Usage: $0 [backup_file]"
    echo ""
    echo "Upload Supabase backup to cloud storage"
    echo ""
    echo "Arguments:"
    echo "  backup_file  - Path to backup file (optional, will use latest if not specified)"
    echo ""
    echo "Options:"
    echo "  --test       - Test cloud connectivity"
    echo "  --cleanup    - Clean up old cloud backups only"
    echo "  --help       - Show this help message"
    echo ""
    echo "Environment variables required (set in config.env):"
    echo "  CLOUD_BACKUP_ENABLED=true"
    echo "  CLOUD_PROVIDER=[rclone|aws|gcp|azure]"
    echo ""
    echo "Provider-specific configuration:"
    echo "  rclone: RCLONE_REMOTE_NAME, RCLONE_REMOTE_PATH"
    echo "  aws: AWS_S3_BUCKET, AWS_REGION"
    echo "  gcp: GCP_BUCKET"
    echo "  azure: AZURE_CONTAINER"
}

# Test cloud connectivity
test_connectivity() {
    log "🧪 Testing cloud connectivity..."
    
    case "${CLOUD_PROVIDER:-rclone}" in
        "rclone")
            install_rclone
            if rclone listremotes | grep -q "^${RCLONE_REMOTE_NAME}:$"; then
                if rclone lsd "${RCLONE_REMOTE_NAME}:" >/dev/null 2>&1; then
                    log "✅ rclone connectivity test passed"
                else
                    error_exit "rclone connectivity test failed"
                fi
            else
                error_exit "rclone remote '${RCLONE_REMOTE_NAME}' not configured"
            fi
            ;;
        "aws")
            install_aws_cli
            if aws sts get-caller-identity >/dev/null 2>&1; then
                if aws s3 ls "s3://${AWS_S3_BUCKET}" >/dev/null 2>&1; then
                    log "✅ AWS S3 connectivity test passed"
                else
                    error_exit "AWS S3 connectivity test failed"
                fi
            else
                error_exit "AWS CLI not configured"
            fi
            ;;
        *)
            log "⚠️  Connectivity test not implemented for ${CLOUD_PROVIDER}"
            ;;
    esac
}

# Main execution
main() {
    check_enabled
    
    case "${1:-}" in
        "--help"|"-h")
            show_usage
            exit 0
            ;;
        "--test")
            test_connectivity
            exit 0
            ;;
        "--cleanup")
            cleanup_cloud_backups
            exit 0
            ;;
        "")
            # Use latest backup
            local backup_file
            backup_file=$(find_latest_backup)
            upload_to_cloud "$backup_file"
            ;;
        *)
            # Use specified backup file
            if [[ -f "$1" ]]; then
                upload_to_cloud "$1"
            else
                error_exit "Backup file not found: $1"
            fi
            ;;
    esac
}

# Run main function
main "$@"
