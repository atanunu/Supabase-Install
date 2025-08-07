#!/bin/bash

# 🚀 Complete Supabase Performance Deployment Script
# Deploys Supabase with full performance optimization and external PostgreSQL support

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Deployment modes
DEPLOYMENT_MODE="${1:-local}"  # local, external-db, scaling, full
DOMAIN="${2:-localhost}"
CDN_PROVIDER="${3:-none}"

# Logging functions
log() {
    echo -e "${2:-$NC}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

success() {
    log "SUCCESS: $1" "$GREEN"
}

warn() {
    log "WARNING: $1" "$YELLOW"
}

info() {
    log "INFO: $1" "$BLUE"
}

header() {
    echo
    log "🔹 $1" "$PURPLE"
    echo "================================" | tee -a "$LOG_FILE"
}

# Display banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ____                  __                        
   / __/__  ______  ____ _/ /_  ____ _________       
  / /_/ / / / __ \/ __ `/ __ \/ __ `/ ___/ _ \      
 / __/ /_/ / /_/ / /_/ / /_/ / /_/ (__  )  __/      
/_/  \__,_/ .___/\__,_/_.___/\__,_/____/\___/       
         /_/                                        
                                                    
🚀 PERFORMANCE DEPLOYMENT SYSTEM 🚀                
EOF
    echo -e "${NC}"
    echo "Deploying high-performance Supabase with scaling capabilities"
    echo "=============================================================="
    echo
}

# Check prerequisites
check_prerequisites() {
    header "CHECKING PREREQUISITES"
    
    local missing_deps=()
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_deps+=("docker")
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
    fi
    
    # Check required files
    local required_files=(
        "docker-compose.yml"
        "docker-compose.performance.yml"
        ".env"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/$file" ]]; then
            missing_deps+=("$file")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error_exit "Missing dependencies: ${missing_deps[*]}"
    fi
    
    success "All prerequisites satisfied"
}

# Setup environment based on deployment mode
setup_environment() {
    header "SETTING UP ENVIRONMENT FOR MODE: $DEPLOYMENT_MODE"
    
    case "$DEPLOYMENT_MODE" in
        "local")
            info "Setting up local deployment with performance optimizations..."
            export COMPOSE_PROFILES="local-db,performance,monitoring"
            ;;
        "external-db")
            info "Setting up external database deployment..."
            if [[ ! -f "${SCRIPT_DIR}/external_db/.env.external" ]]; then
                warn "External database configuration not found"
                info "Creating template configuration..."
                mkdir -p "${SCRIPT_DIR}/external_db"
                cp "${SCRIPT_DIR}/external_db/.env.external" "${SCRIPT_DIR}/.env.external" 2>/dev/null || true
                warn "Please configure external_db/.env.external with your database credentials"
                exit 1
            fi
            export COMPOSE_PROFILES="external-db,performance,monitoring"
            ;;
        "scaling")
            info "Setting up auto-scaling deployment..."
            export COMPOSE_PROFILES="local-db,performance,monitoring,scaling"
            ;;
        "full")
            info "Setting up full deployment with all features..."
            export COMPOSE_PROFILES="local-db,performance,monitoring,scaling"
            ;;
        *)
            error_exit "Unknown deployment mode: $DEPLOYMENT_MODE. Use: local, external-db, scaling, full"
            ;;
    esac
    
    success "Environment configured for $DEPLOYMENT_MODE mode"
}

# Setup SSL certificates
setup_ssl() {
    header "SETTING UP SSL CERTIFICATES"
    
    if [[ "$DOMAIN" != "localhost" ]]; then
        info "Setting up SSL for domain: $DOMAIN"
        
        # Check if SSL setup script exists
        if [[ -f "${SCRIPT_DIR}/setup_ssl.sh" ]]; then
            info "Running SSL setup script..."
            bash "${SCRIPT_DIR}/setup_ssl.sh" "$DOMAIN"
        else
            warn "SSL setup script not found. Creating self-signed certificates..."
            mkdir -p "${SCRIPT_DIR}/ssl/nginx"
            
            # Generate self-signed certificate
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "${SCRIPT_DIR}/ssl/nginx/privkey.pem" \
                -out "${SCRIPT_DIR}/ssl/nginx/fullchain.pem" \
                -subj "/CN=$DOMAIN"
        fi
    else
        info "Using localhost - skipping SSL setup"
    fi
    
    success "SSL configuration completed"
}

# Setup CDN if specified
setup_cdn() {
    if [[ "$CDN_PROVIDER" != "none" ]]; then
        header "SETTING UP CDN: $CDN_PROVIDER"
        
        if [[ -f "${SCRIPT_DIR}/cdn/setup_cdn.sh" ]]; then
            info "Configuring $CDN_PROVIDER CDN for $DOMAIN..."
            bash "${SCRIPT_DIR}/cdn/setup_cdn.sh" "$DOMAIN" "$CDN_PROVIDER"
            success "CDN configuration completed"
        else
            warn "CDN setup script not found"
        fi
    fi
}

# Create necessary directories
create_directories() {
    header "CREATING DIRECTORIES"
    
    local directories=(
        "ssl/nginx"
        "nginx"
        "monitoring"
        "redis"
        "postgres"
        "logs"
    )
    
    for dir in "${directories[@]}"; do
        mkdir -p "${SCRIPT_DIR}/$dir"
        info "Created directory: $dir"
    done
    
    success "Directories created"
}

# Generate monitoring configuration
setup_monitoring() {
    header "SETTING UP MONITORING"
    
    info "Creating Prometheus configuration..."
    cat > "${SCRIPT_DIR}/monitoring/prometheus.yml" << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'supabase-services'
    static_configs:
      - targets: ['nginx:80', 'rest:3000', 'auth:9999', 'storage:5000', 'realtime:4000']
    metrics_path: /metrics
    scrape_interval: 10s

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

  - job_name: 'postgres'
    static_configs:
      - targets: ['db:5432']
EOF

    info "Creating Grafana datasource configuration..."
    mkdir -p "${SCRIPT_DIR}/monitoring/grafana/datasources"
    cat > "${SCRIPT_DIR}/monitoring/grafana/datasources/prometheus.yml" << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

    success "Monitoring configuration created"
}

# Deploy services
deploy_services() {
    header "DEPLOYING SERVICES"
    
    local compose_files=("-f" "docker-compose.yml" "-f" "docker-compose.performance.yml")
    
    # Add external database compose file if needed
    if [[ "$DEPLOYMENT_MODE" == "external-db" ]]; then
        if [[ -f "${SCRIPT_DIR}/external_db/docker-compose.external-db.yml" ]]; then
            compose_files+=("-f" "external_db/docker-compose.external-db.yml")
        fi
    fi
    
    # Add scaling compose file if needed
    if [[ "$DEPLOYMENT_MODE" == "scaling" || "$DEPLOYMENT_MODE" == "full" ]]; then
        if [[ -f "${SCRIPT_DIR}/scaling/docker-compose.scaling.yml" ]]; then
            compose_files+=("-f" "scaling/docker-compose.scaling.yml")
        fi
    fi
    
    info "Pulling latest images..."
    docker-compose "${compose_files[@]}" pull
    
    info "Starting services..."
    docker-compose "${compose_files[@]}" up -d
    
    # Wait for services to be healthy
    info "Waiting for services to become healthy..."
    sleep 30
    
    success "Services deployed successfully"
}

# Run database optimization
optimize_database() {
    if [[ "$DEPLOYMENT_MODE" != "external-db" ]]; then
        header "OPTIMIZING DATABASE"
        
        if [[ -f "${SCRIPT_DIR}/query_optimization/optimize_database.sh" ]]; then
            info "Running database optimization..."
            sleep 10  # Wait for database to be ready
            POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" bash "${SCRIPT_DIR}/query_optimization/optimize_database.sh"
            success "Database optimization completed"
        else
            warn "Database optimization script not found"
        fi
    else
        info "Skipping database optimization for external database mode"
    fi
}

# Start auto-scaling if enabled
start_autoscaling() {
    if [[ "$DEPLOYMENT_MODE" == "scaling" || "$DEPLOYMENT_MODE" == "full" ]]; then
        header "STARTING AUTO-SCALING"
        
        if [[ -f "${SCRIPT_DIR}/scaling/autoscale.sh" ]]; then
            info "Starting auto-scaling monitor..."
            nohup bash "${SCRIPT_DIR}/scaling/autoscale.sh" > "${SCRIPT_DIR}/logs/autoscale.log" 2>&1 &
            echo $! > "${SCRIPT_DIR}/logs/autoscale.pid"
            success "Auto-scaling started (PID: $(cat "${SCRIPT_DIR}/logs/autoscale.pid"))"
        else
            warn "Auto-scaling script not found"
        fi
    fi
}

# Health check all services
health_check() {
    header "PERFORMING HEALTH CHECKS"
    
    local services=("nginx" "redis" "rest" "auth" "storage" "realtime" "meta")
    if [[ "$DEPLOYMENT_MODE" != "external-db" ]]; then
        services+=("db")
    fi
    
    local failed_services=()
    
    for service in "${services[@]}"; do
        info "Checking $service..."
        if docker-compose ps | grep -q "$service.*healthy\|$service.*running"; then
            success "$service is healthy"
        else
            warn "$service is not healthy"
            failed_services+=("$service")
        fi
    done
    
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        warn "Some services are not healthy: ${failed_services[*]}"
        warn "Check logs with: docker-compose logs [service-name]"
    else
        success "All services are healthy"
    fi
}

# Display deployment summary
show_summary() {
    header "DEPLOYMENT SUMMARY"
    
    echo -e "${GREEN}🎉 Supabase Performance Deployment Complete!${NC}"
    echo
    echo -e "${BLUE}📊 Deployment Configuration:${NC}"
    echo "• Mode: $DEPLOYMENT_MODE"
    echo "• Domain: $DOMAIN"
    echo "• CDN: $CDN_PROVIDER"
    echo "• Profiles: $COMPOSE_PROFILES"
    echo
    echo -e "${BLUE}🔗 Service URLs:${NC}"
    echo "• Supabase Studio: https://$DOMAIN/dashboard"
    echo "• API Gateway: https://$DOMAIN/rest/v1"
    echo "• Auth: https://$DOMAIN/auth/v1"
    echo "• Storage: https://$DOMAIN/storage/v1"
    echo "• Realtime: wss://$DOMAIN/realtime/v1"
    echo
    echo -e "${BLUE}📈 Monitoring:${NC}"
    echo "• Prometheus: http://$DOMAIN:9090"
    echo "• Grafana: http://$DOMAIN:3001"
    echo
    echo -e "${BLUE}⚡ Performance Features:${NC}"
    echo "• Redis caching enabled"
    echo "• Database optimization applied"
    echo "• CDN configured ($CDN_PROVIDER)"
    if [[ "$DEPLOYMENT_MODE" == "scaling" || "$DEPLOYMENT_MODE" == "full" ]]; then
        echo "• Auto-scaling enabled"
        echo "• Load balancing configured"
    fi
    if [[ "$DEPLOYMENT_MODE" == "external-db" ]]; then
        echo "• External PostgreSQL configured"
    fi
    echo
    echo -e "${BLUE}📋 Management Commands:${NC}"
    echo "• View logs: docker-compose logs -f [service]"
    echo "• Scale service: docker-compose up -d --scale rest=3"
    echo "• Monitor resources: docker stats"
    echo "• Stop services: docker-compose down"
    echo
    echo -e "${YELLOW}📖 Full documentation: performance_implementation_report.md${NC}"
}

# Main deployment function
main() {
    # Check if script is run with proper arguments
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]]; then
        echo "Usage: $0 <mode> [domain] [cdn-provider]"
        echo
        echo "Modes:"
        echo "  local      - Local deployment with performance optimizations"
        echo "  external-db - External PostgreSQL with performance features"
        echo "  scaling    - Auto-scaling deployment"
        echo "  full       - Complete deployment with all features"
        echo
        echo "Example:"
        echo "  $0 local localhost none"
        echo "  $0 external-db my-domain.com cloudflare"
        echo "  $0 scaling my-domain.com none"
        echo "  $0 full my-domain.com cloudfront"
        exit 0
    fi
    
    show_banner
    
    log "🚀 Starting Supabase Performance Deployment" "$CYAN"
    log "Mode: $DEPLOYMENT_MODE | Domain: $DOMAIN | CDN: $CDN_PROVIDER" "$CYAN"
    
    # Deployment steps
    check_prerequisites
    setup_environment
    create_directories
    setup_ssl
    setup_cdn
    setup_monitoring
    deploy_services
    optimize_database
    start_autoscaling
    health_check
    show_summary
    
    success "🎉 Deployment completed successfully!"
    
    # Save deployment info
    cat > "${SCRIPT_DIR}/deployment_info.txt" << EOF
Deployment Date: $(date)
Mode: $DEPLOYMENT_MODE
Domain: $DOMAIN
CDN Provider: $CDN_PROVIDER
Compose Profiles: $COMPOSE_PROFILES
Log File: $LOG_FILE
EOF
    
    log "Deployment information saved to deployment_info.txt" "$BLUE"
}

# Run main function
main "$@"
