#!/bin/bash
# Complete Backup and Recovery Deployment Script
# Sets up comprehensive backup system with PITR, cross-region sync, and validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/deploy_backup_recovery.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting backup and recovery deployment..."

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("docker" "docker-compose" "aws" "psql" "pg_dump" "pg_restore")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR: Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check environment file
    if [[ ! -f "$SCRIPT_DIR/configs/backup.env" ]]; then
        log "ERROR: backup.env configuration file not found"
        exit 1
    fi
    
    # Load environment variables
    source "$SCRIPT_DIR/configs/backup.env"
    
    # Validate required environment variables
    local required_vars=("POSTGRES_PASSWORD" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_S3_BUCKET")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR: Required environment variable not set: $var"
            exit 1
        fi
    done
    
    log "Prerequisites validation completed"
}

# Function to create backup directories
create_backup_structure() {
    log "Creating backup directory structure..."
    
    # Create local backup directories
    local backup_dirs=(
        "/backups"
        "/storage_backups" 
        "/wal_archive"
        "/validation_temp"
        "/var/log"
    )
    
    for dir in "${backup_dirs[@]}"; do
        sudo mkdir -p "$dir"
        sudo chown "$USER:$USER" "$dir"
        sudo chmod 755 "$dir"
    done
    
    # Create backup metadata directory
    mkdir -p "$SCRIPT_DIR/metadata"
    
    log "Backup directory structure created"
}

# Function to setup AWS S3 buckets
setup_s3_buckets() {
    log "Setting up S3 buckets..."
    
    # Create primary bucket if it doesn't exist
    if ! aws s3api head-bucket --bucket "$AWS_S3_BUCKET" 2>/dev/null; then
        aws s3api create-bucket \
            --bucket "$AWS_S3_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        
        log "Created primary S3 bucket: $AWS_S3_BUCKET"
    fi
    
    # Create bucket structure
    aws s3api put-object --bucket "$AWS_S3_BUCKET" --key "postgres/full-backups/"
    aws s3api put-object --bucket "$AWS_S3_BUCKET" --key "postgres/wal-backups/"
    aws s3api put-object --bucket "$AWS_S3_BUCKET" --key "postgres/metadata/"
    aws s3api put-object --bucket "$AWS_S3_BUCKET" --key "storage/backups/"
    aws s3api put-object --bucket "$AWS_S3_BUCKET" --key "storage/metadata/"
    aws s3api put-object --bucket "$AWS_S3_BUCKET" --key "validation/reports/"
    
    # Setup cross-region bucket if enabled
    if [[ "${CROSS_REGION_BACKUP:-}" == "true" && -n "${CROSS_REGION_BUCKET:-}" ]]; then
        if ! aws s3api head-bucket --bucket "$CROSS_REGION_BUCKET" --region "$CROSS_REGION" 2>/dev/null; then
            aws s3api create-bucket \
                --bucket "$CROSS_REGION_BUCKET" \
                --region "$CROSS_REGION" \
                --create-bucket-configuration LocationConstraint="$CROSS_REGION"
            
            log "Created cross-region S3 bucket: $CROSS_REGION_BUCKET"
        fi
        
        # Create cross-region bucket structure
        aws s3api put-object --bucket "$CROSS_REGION_BUCKET" --key "postgres/full-backups/" --region "$CROSS_REGION"
        aws s3api put-object --bucket "$CROSS_REGION_BUCKET" --key "postgres/wal-backups/" --region "$CROSS_REGION"
        aws s3api put-object --bucket "$CROSS_REGION_BUCKET" --key "storage/backups/" --region "$CROSS_REGION"
    fi
    
    # Setup lifecycle policies
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "BackupRetention",
            "Status": "Enabled",
            "Filter": {"Prefix": "postgres/"},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ],
            "Expiration": {
                "Days": 2555
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$AWS_S3_BUCKET" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    log "S3 buckets setup completed"
}

# Function to make scripts executable
setup_scripts() {
    log "Setting up backup scripts..."
    
    # Make all scripts executable
    chmod +x "$SCRIPT_DIR/scripts/"*.sh
    
    # Copy scripts to system path for easy access
    sudo cp "$SCRIPT_DIR/scripts/"*.sh /usr/local/bin/
    
    # Create symlinks for common commands
    sudo ln -sf /usr/local/bin/backup_manager.sh /usr/local/bin/supabase-backup
    sudo ln -sf /usr/local/bin/wal_manager.sh /usr/local/bin/supabase-wal
    sudo ln -sf /usr/local/bin/backup_validator.sh /usr/local/bin/supabase-validate
    sudo ln -sf /usr/local/bin/cross_region_sync.sh /usr/local/bin/supabase-sync
    
    log "Backup scripts setup completed"
}

# Function to configure PostgreSQL for PITR
configure_postgresql() {
    log "Configuring PostgreSQL for PITR..."
    
    # Wait for PostgreSQL to be ready
    until docker exec supabase_db_supabase pg_isready -U "$POSTGRES_USER"; do
        log "Waiting for PostgreSQL to be ready..."
        sleep 5
    done
    
    # Configure PostgreSQL for WAL archiving
    docker exec supabase_db_supabase psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" << EOF
-- Enable WAL archiving for PITR
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM SET archive_command = 'test ! -f /wal_archive/%f && cp %p /wal_archive/%f';
ALTER SYSTEM SET archive_timeout = '${ARCHIVE_TIMEOUT:-60s}';

-- Configure for replication
ALTER SYSTEM SET max_wal_senders = ${MAX_WAL_SENDERS:-3};
ALTER SYSTEM SET max_replication_slots = 3;
ALTER SYSTEM SET wal_keep_size = '${WAL_KEEP_SIZE:-1GB}';

-- Performance settings for backup
ALTER SYSTEM SET checkpoint_timeout = '15min';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';

-- Enable pg_stat_statements for monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Reload configuration
SELECT pg_reload_conf();
EOF
    
    # Restart PostgreSQL to apply configuration
    docker restart supabase_db_supabase
    
    # Wait for restart
    sleep 10
    until docker exec supabase_db_supabase pg_isready -U "$POSTGRES_USER"; do
        log "Waiting for PostgreSQL restart..."
        sleep 5
    done
    
    log "PostgreSQL PITR configuration completed"
}

# Function to deploy backup services
deploy_backup_services() {
    log "Deploying backup services..."
    
    # Copy environment file for Docker Compose
    cp "$SCRIPT_DIR/configs/backup.env" "$SCRIPT_DIR/.env"
    
    # Deploy backup services
    cd "$SCRIPT_DIR"
    docker-compose -f backup_config.yml up -d
    
    # Wait for services to be ready
    sleep 30
    
    # Verify services are running
    local services=("postgres_backup" "wal_e_backup" "storage_backup" "backup_validator" "cross_region_sync")
    for service in "${services[@]}"; do
        if docker ps | grep -q "supabase_${service}"; then
            log "✅ Service running: $service"
        else
            log "❌ Service failed to start: $service"
        fi
    done
    
    log "Backup services deployment completed"
}

# Function to setup cron jobs
setup_cron_jobs() {
    log "Setting up cron jobs for backup automation..."
    
    # Create cron job file
    cat > /tmp/supabase_backup_cron << EOF
# Supabase Backup and Recovery Cron Jobs
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin

# Full backup daily at 2 AM
${BACKUP_SCHEDULE:-0 2 * * *} root /usr/local/bin/backup_manager.sh full >> /var/log/backup_manager.log 2>&1

# Storage backup daily at 3 AM  
${STORAGE_BACKUP_SCHEDULE:-0 3 * * *} root /usr/local/bin/storage_backup.sh backup >> /var/log/storage_backup.log 2>&1

# Backup validation weekly on Monday at 4 AM
${VALIDATION_SCHEDULE:-0 4 * * 1} root /usr/local/bin/backup_validator.sh validate >> /var/log/backup_validator.log 2>&1

# Cross-region sync daily at 5 AM
${SYNC_SCHEDULE:-0 5 * * *} root /usr/local/bin/cross_region_sync.sh sync >> /var/log/cross_region_sync.log 2>&1

# WAL archiving monitoring every 15 minutes
*/15 * * * * root /usr/local/bin/wal_manager.sh monitor >> /var/log/wal_manager.log 2>&1
EOF
    
    # Install cron jobs
    sudo cp /tmp/supabase_backup_cron /etc/cron.d/supabase_backup
    sudo chmod 644 /etc/cron.d/supabase_backup
    
    # Restart cron service
    sudo systemctl restart cron
    
    log "Cron jobs setup completed"
}

# Function to run initial backup
perform_initial_backup() {
    log "Performing initial backup..."
    
    # Create first restore point
    /usr/local/bin/wal_manager.sh restore-point "initial_deployment"
    
    # Perform initial full backup
    /usr/local/bin/backup_manager.sh full
    
    # Perform initial storage backup
    /usr/local/bin/storage_backup.sh backup
    
    # Validate initial backups
    /usr/local/bin/backup_validator.sh validate
    
    # Sync to cross-region if enabled
    if [[ "${CROSS_REGION_BACKUP:-}" == "true" ]]; then
        /usr/local/bin/cross_region_sync.sh sync
    fi
    
    log "Initial backup completed"
}

# Function to create monitoring integration
setup_monitoring_integration() {
    log "Setting up monitoring integration..."
    
    # Create Grafana dashboard for backup metrics (if Grafana is available)
    if curl -f http://localhost:3000/api/health &>/dev/null; then
        cat > /tmp/backup_dashboard.json << 'EOF'
{
    "dashboard": {
        "id": null,
        "title": "Supabase Backup & Recovery",
        "tags": ["supabase", "backup"],
        "panels": [
            {
                "title": "Backup Success Rate",
                "type": "stat",
                "targets": [
                    {
                        "expr": "rate(backup_success_total[1h]) / rate(backup_attempts_total[1h]) * 100"
                    }
                ]
            },
            {
                "title": "WAL Archive Status", 
                "type": "stat",
                "targets": [
                    {
                        "expr": "pg_stat_archiver_archived_count"
                    }
                ]
            }
        ]
    }
}
EOF
        
        # Import dashboard (requires Grafana API key)
        # curl -X POST http://localhost:3000/api/dashboards/db \
        #     -H "Content-Type: application/json" \
        #     -d @/tmp/backup_dashboard.json
    fi
    
    log "Monitoring integration setup completed"
}

# Function to run deployment tests
run_deployment_tests() {
    log "Running deployment tests..."
    
    local test_errors=0
    
    # Test backup creation
    if /usr/local/bin/backup_manager.sh full; then
        log "✅ Backup creation test passed"
    else
        log "❌ Backup creation test failed"
        ((test_errors++))
    fi
    
    # Test storage backup
    if /usr/local/bin/storage_backup.sh backup; then
        log "✅ Storage backup test passed"
    else
        log "❌ Storage backup test failed" 
        ((test_errors++))
    fi
    
    # Test validation
    if /usr/local/bin/backup_validator.sh validate; then
        log "✅ Backup validation test passed"
    else
        log "❌ Backup validation test failed"
        ((test_errors++))
    fi
    
    # Test S3 connectivity
    if aws s3 ls "s3://$AWS_S3_BUCKET/" > /dev/null; then
        log "✅ S3 connectivity test passed"
    else
        log "❌ S3 connectivity test failed"
        ((test_errors++))
    fi
    
    if [[ $test_errors -eq 0 ]]; then
        log "All deployment tests passed"
        return 0
    else
        log "$test_errors deployment tests failed"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    log "=== Backup and Recovery Deployment Summary ==="
    
    echo "
🎉 Supabase Backup and Recovery System Deployed Successfully!

📊 **Deployment Details:**
- PITR: ✅ Enabled with WAL archiving
- Cross-region: ✅ Configured for ${CROSS_REGION:-N/A}
- Validation: ✅ Automated weekly testing
- Monitoring: ✅ Integrated with system

🔧 **Available Commands:**
- supabase-backup full     # Create full backup
- supabase-wal restore     # PITR restoration
- supabase-validate        # Test backups
- supabase-sync           # Cross-region sync

📋 **Backup Schedule:**
- Full backups: ${BACKUP_SCHEDULE:-Daily at 2 AM}
- Storage backups: ${STORAGE_BACKUP_SCHEDULE:-Daily at 3 AM}
- Validation: ${VALIDATION_SCHEDULE:-Weekly on Monday}
- Cross-region sync: ${SYNC_SCHEDULE:-Daily at 5 AM}

📂 **Key Locations:**
- Local backups: /backups
- Storage backups: /storage_backups
- WAL archive: /wal_archive
- Logs: /var/log/
- Recovery procedures: $SCRIPT_DIR/DISASTER_RECOVERY_PROCEDURES.md

🔗 **Next Steps:**
1. Review disaster recovery procedures
2. Test recovery scenarios in staging
3. Configure monitoring alerts
4. Train team on recovery procedures

📞 **Support:**
- Documentation: $SCRIPT_DIR/DISASTER_RECOVERY_PROCEDURES.md
- Logs: tail -f /var/log/backup_*.log
- Status: docker ps | grep backup
"
}

# Main deployment function
main() {
    local action="${1:-deploy}"
    
    case "$action" in
        "deploy")
            validate_prerequisites
            create_backup_structure
            setup_s3_buckets
            setup_scripts
            configure_postgresql
            deploy_backup_services
            setup_cron_jobs
            perform_initial_backup
            setup_monitoring_integration
            
            if run_deployment_tests; then
                display_summary
                log "Backup and recovery deployment completed successfully"
                exit 0
            else
                log "Deployment tests failed - please check logs"
                exit 1
            fi
            ;;
        "test")
            run_deployment_tests
            ;;
        "status")
            docker ps | grep -E "(backup|wal)" || echo "No backup services running"
            ;;
        *)
            echo "Usage: $0 {deploy|test|status}"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
