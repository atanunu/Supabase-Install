#!/bin/bash
# Cross-Region Backup Synchronization
# Syncs backups between primary and secondary regions for disaster recovery

set -euo pipefail

LOG_FILE="/var/log/cross_region_sync.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log "Starting cross-region sync..."

# Function to sync PostgreSQL backups
sync_postgres_backups() {
    log "Syncing PostgreSQL backups to cross-region"
    
    # Sync full backups
    aws s3 sync "s3://${PRIMARY_BUCKET}/postgres/full-backups/" \
        "s3://${CROSS_REGION_BUCKET}/postgres/full-backups/" \
        --region "${CROSS_REGION}" \
        --storage-class STANDARD_IA \
        --delete
    
    # Sync WAL backups
    aws s3 sync "s3://${PRIMARY_BUCKET}/postgres/wal-backups/" \
        "s3://${CROSS_REGION_BUCKET}/postgres/wal-backups/" \
        --region "${CROSS_REGION}" \
        --storage-class STANDARD_IA \
        --delete
    
    # Sync metadata
    aws s3 sync "s3://${PRIMARY_BUCKET}/postgres/metadata/" \
        "s3://${CROSS_REGION_BUCKET}/postgres/metadata/" \
        --region "${CROSS_REGION}" \
        --delete
    
    log "PostgreSQL backup sync completed"
}

# Function to sync storage backups
sync_storage_backups() {
    log "Syncing storage backups to cross-region"
    
    # Sync storage backups
    aws s3 sync "s3://${PRIMARY_BUCKET}/storage/backups/" \
        "s3://${CROSS_REGION_BUCKET}/storage/backups/" \
        --region "${CROSS_REGION}" \
        --storage-class STANDARD_IA \
        --delete
    
    # Sync storage metadata
    aws s3 sync "s3://${PRIMARY_BUCKET}/storage/metadata/" \
        "s3://${CROSS_REGION_BUCKET}/storage/metadata/" \
        --region "${CROSS_REGION}" \
        --delete
    
    log "Storage backup sync completed"
}

# Function to sync validation reports
sync_validation_reports() {
    log "Syncing validation reports to cross-region"
    
    aws s3 sync "s3://${PRIMARY_BUCKET}/validation/" \
        "s3://${CROSS_REGION_BUCKET}/validation/" \
        --region "${CROSS_REGION}" \
        --delete
    
    log "Validation report sync completed"
}

# Function to verify cross-region sync
verify_cross_region_sync() {
    log "Verifying cross-region sync integrity"
    
    local errors=0
    
    # Check PostgreSQL backups
    local primary_postgres_count=$(aws s3 ls "s3://${PRIMARY_BUCKET}/postgres/" --recursive | wc -l)
    local cross_postgres_count=$(aws s3 ls "s3://${CROSS_REGION_BUCKET}/postgres/" --recursive --region "${CROSS_REGION}" | wc -l)
    
    if [[ $primary_postgres_count -eq $cross_postgres_count ]]; then
        log "✅ PostgreSQL backup sync verified ($primary_postgres_count files)"
    else
        log "❌ PostgreSQL backup sync mismatch (Primary: $primary_postgres_count, Cross-region: $cross_postgres_count)"
        ((errors++))
    fi
    
    # Check storage backups
    local primary_storage_count=$(aws s3 ls "s3://${PRIMARY_BUCKET}/storage/" --recursive | wc -l)
    local cross_storage_count=$(aws s3 ls "s3://${CROSS_REGION_BUCKET}/storage/" --recursive --region "${CROSS_REGION}" | wc -l)
    
    if [[ $primary_storage_count -eq $cross_storage_count ]]; then
        log "✅ Storage backup sync verified ($primary_storage_count files)"
    else
        log "❌ Storage backup sync mismatch (Primary: $primary_storage_count, Cross-region: $cross_storage_count)"
        ((errors++))
    fi
    
    return $errors
}

# Function to create sync report
create_sync_report() {
    local sync_status="$1"
    local report_file="/tmp/cross_region_sync_report_${DATE}.json"
    
    # Collect sync statistics
    local primary_total=$(aws s3 ls "s3://${PRIMARY_BUCKET}/" --recursive | wc -l)
    local cross_total=$(aws s3 ls "s3://${CROSS_REGION_BUCKET}/" --recursive --region "${CROSS_REGION}" | wc -l)
    
    local primary_size=$(aws s3 ls "s3://${PRIMARY_BUCKET}/" --recursive --summarize | grep "Total Size" | awk '{print $3}')
    local cross_size=$(aws s3 ls "s3://${CROSS_REGION_BUCKET}/" --recursive --region "${CROSS_REGION}" --summarize | grep "Total Size" | awk '{print $3}')
    
    cat > "$report_file" << EOF
{
    "sync_date": "$DATE",
    "sync_status": "$sync_status",
    "primary_region": "${PRIMARY_REGION}",
    "cross_region": "${CROSS_REGION}",
    "primary_bucket": "${PRIMARY_BUCKET}",
    "cross_region_bucket": "${CROSS_REGION_BUCKET}",
    "statistics": {
        "primary_files": $primary_total,
        "cross_region_files": $cross_total,
        "primary_size_bytes": "${primary_size:-0}",
        "cross_region_size_bytes": "${cross_size:-0}",
        "sync_percentage": $(( cross_total * 100 / primary_total ))
    },
    "sync_details": {
        "postgres_backups": "synced",
        "storage_backups": "synced",
        "validation_reports": "synced",
        "metadata": "synced"
    }
}
EOF
    
    log "Sync report created: $report_file"
    
    # Upload report to both buckets
    aws s3 cp "$report_file" "s3://${PRIMARY_BUCKET}/sync/reports/"
    aws s3 cp "$report_file" "s3://${CROSS_REGION_BUCKET}/sync/reports/" --region "${CROSS_REGION}"
}

# Function to send sync notifications
send_sync_notification() {
    local status="$1"
    local message="$2"
    
    local emoji="✅"
    if [[ "$status" != "SUCCESS" ]]; then
        emoji="❌"
    fi
    
    local notification="$emoji Cross-Region Backup Sync $status
    
    Primary Region: ${PRIMARY_REGION}
    Cross Region: ${CROSS_REGION}
    Primary Bucket: ${PRIMARY_BUCKET}
    Cross Bucket: ${CROSS_REGION_BUCKET}
    
    $message
    
    Date: $DATE"
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$notification\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    log "Sync notification sent: $status"
}

# Function to handle sync failure recovery
handle_sync_failure() {
    local failed_component="$1"
    
    log "Attempting recovery for failed sync: $failed_component"
    
    # Retry the failed component
    case "$failed_component" in
        "postgres")
            sync_postgres_backups
            ;;
        "storage")
            sync_storage_backups
            ;;
        "validation")
            sync_validation_reports
            ;;
        *)
            log "Unknown failed component: $failed_component"
            return 1
            ;;
    esac
    
    log "Recovery attempt completed for: $failed_component"
}

# Function to setup cross-region replication policies
setup_cross_region_policies() {
    log "Setting up cross-region replication policies"
    
    # Create bucket policy for cross-region access
    cat > /tmp/cross_region_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CrossRegionReplication",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):root"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${CROSS_REGION_BUCKET}",
                "arn:aws:s3:::${CROSS_REGION_BUCKET}/*"
            ]
        }
    ]
}
EOF
    
    # Apply policy to cross-region bucket
    aws s3api put-bucket-policy \
        --bucket "${CROSS_REGION_BUCKET}" \
        --policy file:///tmp/cross_region_policy.json \
        --region "${CROSS_REGION}"
    
    log "Cross-region policies configured"
}

# Main sync function
main() {
    local action="${1:-sync}"
    
    case "$action" in
        "sync")
            log "=== Starting Cross-Region Backup Sync ==="
            
            local sync_errors=0
            
            # Sync PostgreSQL backups
            if ! sync_postgres_backups; then
                ((sync_errors++))
                handle_sync_failure "postgres"
            fi
            
            # Sync storage backups
            if ! sync_storage_backups; then
                ((sync_errors++))
                handle_sync_failure "storage"
            fi
            
            # Sync validation reports
            if ! sync_validation_reports; then
                ((sync_errors++))
                handle_sync_failure "validation"
            fi
            
            # Verify sync
            if verify_cross_region_sync; then
                log "Cross-region sync verification successful"
            else
                ((sync_errors++))
                log "Cross-region sync verification failed"
            fi
            
            # Create report and send notifications
            if [[ $sync_errors -eq 0 ]]; then
                create_sync_report "SUCCESS"
                send_sync_notification "SUCCESS" "All backup synchronization completed successfully"
            else
                create_sync_report "FAILED"
                send_sync_notification "FAILED" "$sync_errors components failed synchronization"
            fi
            
            log "=== Cross-Region Sync Completed ==="
            exit $sync_errors
            ;;
        "verify")
            verify_cross_region_sync
            ;;
        "setup")
            setup_cross_region_policies
            ;;
        "daemon")
            # Run sync daemon
            while true; do
                # Check schedule
                local current_hour=$(date +%H)
                local sync_hour=$(echo "${SYNC_SCHEDULE:-0 5 * * *}" | cut -d' ' -f2)
                
                if [[ "$current_hour" == "$sync_hour" ]]; then
                    main sync
                fi
                
                sleep 3600  # Check every hour
            done
            ;;
        *)
            log "Usage: $0 {sync|verify|setup|daemon}"
            exit 1
            ;;
    esac
}

# Validate required environment variables
if [[ -z "${PRIMARY_BUCKET:-}" || -z "${CROSS_REGION_BUCKET:-}" || -z "${CROSS_REGION:-}" ]]; then
    log "ERROR: Required environment variables not set"
    log "Required: PRIMARY_BUCKET, CROSS_REGION_BUCKET, CROSS_REGION"
    exit 1
fi

# Signal handlers
trap 'log "Cross-region sync interrupted"; exit 1' INT TERM

# Run main function
main "$@"
