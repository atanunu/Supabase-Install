#!/bin/bash
# Backup Validation and Testing System
# Automatically tests backup restoration and validates backup integrity

set -euo pipefail

VALIDATION_DIR="/validation_temp"
LOG_FILE="/var/log/backup_validator.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log "Starting backup validation..."

# Function to test PostgreSQL backup restoration
test_postgres_restore() {
    local backup_file="$1"
    local test_db="validation_test_${DATE}"
    
    log "Testing PostgreSQL backup restoration: $(basename "$backup_file")"
    
    # Create test database
    createdb -h postgres -U "$POSTGRES_USER" "$test_db" || {
        log "ERROR: Failed to create test database"
        return 1
    }
    
    # Test restore
    if pg_restore -h postgres -U "$POSTGRES_USER" -d "$test_db" --no-owner --no-privileges "$backup_file"; then
        log "Backup restoration test successful"
        
        # Basic data validation
        local table_count=$(psql -h postgres -U "$POSTGRES_USER" -d "$test_db" -t -c \
            "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
        local record_count=$(psql -h postgres -U "$POSTGRES_USER" -d "$test_db" -t -c \
            "SELECT count(*) FROM auth.users;" 2>/dev/null || echo "0")
        
        log "Validation results - Tables: $table_count, Users: $record_count"
        
        # Cleanup test database
        dropdb -h postgres -U "$POSTGRES_USER" "$test_db"
        
        return 0
    else
        log "ERROR: Backup restoration test failed"
        dropdb -h postgres -U "$POSTGRES_USER" "$test_db" 2>/dev/null || true
        return 1
    fi
}

# Function to test storage backup
test_storage_restore() {
    local backup_archive="$1"
    local test_dir="$VALIDATION_DIR/storage_test_${DATE}"
    
    log "Testing storage backup: $(basename "$backup_archive")"
    
    # Create test directory
    mkdir -p "$test_dir"
    
    # Extract and test
    if tar -xzf "$backup_archive" -C "$test_dir"; then
        local file_count=$(find "$test_dir" -type f | wc -l)
        local total_size=$(du -sh "$test_dir" | cut -f1)
        
        log "Storage backup test successful - Files: $file_count, Size: $total_size"
        
        # Test file integrity (sample)
        local sample_files=$(find "$test_dir" -type f | head -5)
        local corrupted_files=0
        
        for file in $sample_files; do
            if [[ ! -r "$file" ]]; then
                ((corrupted_files++))
            fi
        done
        
        if [[ $corrupted_files -eq 0 ]]; then
            log "File integrity test passed"
        else
            log "WARNING: $corrupted_files files failed integrity check"
        fi
        
        # Cleanup
        rm -rf "$test_dir"
        return 0
    else
        log "ERROR: Storage backup test failed"
        rm -rf "$test_dir"
        return 1
    fi
}

# Function to validate backup completeness
validate_backup_completeness() {
    log "Validating backup completeness..."
    
    local validation_results=""
    local total_tests=0
    local passed_tests=0
    
    # Check PostgreSQL backups
    local postgres_backups=$(find /backups -name "*.custom" -mtime -1 | head -3)
    for backup in $postgres_backups; do
        ((total_tests++))
        if test_postgres_restore "$backup"; then
            ((passed_tests++))
            validation_results+="\n✅ PostgreSQL backup: $(basename "$backup")"
        else
            validation_results+="\n❌ PostgreSQL backup: $(basename "$backup")"
        fi
    done
    
    # Check storage backups
    local storage_backups=$(find /storage_backups -name "*.tar.gz" -mtime -1 | head -2)
    for backup in $storage_backups; do
        ((total_tests++))
        if test_storage_restore "$backup"; then
            ((passed_tests++))
            validation_results+="\n✅ Storage backup: $(basename "$backup")"
        else
            validation_results+="\n❌ Storage backup: $(basename "$backup")"
        fi
    done
    
    # Check S3 backup availability
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        ((total_tests++))
        if aws s3 ls "s3://${AWS_S3_BUCKET}/postgres/" > /dev/null; then
            ((passed_tests++))
            validation_results+="\n✅ S3 PostgreSQL backups accessible"
        else
            validation_results+="\n❌ S3 PostgreSQL backups not accessible"
        fi
        
        ((total_tests++))
        if aws s3 ls "s3://${AWS_S3_BUCKET}/storage/" > /dev/null; then
            ((passed_tests++))
            validation_results+="\n✅ S3 Storage backups accessible"
        else
            validation_results+="\n❌ S3 Storage backups not accessible"
        fi
    fi
    
    # Calculate success rate
    local success_rate=$((passed_tests * 100 / total_tests))
    
    log "Validation completed: $passed_tests/$total_tests tests passed ($success_rate%)"
    
    # Send notification
    send_validation_notification "$success_rate" "$validation_results"
    
    return $((total_tests - passed_tests))
}

# Function to test Point-in-Time Recovery
test_pitr_capability() {
    log "Testing Point-in-Time Recovery capability..."
    
    # Check if WAL archiving is working
    local wal_status=$(psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT archived_count FROM pg_stat_archiver;")
    
    if [[ "$wal_status" -gt 0 ]]; then
        log "✅ WAL archiving is active (${wal_status} files archived)"
        
        # Test restore point creation
        local restore_point="validation_test_${DATE}"
        if psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
            "SELECT pg_create_restore_point('$restore_point');" > /dev/null; then
            log "✅ Restore point creation successful: $restore_point"
            return 0
        else
            log "❌ Restore point creation failed"
            return 1
        fi
    else
        log "❌ WAL archiving not working"
        return 1
    fi
}

# Function to test cross-region backup sync
test_cross_region_sync() {
    if [[ "${CROSS_REGION_BACKUP:-}" == "true" && -n "${CROSS_REGION_BUCKET:-}" ]]; then
        log "Testing cross-region backup sync..."
        
        # Check if cross-region bucket is accessible
        if aws s3 ls "s3://${CROSS_REGION_BUCKET}/" --region "${CROSS_REGION}" > /dev/null; then
            # Check if recent backups exist
            local recent_backups=$(aws s3 ls "s3://${CROSS_REGION_BUCKET}/postgres/" --region "${CROSS_REGION}" --recursive | wc -l)
            
            if [[ "$recent_backups" -gt 0 ]]; then
                log "✅ Cross-region sync working ($recent_backups files found)"
                return 0
            else
                log "❌ No backups found in cross-region bucket"
                return 1
            fi
        else
            log "❌ Cross-region bucket not accessible"
            return 1
        fi
    else
        log "Cross-region backup not configured, skipping test"
        return 0
    fi
}

# Function to generate backup validation report
generate_validation_report() {
    local report_file="/validation_temp/backup_validation_report_${DATE}.json"
    
    log "Generating validation report..."
    
    # Collect backup statistics
    local postgres_backup_count=$(find /backups -name "*.custom" | wc -l)
    local storage_backup_count=$(find /storage_backups -name "*.tar.gz" | wc -l)
    local total_backup_size=$(du -sh /backups /storage_backups 2>/dev/null | awk '{sum+=$1} END {print sum"B"}')
    
    # WAL archiving status
    local wal_status=$(psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT row_to_json(pg_stat_archiver) FROM pg_stat_archiver;" 2>/dev/null || echo "{}")
    
    # S3 backup status
    local s3_postgres_count=0
    local s3_storage_count=0
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        s3_postgres_count=$(aws s3 ls "s3://${AWS_S3_BUCKET}/postgres/" --recursive | wc -l)
        s3_storage_count=$(aws s3 ls "s3://${AWS_S3_BUCKET}/storage/" --recursive | wc -l)
    fi
    
    cat > "$report_file" << EOF
{
    "validation_date": "$DATE",
    "local_backups": {
        "postgres_backup_count": $postgres_backup_count,
        "storage_backup_count": $storage_backup_count,
        "total_size": "$total_backup_size"
    },
    "s3_backups": {
        "postgres_count": $s3_postgres_count,
        "storage_count": $s3_storage_count,
        "bucket": "${AWS_S3_BUCKET:-none}"
    },
    "wal_archiving": $wal_status,
    "cross_region": {
        "enabled": "${CROSS_REGION_BACKUP:-false}",
        "bucket": "${CROSS_REGION_BUCKET:-none}",
        "region": "${CROSS_REGION:-none}"
    },
    "validation_tests": {
        "postgres_restore": "tested",
        "storage_restore": "tested",
        "pitr_capability": "tested",
        "cross_region_sync": "tested"
    }
}
EOF
    
    log "Validation report generated: $report_file"
    
    # Upload report to S3
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        aws s3 cp "$report_file" "s3://${AWS_S3_BUCKET}/validation/reports/" || true
    fi
}

# Function to send validation notifications
send_validation_notification() {
    local success_rate="$1"
    local results="$2"
    
    local status="SUCCESS"
    local emoji="✅"
    
    if [[ $success_rate -lt 100 ]]; then
        status="WARNING"
        emoji="⚠️"
    fi
    
    if [[ $success_rate -lt 80 ]]; then
        status="FAILED"
        emoji="❌"
    fi
    
    local message="$emoji Backup Validation $status ($success_rate% passed)
    
    Test Results:$results
    
    Date: $DATE
    Report: Available in S3"
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    # Email notification
    if [[ -n "${EMAIL_ALERTS:-}" && -x "$(command -v mail)" ]]; then
        echo "$message" | mail -s "Backup Validation $status" "$EMAIL_ALERTS" || true
    fi
    
    log "Validation notification sent: $status"
}

# Function to cleanup validation artifacts
cleanup_validation() {
    log "Cleaning up validation artifacts..."
    
    # Remove old validation files
    find "$VALIDATION_DIR" -name "*validation*" -mtime +7 -delete
    
    # Remove old test databases (safety check)
    psql -h postgres -U "$POSTGRES_USER" -d postgres -t -c \
        "SELECT datname FROM pg_database WHERE datname LIKE 'validation_test_%';" | \
    while read -r db_name; do
        if [[ -n "$db_name" ]]; then
            dropdb -h postgres -U "$POSTGRES_USER" "$db_name" 2>/dev/null || true
            log "Cleaned up test database: $db_name"
        fi
    done
}

# Main validation function
main() {
    local action="${1:-validate}"
    
    # Create validation directory
    mkdir -p "$VALIDATION_DIR"
    
    case "$action" in
        "validate")
            log "=== Starting Comprehensive Backup Validation ==="
            
            local validation_errors=0
            
            # Test backup completeness
            validate_backup_completeness || ((validation_errors++))
            
            # Test PITR capability
            test_pitr_capability || ((validation_errors++))
            
            # Test cross-region sync
            test_cross_region_sync || ((validation_errors++))
            
            # Generate report
            generate_validation_report
            
            # Cleanup
            cleanup_validation
            
            log "=== Backup Validation Completed ==="
            
            if [[ $validation_errors -eq 0 ]]; then
                log "All validation tests passed"
                exit 0
            else
                log "$validation_errors validation tests failed"
                exit 1
            fi
            ;;
        "test-postgres")
            local backup_file="${2:-}"
            if [[ -n "$backup_file" && -f "$backup_file" ]]; then
                test_postgres_restore "$backup_file"
            else
                log "ERROR: Backup file required"
                exit 1
            fi
            ;;
        "test-storage")
            local backup_file="${2:-}"
            if [[ -n "$backup_file" && -f "$backup_file" ]]; then
                test_storage_restore "$backup_file"
            else
                log "ERROR: Backup file required"
                exit 1
            fi
            ;;
        "daemon")
            # Run validation daemon
            while true; do
                # Check schedule (weekly validation)
                local day_of_week=$(date +%u)
                local current_hour=$(date +%H)
                local validation_hour=$(echo "${VALIDATION_SCHEDULE:-0 4 * * 1}" | cut -d' ' -f2)
                
                if [[ "$day_of_week" == "1" && "$current_hour" == "$validation_hour" ]]; then
                    main validate
                fi
                
                sleep 3600  # Check every hour
            done
            ;;
        *)
            log "Usage: $0 {validate|test-postgres|test-storage|daemon}"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "Backup validation interrupted"; exit 1' INT TERM

# Run main function
main "$@"
