#!/bin/bash
# WAL Manager for Point-in-Time Recovery (PITR)
# Handles WAL archiving and PITR setup

set -euo pipefail

LOG_FILE="/var/log/wal_manager.log"
WAL_ARCHIVE_DIR="/wal_archive"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log "Starting WAL manager..."

# Function to setup WAL-E for continuous archiving
setup_wal_e() {
    log "Setting up WAL-E for continuous archiving"
    
    # Create WAL-E configuration
    cat > /etc/wal-e.d/env << EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
WALE_S3_PREFIX=${WALE_S3_PREFIX}
AWS_REGION=${AWS_REGION}
WALE_S3_ENDPOINT=s3.${AWS_REGION}.amazonaws.com
WALE_SWIFT_PREFIX=
EOF
    
    chmod 600 /etc/wal-e.d/env
    
    # Test WAL-E configuration
    envdir /etc/wal-e.d/env wal-e backup-list || {
        log "WAL-E configuration test failed"
        return 1
    }
    
    log "WAL-E setup completed successfully"
}

# Function to perform base backup
perform_base_backup() {
    log "Starting base backup with WAL-E"
    
    # Create base backup
    if envdir /etc/wal-e.d/env wal-e backup-push /var/lib/postgresql/data; then
        log "Base backup completed successfully"
        
        # Create backup retention policy
        local retention_count="${BACKUP_RETENTION_COUNT:-7}"
        envdir /etc/wal-e.d/env wal-e delete --confirm retain "$retention_count"
        
        return 0
    else
        log "ERROR: Base backup failed"
        return 1
    fi
}

# Function to archive WAL files
archive_wal_file() {
    local wal_file="$1"
    local wal_path="$2"
    
    log "Archiving WAL file: $wal_file"
    
    # Archive with WAL-E
    if envdir /etc/wal-e.d/env wal-e wal-push "$wal_path"; then
        log "WAL file archived successfully: $wal_file"
        return 0
    else
        log "ERROR: WAL archiving failed: $wal_file"
        return 1
    fi
}

# Function to setup PostgreSQL for PITR
configure_postgres_pitr() {
    log "Configuring PostgreSQL for PITR"
    
    # Connect to PostgreSQL and configure
    psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" << EOF
-- Enable WAL archiving
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'envdir /etc/wal-e.d/env wal-e wal-push %p';
ALTER SYSTEM SET archive_timeout = '60s';

-- Configure for replication
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET max_replication_slots = 3;
ALTER SYSTEM SET wal_keep_size = '1GB';

-- Performance settings for backup
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';

-- Reload configuration
SELECT pg_reload_conf();
EOF
    
    log "PostgreSQL PITR configuration completed"
}

# Function to create recovery configuration template
create_recovery_template() {
    log "Creating recovery configuration template"
    
    cat > /backup_configs/recovery.conf.template << 'EOF'
# Recovery configuration for Point-in-Time Recovery
# Copy this file to recovery.conf in PostgreSQL data directory

# Restore command
restore_command = 'envdir /etc/wal-e.d/env wal-e wal-fetch "%f" "%p"'

# Recovery target (uncomment and modify as needed)
# recovery_target_time = 'YYYY-MM-DD HH:MM:SS'
# recovery_target_xid = 'transaction_id'
# recovery_target_name = 'restore_point_name'
# recovery_target_lsn = 'lsn_value'

# Recovery behavior
recovery_target_action = 'promote'
recovery_target_timeline = 'latest'

# Standby mode (for continuous replication)
# standby_mode = 'on'
# primary_conninfo = 'host=primary_host port=5432 user=replicator'
EOF
    
    log "Recovery template created at /backup_configs/recovery.conf.template"
}

# Function to perform PITR restoration
perform_pitr_restore() {
    local restore_target="$1"
    local restore_type="${2:-time}"  # time, xid, name, lsn
    local data_dir="/var/lib/postgresql/data"
    
    log "Starting PITR restore to $restore_type: $restore_target"
    
    # Stop PostgreSQL if running
    pg_ctl stop -D "$data_dir" -m fast || true
    
    # Remove existing data directory
    rm -rf "$data_dir"
    mkdir -p "$data_dir"
    chown postgres:postgres "$data_dir"
    
    # Restore base backup
    log "Restoring base backup..."
    if envdir /etc/wal-e.d/env wal-e backup-fetch "$data_dir" LATEST; then
        log "Base backup restored successfully"
    else
        log "ERROR: Base backup restore failed"
        return 1
    fi
    
    # Create recovery configuration
    cat > "$data_dir/recovery.conf" << EOF
restore_command = 'envdir /etc/wal-e.d/env wal-e wal-fetch "%f" "%p"'
recovery_target_${restore_type} = '${restore_target}'
recovery_target_action = 'promote'
recovery_target_timeline = 'latest'
EOF
    
    # Start PostgreSQL in recovery mode
    log "Starting PostgreSQL in recovery mode..."
    pg_ctl start -D "$data_dir"
    
    # Wait for recovery to complete
    while [[ ! -f "$data_dir/recovery.done" ]]; do
        sleep 5
        log "Waiting for recovery to complete..."
    done
    
    log "PITR restore completed successfully"
}

# Function to create restore point
create_restore_point() {
    local restore_point_name="$1"
    
    log "Creating restore point: $restore_point_name"
    
    psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "SELECT pg_create_restore_point('$restore_point_name');"
    
    log "Restore point created: $restore_point_name"
}

# Function to monitor WAL archiving
monitor_wal_archiving() {
    log "Monitoring WAL archiving status"
    
    # Check archiver status
    local archiver_stats=$(psql -h postgres -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT archived_count, last_archived_wal, last_archived_time, failed_count, last_failed_wal, last_failed_time FROM pg_stat_archiver;")
    
    log "Archiver stats: $archiver_stats"
    
    # Check for failed archives
    local failed_count=$(echo "$archiver_stats" | awk '{print $4}')
    if [[ "$failed_count" -gt 0 ]]; then
        log "WARNING: $failed_count WAL files failed to archive"
        
        # Send alert
        if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
            curl -X POST -H 'Content-type: application/json' \
                --data "{\"text\":\"⚠️ WAL archiving failures detected: $failed_count failed archives\"}" \
                "$SLACK_WEBHOOK_URL" || true
        fi
    fi
}

# Main function
main() {
    local action="${1:-daemon}"
    
    case "$action" in
        "setup")
            setup_wal_e
            configure_postgres_pitr
            create_recovery_template
            ;;
        "backup")
            perform_base_backup
            ;;
        "restore")
            local restore_target="${2:-}"
            local restore_type="${3:-time}"
            if [[ -n "$restore_target" ]]; then
                perform_pitr_restore "$restore_target" "$restore_type"
            else
                log "ERROR: Restore target required"
                exit 1
            fi
            ;;
        "restore-point")
            local point_name="${2:-manual_$(date +%Y%m%d_%H%M%S)}"
            create_restore_point "$point_name"
            ;;
        "monitor")
            monitor_wal_archiving
            ;;
        "daemon")
            # Setup on first run
            if [[ ! -f "/etc/wal-e.d/env" ]]; then
                setup_wal_e
                configure_postgres_pitr
                create_recovery_template
            fi
            
            # Run monitoring loop
            while true; do
                monitor_wal_archiving
                
                # Perform base backup weekly (Sunday at 1 AM)
                if [[ "$(date +%u)" == "7" && "$(date +%H)" == "01" ]]; then
                    perform_base_backup
                fi
                
                sleep 300  # Check every 5 minutes
            done
            ;;
        *)
            log "Usage: $0 {setup|backup|restore|restore-point|monitor|daemon}"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "WAL manager interrupted"; exit 1' INT TERM

# Run main function
main "$@"
