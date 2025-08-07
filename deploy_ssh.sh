#!/bin/bash

# ============================================================================
# SSH DEPLOYMENT SCRIPT FOR SUPABASE ENTERPRISE
# Secure deployment to production server via SSH
# ============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/supabase-deploy.log"
BACKUP_DIR="/var/backups/supabase-deploy"
TEMP_DIR="/tmp/supabase-deploy-$$"

# Default values
SERVER_HOST=""
SERVER_USER="root"
SERVER_PORT="22"
DEPLOY_PATH="/opt/supabase"
SSH_KEY_PATH=""
ENVIRONMENT="production"
BACKUP_BEFORE_DEPLOY="true"
VALIDATE_DEPLOYMENT="true"
AUTO_START_SERVICES="true"

# Print functions
print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Help function
show_help() {
    cat << EOF
SSH DEPLOYMENT SCRIPT FOR SUPABASE ENTERPRISE

USAGE:
    $0 [OPTIONS] --server <SERVER_HOST>

REQUIRED:
    --server <HOST>          Production server hostname or IP address

OPTIONS:
    --user <USER>            SSH username (default: root)
    --port <PORT>            SSH port (default: 22)
    --key <PATH>             Path to SSH private key
    --path <PATH>            Deployment path on server (default: /opt/supabase)
    --env <ENV>              Environment name (default: production)
    --no-backup              Skip backup before deployment
    --no-validate            Skip deployment validation
    --no-start               Don't auto-start services after deployment
    --help                   Show this help message

EXAMPLES:
    # Basic deployment
    $0 --server my-server.com

    # Deployment with custom SSH key and user
    $0 --server 192.168.1.100 --user ubuntu --key ~/.ssh/production.pem

    # Deployment to custom path without auto-start
    $0 --server prod.example.com --path /app/supabase --no-start

REQUIREMENTS:
    - SSH access to target server
    - Docker and Docker Compose installed on target server
    - Sufficient disk space for deployment and backups
    - Valid environment configuration files

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --server)
                SERVER_HOST="$2"
                shift 2
                ;;
            --user)
                SERVER_USER="$2"
                shift 2
                ;;
            --port)
                SERVER_PORT="$2"
                shift 2
                ;;
            --key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            --path)
                DEPLOY_PATH="$2"
                shift 2
                ;;
            --env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --no-backup)
                BACKUP_BEFORE_DEPLOY="false"
                shift
                ;;
            --no-validate)
                VALIDATE_DEPLOYMENT="false"
                shift
                ;;
            --no-start)
                AUTO_START_SERVICES="false"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$SERVER_HOST" ]]; then
        print_error "Server hostname is required. Use --server option."
        exit 1
    fi
}

# Build SSH command
build_ssh_cmd() {
    local ssh_cmd="ssh"
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY_PATH"
    fi
    
    ssh_cmd="$ssh_cmd -p $SERVER_PORT $SERVER_USER@$SERVER_HOST"
    echo "$ssh_cmd"
}

# Build SCP command
build_scp_cmd() {
    local scp_cmd="scp"
    
    if [[ -n "$SSH_KEY_PATH" ]]; then
        scp_cmd="$scp_cmd -i $SSH_KEY_PATH"
    fi
    
    scp_cmd="$scp_cmd -P $SERVER_PORT"
    echo "$scp_cmd"
}

# Test SSH connection
test_ssh_connection() {
    print_info "Testing SSH connection to $SERVER_USER@$SERVER_HOST:$SERVER_PORT..."
    
    local ssh_cmd=$(build_ssh_cmd)
    
    if $ssh_cmd "echo 'SSH connection successful'" >/dev/null 2>&1; then
        print_success "SSH connection established"
        return 0
    else
        print_error "Failed to establish SSH connection"
        print_info "Please verify:"
        print_info "  - Server hostname: $SERVER_HOST"
        print_info "  - SSH port: $SERVER_PORT"
        print_info "  - Username: $SERVER_USER"
        if [[ -n "$SSH_KEY_PATH" ]]; then
            print_info "  - SSH key: $SSH_KEY_PATH"
        fi
        return 1
    fi
}

# Check server requirements
check_server_requirements() {
    print_info "Checking server requirements..."
    
    local ssh_cmd=$(build_ssh_cmd)
    
    # Check Docker
    if ! $ssh_cmd "command -v docker >/dev/null 2>&1"; then
        print_error "Docker is not installed on the server"
        return 1
    fi
    
    # Check Docker Compose
    if ! $ssh_cmd "command -v docker-compose >/dev/null 2>&1"; then
        print_error "Docker Compose is not installed on the server"
        return 1
    fi
    
    # Check disk space (require at least 10GB)
    local available_space
    available_space=$($ssh_cmd "df / | awk 'NR==2 {print \$4}'")
    if [[ $available_space -lt 10485760 ]]; then  # 10GB in KB
        print_warning "Low disk space: $(($available_space / 1024 / 1024))GB available"
        print_warning "Recommended: at least 10GB free space"
    fi
    
    print_success "Server requirements check completed"
}

# Create backup on server
create_server_backup() {
    if [[ "$BACKUP_BEFORE_DEPLOY" != "true" ]]; then
        print_info "Skipping backup (--no-backup specified)"
        return 0
    fi
    
    print_info "Creating backup on server..."
    
    local ssh_cmd=$(build_ssh_cmd)
    local backup_name="supabase-backup-$(date +%Y%m%d-%H%M%S)"
    
    $ssh_cmd "
        mkdir -p $BACKUP_DIR
        if [[ -d '$DEPLOY_PATH' ]]; then
            tar -czf '$BACKUP_DIR/$backup_name.tar.gz' -C '$(dirname $DEPLOY_PATH)' '$(basename $DEPLOY_PATH)'
            echo 'Backup created: $BACKUP_DIR/$backup_name.tar.gz'
        else
            echo 'No existing deployment found, skipping backup'
        fi
    "
    
    print_success "Backup completed"
}

# Prepare deployment files
prepare_deployment_files() {
    print_info "Preparing deployment files..."
    
    mkdir -p "$TEMP_DIR"
    
    # Copy all necessary files
    cp -r "$SCRIPT_DIR"/* "$TEMP_DIR/"
    
    # Ensure we have the production environment file
    if [[ ! -f "$TEMP_DIR/.env.production" ]]; then
        print_error "Production environment file (.env.production) not found"
        return 1
    fi
    
    # Create deployment info file
    cat > "$TEMP_DIR/deployment-info.txt" << EOF
Deployment Information
=====================
Date: $(date)
Environment: $ENVIRONMENT
Source: $(hostname):$SCRIPT_DIR
Target: $SERVER_USER@$SERVER_HOST:$DEPLOY_PATH
Git Commit: $(git rev-parse HEAD 2>/dev/null || echo "N/A")
Git Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
EOF
    
    print_success "Deployment files prepared"
}

# Transfer files to server
transfer_files() {
    print_info "Transferring files to server..."
    
    local ssh_cmd=$(build_ssh_cmd)
    local scp_cmd=$(build_scp_cmd)
    
    # Create deployment directory on server
    $ssh_cmd "mkdir -p $DEPLOY_PATH"
    
    # Transfer files
    $scp_cmd -r "$TEMP_DIR"/* "$SERVER_USER@$SERVER_HOST:$DEPLOY_PATH/"
    
    # Set proper permissions
    $ssh_cmd "
        cd $DEPLOY_PATH
        chmod +x *.sh
        chmod 600 .env.production
        chown -R $SERVER_USER:$SERVER_USER .
    "
    
    print_success "Files transferred successfully"
}

# Configure environment on server
configure_environment() {
    print_info "Configuring environment on server..."
    
    local ssh_cmd=$(build_ssh_cmd)
    
    $ssh_cmd "
        cd $DEPLOY_PATH
        
        # Copy production environment
        cp .env.production .env
        
        # Create necessary directories
        mkdir -p logs
        mkdir -p ssl
        mkdir -p database/{init,config}
        mkdir -p functions
        mkdir -p monitoring/{prometheus,grafana}/{provisioning,dashboards}
        mkdir -p nginx/conf.d
        mkdir -p static
        mkdir -p kong
        
        # Set proper permissions
        chmod 755 logs ssl database functions monitoring nginx static kong
        chmod -R 755 database monitoring nginx
        
        echo 'Environment configured successfully'
    "
    
    print_success "Environment configuration completed"
}

# Deploy services
deploy_services() {
    print_info "Deploying services on server..."
    
    local ssh_cmd=$(build_ssh_cmd)
    
    $ssh_cmd "
        cd $DEPLOY_PATH
        
        # Pull latest images
        docker-compose -f docker-compose.yml -f docker-compose.production.yml pull
        
        # Build and start services
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d --build
        
        echo 'Services deployment completed'
    "
    
    print_success "Services deployed successfully"
}

# Validate deployment on server
validate_deployment_remote() {
    if [[ "$VALIDATE_DEPLOYMENT" != "true" ]]; then
        print_info "Skipping deployment validation (--no-validate specified)"
        return 0
    fi
    
    print_info "Validating deployment on server..."
    
    local ssh_cmd=$(build_ssh_cmd)
    
    # Run validation script on server
    $ssh_cmd "
        cd $DEPLOY_PATH
        if [[ -f './validate_deployment.sh' ]]; then
            chmod +x validate_deployment.sh
            ./validate_deployment.sh --production
        else
            echo 'Validation script not found, performing basic checks...'
            docker-compose ps
            docker-compose logs --tail=20
        fi
    "
    
    print_success "Deployment validation completed"
}

# Start services if requested
start_services() {
    if [[ "$AUTO_START_SERVICES" != "true" ]]; then
        print_info "Skipping auto-start (--no-start specified)"
        return 0
    fi
    
    print_info "Starting services on server..."
    
    local ssh_cmd=$(build_ssh_cmd)
    
    $ssh_cmd "
        cd $DEPLOY_PATH
        docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d
        
        # Wait for services to be ready
        echo 'Waiting for services to be ready...'
        sleep 30
        
        # Check service health
        docker-compose ps
    "
    
    print_success "Services started successfully"
}

# Cleanup temporary files
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Main deployment function
main() {
    print_header "SUPABASE ENTERPRISE SSH DEPLOYMENT"
    
    log "Starting deployment to $SERVER_HOST"
    
    # Create log file if it doesn't exist
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/supabase-deploy.log"
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    # Execute deployment steps
    test_ssh_connection
    check_server_requirements
    create_server_backup
    prepare_deployment_files
    transfer_files
    configure_environment
    deploy_services
    validate_deployment_remote
    start_services
    
    print_header "DEPLOYMENT COMPLETED SUCCESSFULLY"
    print_success "Supabase Enterprise has been deployed to $SERVER_HOST"
    print_info "Deployment path: $DEPLOY_PATH"
    print_info "Environment: $ENVIRONMENT"
    print_info "Log file: $LOG_FILE"
    
    log "Deployment completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi
