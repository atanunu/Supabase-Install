#!/bin/bash
# health_check.sh - Comprehensive health monitoring script for Supabase
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    INSTALL_DIR="/opt/supabase"
    LOG_DIR="/var/log/supabase"
fi

# Logging setup
LOG_FILE="${LOG_DIR}/health.log"
mkdir -p "$LOG_DIR"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Color output functions
print_status() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "OK")     echo -e "✅ \033[32m$message\033[0m" ;;
        "WARN")   echo -e "⚠️  \033[33m$message\033[0m" ;;
        "ERROR")  echo -e "❌ \033[31m$message\033[0m" ;;
        "INFO")   echo -e "ℹ️  \033[34m$message\033[0m" ;;
    esac
}

# Check Docker daemon
check_docker() {
    if docker info >/dev/null 2>&1; then
        print_status "OK" "Docker daemon is running"
        return 0
    else
        print_status "ERROR" "Docker daemon is not running"
        return 1
    fi
}

# Check Supabase containers
check_containers() {
    local failed=0
    
    print_status "INFO" "Checking Supabase containers..."
    
    cd "$INSTALL_DIR/supabase/docker" 2>/dev/null || {
        print_status "ERROR" "Supabase directory not found"
        return 1
    }
    
    # Get list of expected services
    local services
    services=$(docker compose config --services)
    
    for service in $services; do
        local container_status
        container_status=$(docker compose ps "$service" --format "table {{.State}}" | tail -n +2)
        
        if [[ "$container_status" == "running" ]]; then
            print_status "OK" "Container $service is running"
        elif [[ "$container_status" == "exited" ]]; then
            print_status "ERROR" "Container $service has exited"
            ((failed++))
        else
            print_status "WARN" "Container $service status: $container_status"
            ((failed++))
        fi
    done
    
    return $failed
}

# Check service endpoints
check_endpoints() {
    local failed=0
    
    print_status "INFO" "Checking service endpoints..."
    
    # API Gateway (Kong)
    if curl -sf "http://localhost:8000/" >/dev/null 2>&1; then
        print_status "OK" "API Gateway is responding"
    else
        print_status "ERROR" "API Gateway is not responding"
        ((failed++))
    fi
    
    # Auth service
    if curl -sf "http://localhost:9999/health" >/dev/null 2>&1; then
        print_status "OK" "Auth service is responding"
    else
        print_status "ERROR" "Auth service is not responding"
        ((failed++))
    fi
    
    # REST API
    if curl -sf "http://localhost:3000/" >/dev/null 2>&1; then
        print_status "OK" "REST API is responding"
    else
        print_status "ERROR" "REST API is not responding"
        ((failed++))
    fi
    
    # Realtime
    if curl -sf "http://localhost:4000/" >/dev/null 2>&1; then
        print_status "OK" "Realtime service is responding"
    else
        print_status "ERROR" "Realtime service is not responding"
        ((failed++))
    fi
    
    # Storage
    if curl -sf "http://localhost:5000/status" >/dev/null 2>&1; then
        print_status "OK" "Storage service is responding"
    else
        print_status "ERROR" "Storage service is not responding"
        ((failed++))
    fi
    
    # Studio Dashboard
    if curl -sf "http://localhost:3000/" >/dev/null 2>&1; then
        print_status "OK" "Studio dashboard is responding"
    else
        print_status "WARN" "Studio dashboard is not responding"
    fi
    
    return $failed
}

# Check database connectivity
check_database() {
    print_status "INFO" "Checking database connectivity..."
    
    if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
        print_status "OK" "Database is accepting connections"
        
        # Check database size
        local db_size
        db_size=$(docker exec supabase-db psql -U postgres -d postgres -t -c "SELECT pg_size_pretty(pg_database_size('postgres'));" | tr -d ' ')
        print_status "INFO" "Database size: $db_size"
        
        # Check active connections
        local connections
        connections=$(docker exec supabase-db psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity;" | tr -d ' ')
        print_status "INFO" "Active connections: $connections"
        
        return 0
    else
        print_status "ERROR" "Database is not accepting connections"
        return 1
    fi
}

# Check system resources
check_resources() {
    print_status "INFO" "Checking system resources..."
    
    # Memory usage
    local memory_info
    memory_info=$(free -h | awk 'NR==2{printf "Used: %s/%s (%.0f%%)", $3,$2,$3*100/$2}')
    print_status "INFO" "Memory $memory_info"
    
    # Disk usage
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2{printf "Used: %s/%s (%s)", $3,$2,$5}')
    print_status "INFO" "Disk $disk_usage"
    
    # Check if backup directory exists and its usage
    if [[ -d "${BACKUP_DIR:-/var/backups/supabase}" ]]; then
        local backup_disk_usage
        backup_disk_usage=$(df -h "${BACKUP_DIR:-/var/backups/supabase}" | awk 'NR==2{printf "Used: %s/%s (%s)", $3,$2,$5}')
        print_status "INFO" "Backup directory $backup_disk_usage"
    fi
    
    # CPU load
    local load_avg
    load_avg=$(uptime | awk -F'[a-z]:' '{print $2}' | sed 's/^ *//')
    print_status "INFO" "Load average:$load_avg"
    
    # Docker resource usage
    print_status "INFO" "Docker container resource usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep supabase || true
}

# Check logs for errors
check_logs() {
    print_status "INFO" "Checking recent logs for errors..."
    
    local log_files=(
        "$LOG_DIR/install.log"
        "$LOG_DIR/backup.log"
        "$LOG_DIR/update.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            local error_count
            error_count=$(grep -c "ERROR\|FAILED" "$log_file" 2>/dev/null || echo "0")
            
            if [[ $error_count -gt 0 ]]; then
                print_status "WARN" "Found $error_count errors in $(basename "$log_file")"
                # Show last few errors
                grep "ERROR\|FAILED" "$log_file" | tail -3 | while read -r line; do
                    print_status "WARN" "  $line"
                done
            else
                print_status "OK" "No errors in $(basename "$log_file")"
            fi
        fi
    done
}

# Generate health report
generate_report() {
    local total_checks="$1"
    local failed_checks="$2"
    
    echo ""
    echo "=========================================="
    echo "SUPABASE HEALTH CHECK REPORT"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Total checks: $total_checks"
    echo "Failed checks: $failed_checks"
    echo "Success rate: $(( (total_checks - failed_checks) * 100 / total_checks ))%"
    echo ""
    
    if [[ $failed_checks -eq 0 ]]; then
        print_status "OK" "All systems are healthy! 🎉"
    elif [[ $failed_checks -lt 3 ]]; then
        print_status "WARN" "Some issues detected, but system is mostly functional"
    else
        print_status "ERROR" "Multiple critical issues detected! Immediate attention required"
    fi
    
    echo ""
    echo "📋 Quick actions:"
    echo "  - View full logs: tail -f $LOG_FILE"
    echo "  - Restart services: cd $INSTALL_DIR/supabase/docker && docker compose restart"
    echo "  - Check containers: docker compose ps"
    echo "  - Access dashboard: http://localhost:3000"
    echo "=========================================="
}

# Main health check function
main() {
    local total_checks=0
    local failed_checks=0
    
    log "🏥 Starting comprehensive health check..."
    
    echo "🔍 Supabase Health Check"
    echo "========================"
    
    # Docker check
    if ! check_docker; then
        ((failed_checks++))
    fi
    ((total_checks++))
    
    # Container check
    local container_failures
    container_failures=$(check_containers || echo $?)
    if [[ $container_failures -gt 0 ]]; then
        ((failed_checks += container_failures))
    fi
    ((total_checks += 6))  # Approximate number of containers
    
    # Endpoint check
    local endpoint_failures
    endpoint_failures=$(check_endpoints || echo $?)
    if [[ $endpoint_failures -gt 0 ]]; then
        ((failed_checks += endpoint_failures))
    fi
    ((total_checks += 5))  # Number of endpoints
    
    # Database check
    if ! check_database; then
        ((failed_checks++))
    fi
    ((total_checks++))
    
    # Resource check
    check_resources
    
    # Log check
    check_logs
    
    # Generate report
    generate_report $total_checks $failed_checks
    
    # Log summary
    log "Health check completed. Failed: $failed_checks/$total_checks"
    
    # Exit with appropriate code
    if [[ $failed_checks -eq 0 ]]; then
        exit 0
    elif [[ $failed_checks -lt 3 ]]; then
        exit 1  # Warning
    else
        exit 2  # Critical
    fi
}

# Show usage if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo ""
    echo "Comprehensive health check for Supabase self-hosted installation"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --quiet       Suppress non-critical output"
    echo "  --json        Output results in JSON format"
    echo ""
    echo "Exit codes:"
    echo "  0 - All checks passed"
    echo "  1 - Some warnings detected"
    echo "  2 - Critical issues detected"
    exit 0
fi

# Run main function
main "$@"
