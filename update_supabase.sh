#!/bin/bash
# update_supabase.sh - Enhanced Supabase stack update with health checks and rollback
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
    INSTALL_DIR="/opt/supabase"
    LOG_DIR="/var/log/supabase"
    HEALTH_CHECK_TIMEOUT=60
    UPDATE_NOTIFICATION=true
fi

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging setup
LOG_FILE="${LOG_DIR}/update.log"
DATE=$(date +%F-%H-%M-%S)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "❌ UPDATE FAILED: $1"
    send_notification "FAILED" "Update failed: $1"
    exit 1
}

# Success notification
update_success() {
    log "✅ UPDATE COMPLETED: $1"
    send_notification "SUCCESS" "Update completed successfully: $1"
}

# Send notification
send_notification() {
    local status="$1"
    local message="$2"
    
    # Use the notification script if available
    if [[ -f "${SCRIPT_DIR}/notify.sh" ]]; then
        "${SCRIPT_DIR}/notify.sh" "Supabase Update" "$message" "$status" 2>/dev/null || true
    fi
    
    # Legacy webhook support
    if [[ "${UPDATE_NOTIFICATION}" == "true" ]]; then
        if [[ -n "${WEBHOOK_URL:-}" ]]; then
            curl -s -X POST "$WEBHOOK_URL" \
                -H "Content-Type: application/json" \
                -d "{\"text\": \"[$status] Supabase Update: $message\"}" || true
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
    
    # Check if Supabase directory exists
    if [[ ! -d "$INSTALL_DIR/supabase" ]]; then
        error_exit "Supabase installation not found at $INSTALL_DIR/supabase"
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "$INSTALL_DIR/supabase/docker/docker-compose.yml" ]]; then
        error_exit "docker-compose.yml not found. Invalid Supabase installation."
    fi
    
    log "✅ Prerequisites check passed"
}

# Create pre-update backup
create_backup() {
    log "💾 Creating pre-update backup..."
    
    if [[ -f "${SCRIPT_DIR}/backup_supabase.sh" ]]; then
        if bash "${SCRIPT_DIR}/backup_supabase.sh"; then
            log "✅ Pre-update backup completed"
        else
            log "⚠️  Pre-update backup failed, but continuing with update"
        fi
    else
        log "⚠️  Backup script not found, skipping pre-update backup"
    fi
}

# Get current version info
get_version_info() {
    cd "$INSTALL_DIR/supabase"
    
    local current_commit
    current_commit=$(git rev-parse HEAD)
    
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    log "📋 Current version info:"
    log "   - Branch: $current_branch"
    log "   - Commit: ${current_commit:0:8}"
    log "   - Date: $(git show -s --format=%ci HEAD)"
}

# Check for updates
check_for_updates() {
    log "🔍 Checking for updates..."
    
    cd "$INSTALL_DIR/supabase"
    
    # Fetch latest changes
    git fetch origin || error_exit "Failed to fetch updates from repository"
    
    local local_commit
    local_commit=$(git rev-parse HEAD)
    
    local remote_commit
    remote_commit=$(git rev-parse origin/master)
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        log "ℹ️  Already up to date. No updates available."
        return 1
    else
        local commits_behind
        commits_behind=$(git rev-list --count HEAD..origin/master)
        log "🔄 Updates available: $commits_behind commits behind"
        return 0
    fi
}

# Stop services gracefully
stop_services() {
    log "🛑 Stopping Supabase services..."
    
    cd "$INSTALL_DIR/supabase/docker"
    
    # Graceful shutdown with timeout
    if timeout 30 docker compose down; then
        log "✅ Services stopped gracefully"
    else
        log "⚠️  Graceful shutdown timed out, forcing stop..."
        docker compose kill
        docker compose down --remove-orphans
        log "🔨 Services force stopped"
    fi
}

# Update repository
update_repository() {
    log "📥 Updating Supabase repository..."
    
    cd "$INSTALL_DIR/supabase"
    
    # Store current commit for potential rollback
    local old_commit
    old_commit=$(git rev-parse HEAD)
    echo "$old_commit" > "/tmp/supabase_update_rollback_${DATE}"
    
    # Pull latest changes
    if git pull origin master; then
        log "✅ Repository updated successfully"
        
        local new_commit
        new_commit=$(git rev-parse HEAD)
        log "📌 Updated to commit: ${new_commit:0:8}"
        
        # Show what changed
        log "📝 Changes in this update:"
        git log --oneline "${old_commit}..${new_commit}" | head -10 | while read -r line; do
            log "   - $line"
        done
    else
        error_exit "Failed to update repository"
    fi
}

# Update Docker images
update_docker_images() {
    log "🐳 Updating Docker images..."
    
    cd "$INSTALL_DIR/supabase/docker"
    
    if docker compose pull; then
        log "✅ Docker images updated successfully"
    else
        error_exit "Failed to update Docker images"
    fi
}

# Start services
start_services() {
    log "🚀 Starting Supabase services..."
    
    cd "$INSTALL_DIR/supabase/docker"
    
    if docker compose up -d; then
        log "✅ Services started successfully"
    else
        error_exit "Failed to start services"
    fi
}

# Health check function
health_check() {
    log "🏥 Performing health checks..."
    
    local timeout="${HEALTH_CHECK_TIMEOUT}"
    local check_interval=5
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        # Check if all containers are running
        cd "$INSTALL_DIR/supabase/docker"
        local running_containers
        running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
        local total_containers
        total_containers=$(docker compose ps --services | wc -l)
        
        if [[ $running_containers -eq $total_containers ]] && [[ $running_containers -gt 0 ]]; then
            # Additional checks
            if check_api_health && check_database_health; then
                log "✅ All health checks passed"
                return 0
            fi
        fi
        
        log "⏳ Health check in progress... ($elapsed/${timeout}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    log "❌ Health checks failed after ${timeout} seconds"
    return 1
}

# Check API health
check_api_health() {
    local api_url="http://localhost:8000/health"
    
    if curl -sf "$api_url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check database health
check_database_health() {
    if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Rollback function
rollback() {
    local rollback_file="/tmp/supabase_update_rollback_${DATE}"
    
    if [[ -f "$rollback_file" ]]; then
        local old_commit
        old_commit=$(cat "$rollback_file")
        
        log "🔄 Rolling back to previous version..."
        
        cd "$INSTALL_DIR/supabase"
        
        if git reset --hard "$old_commit"; then
            log "✅ Repository rolled back"
            
            # Restart services
            stop_services
            start_services
            
            if health_check; then
                log "✅ Rollback completed successfully"
                return 0
            else
                log "❌ Rollback failed health checks"
                return 1
            fi
        else
            log "❌ Failed to rollback repository"
            return 1
        fi
    else
        log "❌ Rollback file not found"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log "🧹 Cleaning up..."
    
    # Remove old rollback files (older than 7 days)
    find /tmp -name "supabase_update_rollback_*" -type f -mtime +7 -delete 2>/dev/null || true
    
    # Cleanup unused Docker resources
    docker system prune -f >/dev/null 2>&1 || true
    
    log "✅ Cleanup completed"
}

# Main update process
main() {
    local start_time
    start_time=$(date +%s)
    
    log "🚀 Starting Supabase update process..."
    log "📍 Installation directory: $INSTALL_DIR"
    log "📍 Health check timeout: ${HEALTH_CHECK_TIMEOUT}s"
    
    check_prerequisites
    get_version_info
    
    # Check if updates are available
    if ! check_for_updates; then
        log "✅ No updates needed"
        exit 0
    fi
    
    create_backup
    stop_services
    update_repository
    update_docker_images
    start_services
    
    # Perform health checks
    if health_check; then
        local end_time duration
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        
        cleanup
        update_success "Duration: ${duration}s"
        
        log "🎉 Update completed successfully in ${duration} seconds!"
        log "📊 Services are healthy and running"
        log "🌐 Dashboard: http://localhost:3000"
        log "🔍 View logs: tail -f $LOG_FILE"
    else
        log "❌ Health checks failed, attempting rollback..."
        
        if rollback; then
            error_exit "Update failed, successfully rolled back to previous version"
        else
            error_exit "Update failed and rollback failed. Manual intervention required."
        fi
    fi
}

# Trap errors and cleanup
trap 'error_exit "Script interrupted"' INT TERM

# Run main function
main "$@"
