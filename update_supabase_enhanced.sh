#!/bin/bash

# Automated Update Script for Supabase Enterprise Deployment
# Handles rolling updates, dependency management, and rollback capabilities

set -e

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/tmp/supabase-backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/supabase-update.log"
ROLLBACK_INFO="/tmp/supabase-rollback-info.json"

# Version information
CURRENT_VERSION=""
TARGET_VERSION=""
UPDATE_TYPE="patch" # patch, minor, major

# Logging function
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "STEP")
            echo -e "${PURPLE}🔄 $message${NC}"
            ;;
    esac
}

# Function to create backup before update
create_backup() {
    log_message "STEP" "Creating backup before update..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup docker-compose files
    cp -r "$SCRIPT_DIR/docker-compose"* "$BACKUP_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/.env" "$BACKUP_DIR/" 2>/dev/null || true
    
    # Backup database
    if docker ps | grep -q "supabase.*db"; then
        log_message "INFO" "Creating database backup..."
        docker exec supabase_db_supabase pg_dump -U postgres postgres > "$BACKUP_DIR/database_backup.sql"
        log_message "SUCCESS" "Database backup created"
    fi
    
    # Backup volumes
    if docker volume ls | grep -q "supabase"; then
        log_message "INFO" "Creating volume backups..."
        docker run --rm -v supabase_db_data:/data -v "$BACKUP_DIR":/backup alpine tar czf /backup/volumes_backup.tar.gz -C /data .
        log_message "SUCCESS" "Volume backups created"
    fi
    
    # Store current container versions
    docker images --format "table {{.Repository}}:{{.Tag}}" | grep supabase > "$BACKUP_DIR/image_versions.txt"
    
    log_message "SUCCESS" "Backup completed: $BACKUP_DIR"
}

# Function to check for updates
check_for_updates() {
    log_message "STEP" "Checking for available updates..."
    
    # Check if we're using specific versions or latest
    if grep -q "supabase.*:latest" "$SCRIPT_DIR/docker-compose.yml"; then
        log_message "INFO" "Using latest tags - pulling newest images"
        return 0
    fi
    
    # For versioned deployments, check GitHub releases
    if command -v curl >/dev/null 2>&1; then
        local latest_release=$(curl -s https://api.github.com/repos/supabase/supabase/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        if [[ -n "$latest_release" ]]; then
            log_message "INFO" "Latest Supabase release: $latest_release"
            TARGET_VERSION="$latest_release"
        fi
    fi
    
    return 0
}

# Function to update system dependencies
update_dependencies() {
    log_message "STEP" "Updating system dependencies..."
    
    # Update package lists
    sudo apt update >/dev/null 2>&1
    
    # Update Docker if available
    if apt list --upgradable 2>/dev/null | grep -q docker; then
        log_message "INFO" "Docker update available"
        read -p "Update Docker? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo apt upgrade -y docker-ce docker-ce-cli containerd.io
            log_message "SUCCESS" "Docker updated"
        fi
    fi
    
    # Update other critical packages
    sudo apt upgrade -y openssl curl wget
    log_message "SUCCESS" "System dependencies updated"
}

# Function to update Docker images
update_docker_images() {
    log_message "STEP" "Updating Docker images..."
    
    # Pull latest images
    if docker-compose -f "$SCRIPT_DIR/docker-compose.yml" pull; then
        log_message "SUCCESS" "Docker images updated"
    else
        log_message "ERROR" "Failed to pull Docker images"
        return 1
    fi
    
    # Clean up old images
    docker image prune -f >/dev/null 2>&1
    log_message "INFO" "Cleaned up old Docker images"
}

# Function to perform rolling update
perform_rolling_update() {
    log_message "STEP" "Performing rolling update..."
    
    # Get list of services
    local services=$(docker-compose -f "$SCRIPT_DIR/docker-compose.yml" config --services)
    
    # Update services one by one (except database)
    for service in $services; do
        if [[ "$service" == *"db"* ]]; then
            log_message "INFO" "Skipping database service for rolling update"
            continue
        fi
        
        log_message "INFO" "Updating service: $service"
        
        # Stop service
        docker-compose -f "$SCRIPT_DIR/docker-compose.yml" stop "$service"
        
        # Start service with new image
        docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d "$service"
        
        # Wait for service to be healthy
        local retries=30
        while [[ $retries -gt 0 ]]; do
            if docker-compose -f "$SCRIPT_DIR/docker-compose.yml" ps "$service" | grep -q "Up"; then
                log_message "SUCCESS" "Service $service updated successfully"
                break
            fi
            sleep 2
            ((retries--))
        done
        
        if [[ $retries -eq 0 ]]; then
            log_message "ERROR" "Service $service failed to start"
            return 1
        fi
    done
    
    # Update database last if needed
    if echo "$services" | grep -q "db"; then
        log_message "INFO" "Updating database service..."
        docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d db
        
        # Wait for database to be ready
        local retries=60
        while [[ $retries -gt 0 ]]; do
            if docker exec supabase_db_supabase pg_isready -U postgres >/dev/null 2>&1; then
                log_message "SUCCESS" "Database service updated successfully"
                break
            fi
            sleep 2
            ((retries--))
        done
    fi
}

# Function to update configuration files
update_configurations() {
    log_message "STEP" "Updating configuration files..."
    
    # Update monitoring configurations
    if [[ -f "$SCRIPT_DIR/monitoring/prometheus.yml" ]]; then
        # Check for new monitoring rules or configurations
        if [[ -f "$SCRIPT_DIR/monitoring/prometheus/rules/supabase-alerts.yml" ]]; then
            docker exec prometheus_container promtool check rules /etc/prometheus/rules/supabase-alerts.yml >/dev/null 2>&1 && \
            log_message "SUCCESS" "Prometheus rules validated"
        fi
    fi
    
    # Update Grafana dashboards
    if [[ -d "$SCRIPT_DIR/monitoring/grafana/dashboards" ]]; then
        # Reload Grafana configuration
        if docker ps | grep -q grafana; then
            docker exec grafana_container curl -X POST http://admin:admin@localhost:3000/api/admin/provisioning/dashboards/reload >/dev/null 2>&1 && \
            log_message "SUCCESS" "Grafana dashboards reloaded"
        fi
    fi
    
    # Update nginx configuration if present
    if [[ -f "$SCRIPT_DIR/nginx/nginx.conf" ]]; then
        if command -v nginx >/dev/null 2>&1; then
            sudo nginx -t && sudo systemctl reload nginx
            log_message "SUCCESS" "Nginx configuration reloaded"
        fi
    fi
}

# Function to run post-update checks
run_post_update_checks() {
    log_message "STEP" "Running post-update health checks..."
    
    # Wait for all services to be ready
    sleep 10
    
    # Check service health
    if [[ -f "$SCRIPT_DIR/health_check.sh" ]]; then
        if "$SCRIPT_DIR/health_check.sh" >/dev/null 2>&1; then
            log_message "SUCCESS" "All services are healthy"
        else
            log_message "WARNING" "Some services may not be fully healthy"
        fi
    fi
    
    # Check API endpoints
    local endpoints=("http://localhost:8000/health" "http://localhost:3000/health")
    for endpoint in "${endpoints[@]}"; do
        if curl -sf "$endpoint" >/dev/null 2>&1; then
            log_message "SUCCESS" "Endpoint $endpoint is responding"
        else
            log_message "WARNING" "Endpoint $endpoint is not responding"
        fi
    done
    
    # Check database connectivity
    if docker exec supabase_db_supabase pg_isready -U postgres >/dev/null 2>&1; then
        log_message "SUCCESS" "Database is accessible"
    else
        log_message "ERROR" "Database is not accessible"
        return 1
    fi
}

# Function to save rollback information
save_rollback_info() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$ROLLBACK_INFO" <<EOF
{
    "timestamp": "$timestamp",
    "backup_location": "$BACKUP_DIR",
    "previous_images": "$(cat $BACKUP_DIR/image_versions.txt 2>/dev/null || echo 'N/A')",
    "update_type": "$UPDATE_TYPE",
    "target_version": "$TARGET_VERSION"
}
EOF
    
    log_message "INFO" "Rollback information saved to $ROLLBACK_INFO"
}

# Function to perform rollback
perform_rollback() {
    log_message "STEP" "Performing rollback..."
    
    if [[ ! -f "$ROLLBACK_INFO" ]]; then
        log_message "ERROR" "No rollback information found"
        return 1
    fi
    
    local backup_location=$(cat "$ROLLBACK_INFO" | grep backup_location | cut -d'"' -f4)
    
    if [[ ! -d "$backup_location" ]]; then
        log_message "ERROR" "Backup directory not found: $backup_location"
        return 1
    fi
    
    # Stop current services
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" down
    
    # Restore configuration files
    cp "$backup_location"/.env "$SCRIPT_DIR/" 2>/dev/null || true
    cp "$backup_location"/docker-compose* "$SCRIPT_DIR/" 2>/dev/null || true
    
    # Restore volumes if needed
    if [[ -f "$backup_location/volumes_backup.tar.gz" ]]; then
        docker run --rm -v supabase_db_data:/data -v "$backup_location":/backup alpine tar xzf /backup/volumes_backup.tar.gz -C /data
    fi
    
    # Restore database if needed
    if [[ -f "$backup_location/database_backup.sql" ]]; then
        docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d db
        sleep 10
        docker exec -i supabase_db_supabase psql -U postgres postgres < "$backup_location/database_backup.sql"
    fi
    
    # Start services
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
    
    log_message "SUCCESS" "Rollback completed"
}

# Function to clean up old backups
cleanup_old_backups() {
    log_message "STEP" "Cleaning up old backups..."
    
    # Keep only last 5 backups
    find /tmp -name "supabase-backup-*" -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
    
    log_message "SUCCESS" "Old backups cleaned up"
}

# Main update function
main_update() {
    log_message "INFO" "Starting Supabase update process..."
    
    # Pre-update checks
    if ! docker ps >/dev/null 2>&1; then
        log_message "ERROR" "Docker is not running"
        exit 1
    fi
    
    # Create backup
    create_backup
    save_rollback_info
    
    # Check for updates
    check_for_updates
    
    # Update system dependencies
    update_dependencies
    
    # Update Docker images
    if ! update_docker_images; then
        log_message "ERROR" "Failed to update Docker images"
        exit 1
    fi
    
    # Perform rolling update
    if ! perform_rolling_update; then
        log_message "ERROR" "Rolling update failed"
        log_message "INFO" "Initiating automatic rollback..."
        perform_rollback
        exit 1
    fi
    
    # Update configurations
    update_configurations
    
    # Run post-update checks
    if ! run_post_update_checks; then
        log_message "WARNING" "Post-update checks failed - manual verification recommended"
    fi
    
    # Clean up
    cleanup_old_backups
    
    log_message "SUCCESS" "Update completed successfully!"
    log_message "INFO" "Backup saved to: $BACKUP_DIR"
    log_message "INFO" "To rollback if needed: $0 rollback"
}

# Script usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  update      - Perform full update (default)"
    echo "  rollback    - Rollback to previous version"
    echo "  check       - Check for available updates"
    echo "  images      - Update Docker images only"
    echo ""
    echo "Options:"
    echo "  --backup-only     - Create backup and exit"
    echo "  --skip-backup     - Skip backup creation"
    echo "  --force          - Force update without confirmation"
    echo "  --help           - Show this help message"
}

# Main execution
case "${1:-update}" in
    "update")
        if [[ "$2" != "--force" ]]; then
            echo -e "${YELLOW}This will update your Supabase deployment.${NC}"
            echo -e "${YELLOW}A backup will be created automatically.${NC}"
            read -p "Continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Update cancelled."
                exit 0
            fi
        fi
        main_update
        ;;
    "rollback")
        perform_rollback
        ;;
    "check")
        check_for_updates
        ;;
    "images")
        update_docker_images
        ;;
    "backup")
        create_backup
        ;;
    "--help"|"help")
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
