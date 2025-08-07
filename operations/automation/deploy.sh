#!/bin/bash
# Enterprise Deployment Script with Blue-Green Strategy
# Supports zero-downtime deployments for production environments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/supabase_deploy.log"
DATE=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Load environment variables
load_environment() {
    local env_name="$1"
    local env_file="$SCRIPT_DIR/.env.${env_name}"
    
    if [[ -f "$env_file" ]]; then
        log "Loading environment: $env_name"
        source "$env_file"
    else
        log "ERROR: Environment file not found: $env_file"
        exit 1
    fi
}

# Health check function
health_check() {
    local service_url="$1"
    local timeout="${2:-60}"
    
    log "Performing health check on: $service_url"
    
    local count=0
    while [[ $count -lt $timeout ]]; do
        if curl -f "$service_url/health" &>/dev/null; then
            log "Health check passed"
            return 0
        fi
        
        ((count++))
        sleep 1
    done
    
    log "Health check failed after ${timeout}s"
    return 1
}

# Blue-Green deployment strategy
deploy_blue_green() {
    local environment="$1"
    local new_image="${2:-latest}"
    
    log "Starting blue-green deployment for $environment"
    
    # Determine current and new slots
    local current_slot=$(docker compose ps --services | grep -E "(blue|green)" | head -1)
    local new_slot="blue"
    
    if [[ "$current_slot" == *"blue"* ]]; then
        new_slot="green"
    fi
    
    log "Current slot: ${current_slot:-none}, New slot: $new_slot"
    
    # Update new slot with new image
    export DEPLOY_SLOT="$new_slot"
    export SUPABASE_IMAGE="$new_image"
    
    # Start new slot
    log "Starting new slot: $new_slot"
    docker compose --profile "$new_slot" up -d
    
    # Wait for new slot to be healthy
    local new_url="http://localhost:${new_slot}_port"
    if health_check "$new_url" 120; then
        log "New slot is healthy"
    else
        log "ERROR: New slot failed health check"
        docker compose --profile "$new_slot" down
        exit 1
    fi
    
    # Switch traffic to new slot
    log "Switching traffic to new slot"
    ./switch_traffic.sh "$new_slot"
    
    # Verify traffic switch
    if health_check "http://localhost:8000" 30; then
        log "Traffic switch successful"
        
        # Stop old slot
        if [[ -n "$current_slot" ]]; then
            log "Stopping old slot: $current_slot"
            docker compose --profile "$current_slot" down
        fi
        
        log "Blue-green deployment completed successfully"
    else
        log "ERROR: Traffic switch failed, rolling back"
        ./switch_traffic.sh "$current_slot"
        docker compose --profile "$new_slot" down
        exit 1
    fi
}

# Rolling deployment strategy
deploy_rolling() {
    local environment="$1"
    local new_image="${2:-latest}"
    
    log "Starting rolling deployment for $environment"
    
    # Get list of services to update
    local services=$(docker compose ps --services | grep -v -E "(postgres|redis)")
    
    for service in $services; do
        log "Updating service: $service"
        
        # Update service image
        docker compose up -d --no-deps "$service"
        
        # Wait for service to be healthy
        sleep 10
        if ! health_check "http://localhost:8000" 30; then
            log "ERROR: Service $service failed health check"
            exit 1
        fi
        
        log "Service $service updated successfully"
    done
    
    log "Rolling deployment completed successfully"
}

# Canary deployment strategy
deploy_canary() {
    local environment="$1"
    local new_image="${2:-latest}"
    local canary_percentage="${3:-10}"
    
    log "Starting canary deployment for $environment (${canary_percentage}% traffic)"
    
    # Deploy canary version
    export CANARY_IMAGE="$new_image"
    docker compose --profile canary up -d
    
    # Configure traffic split
    ./configure_traffic_split.sh "$canary_percentage"
    
    # Monitor canary for specified duration
    local monitor_duration=300  # 5 minutes
    log "Monitoring canary for ${monitor_duration}s"
    
    local start_time=$(date +%s)
    while [[ $(($(date +%s) - start_time)) -lt $monitor_duration ]]; do
        # Check error rates and performance metrics
        local error_rate=$(./get_error_rate.sh canary)
        local response_time=$(./get_response_time.sh canary)
        
        if [[ $(echo "$error_rate > 0.1" | bc -l) -eq 1 ]] || [[ $(echo "$response_time > 500" | bc -l) -eq 1 ]]; then
            log "ERROR: Canary metrics exceeded thresholds (error_rate: $error_rate, response_time: $response_time)"
            
            # Rollback canary
            ./configure_traffic_split.sh 0
            docker compose --profile canary down
            exit 1
        fi
        
        sleep 30
    done
    
    # Promote canary to full deployment
    log "Canary validation successful, promoting to full deployment"
    ./configure_traffic_split.sh 100
    
    # Update main services
    docker compose up -d
    
    # Remove canary
    docker compose --profile canary down
    
    log "Canary deployment completed successfully"
}

# Database migration function
run_migrations() {
    local environment="$1"
    
    log "Running database migrations for $environment"
    
    # Create migration backup
    local migration_backup="migration_backup_${DATE}.sql.gz"
    pg_dump -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip > "/backups/$migration_backup"
    
    # Run migrations
    if [[ -d "$SCRIPT_DIR/migrations" ]]; then
        for migration in "$SCRIPT_DIR/migrations"/*.sql; do
            if [[ -f "$migration" ]]; then
                log "Running migration: $(basename "$migration")"
                psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$migration"
            fi
        done
    fi
    
    log "Database migrations completed"
}

# Configuration validation
validate_configuration() {
    local environment="$1"
    
    log "Validating configuration for $environment"
    
    # Check required environment variables
    local required_vars=("POSTGRES_PASSWORD" "JWT_SECRET" "ANON_KEY" "SERVICE_ROLE_KEY")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR: Required environment variable not set: $var"
            exit 1
        fi
    done
    
    # Validate Docker Compose configuration
    if ! docker compose config > /dev/null; then
        log "ERROR: Invalid Docker Compose configuration"
        exit 1
    fi
    
    # Check resource requirements
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    local required_memory=2048
    
    if [[ $available_memory -lt $required_memory ]]; then
        log "WARNING: Available memory ($available_memory MB) below recommended ($required_memory MB)"
    fi
    
    log "Configuration validation passed"
}

# Pre-deployment checks
pre_deployment_checks() {
    local environment="$1"
    
    log "Running pre-deployment checks"
    
    # Check Docker daemon
    if ! docker info > /dev/null 2>&1; then
        log "ERROR: Docker daemon not running"
        exit 1
    fi
    
    # Check disk space
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log "ERROR: Insufficient disk space (available: ${available_space}KB, required: ${required_space}KB)"
        exit 1
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
        log "WARNING: No internet connectivity detected"
    fi
    
    # Verify backup systems
    if [[ "$environment" == "production" ]]; then
        if ! supabase-backup test > /dev/null 2>&1; then
            log "ERROR: Backup system not operational"
            exit 1
        fi
    fi
    
    log "Pre-deployment checks passed"
}

# Post-deployment validation
post_deployment_validation() {
    local environment="$1"
    
    log "Running post-deployment validation"
    
    # Comprehensive health checks
    local endpoints=(
        "http://localhost:8000/health"
        "http://localhost:8000/rest/v1/"
        "http://localhost:8000/auth/v1/health"
        "http://localhost:8000/storage/v1/buckets"
        "http://localhost:8000/realtime/v1/health"
    )
    
    for endpoint in "${endpoints[@]}"; do
        if ! curl -f "$endpoint" > /dev/null 2>&1; then
            log "ERROR: Endpoint validation failed: $endpoint"
            exit 1
        fi
    done
    
    # Database connectivity test
    if ! psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT 1;" > /dev/null; then
        log "ERROR: Database connectivity test failed"
        exit 1
    fi
    
    # Performance baseline test
    local response_time=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:8000/health)
    if [[ $(echo "$response_time > 1.0" | bc -l) -eq 1 ]]; then
        log "WARNING: High response time detected: ${response_time}s"
    fi
    
    log "Post-deployment validation passed"
}

# Rollback function
rollback_deployment() {
    local environment="$1"
    local rollback_version="${2:-previous}"
    
    log "Starting rollback for $environment to $rollback_version"
    
    # Stop current deployment
    docker compose down
    
    # Restore previous version
    if [[ "$rollback_version" == "previous" ]]; then
        # Get previous image tag from deployment history
        rollback_version=$(tail -2 /var/log/deployment_history.log | head -1 | cut -d' ' -f3)
    fi
    
    # Deploy previous version
    export SUPABASE_IMAGE="$rollback_version"
    docker compose up -d
    
    # Verify rollback
    if health_check "http://localhost:8000" 60; then
        log "Rollback completed successfully"
        
        # Log rollback event
        echo "$(date) ROLLBACK $environment $rollback_version" >> /var/log/deployment_history.log
    else
        log "ERROR: Rollback failed"
        exit 1
    fi
}

# Maintenance mode functions
enable_maintenance_mode() {
    log "Enabling maintenance mode"
    
    # Create maintenance page
    cat > /tmp/maintenance.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Maintenance Mode</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .container { max-width: 600px; margin: 0 auto; }
        .icon { font-size: 48px; margin: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">🚧</div>
        <h1>System Under Maintenance</h1>
        <p>We're currently performing scheduled maintenance. Please check back in a few minutes.</p>
        <p>We apologize for any inconvenience.</p>
    </div>
</body>
</html>
EOF
    
    # Deploy maintenance page via nginx
    sudo cp /tmp/maintenance.html /var/www/html/maintenance.html
    sudo nginx -s reload
    
    # Create maintenance flag
    touch /tmp/maintenance_mode
}

disable_maintenance_mode() {
    log "Disabling maintenance mode"
    
    # Remove maintenance flag
    rm -f /tmp/maintenance_mode
    
    # Restore normal nginx configuration
    sudo nginx -s reload
}

# Main deployment function
main() {
    local action="$1"
    local environment="${2:-staging}"
    local image="${3:-latest}"
    local strategy="${4:-rolling}"
    
    case "$action" in
        "deploy")
            log "=== Starting Supabase Deployment ==="
            log "Environment: $environment"
            log "Image: $image"
            log "Strategy: $strategy"
            
            # Load environment configuration
            load_environment "$environment"
            
            # Pre-deployment checks
            pre_deployment_checks "$environment"
            
            # Validate configuration
            validate_configuration "$environment"
            
            # Enable maintenance mode for production
            if [[ "$environment" == "production" ]]; then
                enable_maintenance_mode
            fi
            
            # Run database migrations
            run_migrations "$environment"
            
            # Deploy based on strategy
            case "$strategy" in
                "blue-green")
                    deploy_blue_green "$environment" "$image"
                    ;;
                "canary")
                    deploy_canary "$environment" "$image"
                    ;;
                "rolling"|*)
                    deploy_rolling "$environment" "$image"
                    ;;
            esac
            
            # Post-deployment validation
            post_deployment_validation "$environment"
            
            # Disable maintenance mode
            if [[ "$environment" == "production" ]]; then
                disable_maintenance_mode
            fi
            
            # Log successful deployment
            echo "$(date) DEPLOY $environment $image $strategy" >> /var/log/deployment_history.log
            
            log "=== Deployment Completed Successfully ==="
            ;;
            
        "rollback")
            rollback_deployment "$environment" "$image"
            ;;
            
        "maintenance")
            case "$environment" in
                "enable")
                    enable_maintenance_mode
                    ;;
                "disable")
                    disable_maintenance_mode
                    ;;
                *)
                    log "Usage: $0 maintenance {enable|disable}"
                    exit 1
                    ;;
            esac
            ;;
            
        "validate")
            load_environment "$environment"
            post_deployment_validation "$environment"
            ;;
            
        *)
            echo "Usage: $0 {deploy|rollback|maintenance|validate} [environment] [image] [strategy]"
            echo ""
            echo "Actions:"
            echo "  deploy     - Deploy application"
            echo "  rollback   - Rollback to previous version"
            echo "  maintenance - Enable/disable maintenance mode"
            echo "  validate   - Validate current deployment"
            echo ""
            echo "Environments: staging, production"
            echo "Strategies: rolling, blue-green, canary"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "Deployment interrupted"; disable_maintenance_mode 2>/dev/null || true; exit 1' INT TERM

# Create required directories
mkdir -p /var/log /backups

# Run main function
main "$@"
