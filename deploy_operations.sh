#!/bin/bash
# Complete Operations Deployment Script
# Deploys runbooks, automation, configuration management, and scaling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/deploy_operations.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting operations deployment..."

# Function to deploy runbooks
deploy_runbooks() {
    log "Deploying operational runbooks..."
    
    # Create runbooks directory
    sudo mkdir -p /opt/supabase/runbooks
    
    # Copy runbooks
    sudo cp -r "$SCRIPT_DIR/runbooks/"* /opt/supabase/runbooks/
    
    # Make scripts executable
    sudo find /opt/supabase/runbooks -name "*.sh" -exec chmod +x {} \;
    
    # Create symlinks for easy access
    sudo ln -sf /opt/supabase/runbooks/OPERATIONS_RUNBOOK.md /usr/local/share/supabase-runbook
    
    log "Runbooks deployed successfully"
}

# Function to setup automation
deploy_automation() {
    log "Deploying automation and CI/CD..."
    
    # Create automation directory
    mkdir -p "$SCRIPT_DIR/.github/workflows"
    
    # Copy GitHub Actions workflow
    cp "$SCRIPT_DIR/automation/github_actions_workflow.yml" "$SCRIPT_DIR/.github/workflows/deploy.yml"
    
    # Copy deployment script
    sudo cp "$SCRIPT_DIR/automation/deploy.sh" /usr/local/bin/supabase-deploy
    sudo chmod +x /usr/local/bin/supabase-deploy
    
    # Create environment files templates
    cat > "$SCRIPT_DIR/.env.staging" << 'EOF'
# Staging Environment Configuration
ENVIRONMENT=staging
POSTGRES_PASSWORD=staging_password_change_me
JWT_SECRET=staging_jwt_secret_change_me
ANON_KEY=staging_anon_key
SERVICE_ROLE_KEY=staging_service_key
SITE_URL=https://staging.yourdomain.com
API_EXTERNAL_URL=https://staging.yourdomain.com
EOF
    
    cat > "$SCRIPT_DIR/.env.production" << 'EOF'
# Production Environment Configuration
ENVIRONMENT=production
POSTGRES_PASSWORD=production_password_change_me
JWT_SECRET=production_jwt_secret_change_me
ANON_KEY=production_anon_key
SERVICE_ROLE_KEY=production_service_key
SITE_URL=https://yourdomain.com
API_EXTERNAL_URL=https://yourdomain.com
EOF
    
    # Create deployment history log
    sudo touch /var/log/deployment_history.log
    sudo chown "$USER:$USER" /var/log/deployment_history.log
    
    log "Automation deployment completed"
}

# Function to deploy infrastructure as code
deploy_infrastructure() {
    log "Deploying infrastructure as code..."
    
    # Create terraform directory
    mkdir -p "$SCRIPT_DIR/terraform"
    
    # Copy Terraform files
    cp "$SCRIPT_DIR/configuration/main.tf" "$SCRIPT_DIR/terraform/"
    cp "$SCRIPT_DIR/configuration/userdata.sh" "$SCRIPT_DIR/terraform/"
    
    # Create terraform variables file
    cat > "$SCRIPT_DIR/terraform/terraform.tfvars.example" << 'EOF'
# Terraform Variables Example
# Copy to terraform.tfvars and customize

environment = "production"
region = "us-east-1"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

instance_type = "t3.large"
min_capacity = 2
max_capacity = 10

domain_name = "yourdomain.com"
ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"
EOF
    
    # Create Terraform initialization script
    cat > "$SCRIPT_DIR/terraform/init.sh" << 'EOF'
#!/bin/bash
# Initialize Terraform for Supabase infrastructure

set -euo pipefail

echo "Initializing Terraform for Supabase infrastructure..."

# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -var-file="terraform.tfvars"

echo "Terraform initialization completed."
echo "To deploy: terraform apply -var-file='terraform.tfvars'"
EOF
    
    chmod +x "$SCRIPT_DIR/terraform/init.sh"
    
    log "Infrastructure as code deployment completed"
}

# Function to setup configuration management
deploy_configuration_management() {
    log "Deploying configuration management..."
    
    # Create configuration management directory
    sudo mkdir -p /opt/supabase/config
    
    # Create configuration validation script
    cat > /tmp/validate_config.sh << 'EOF'
#!/bin/bash
# Configuration Validation Script

set -euo pipefail

CONFIG_DIR="/opt/supabase/config"
LOG_FILE="/var/log/config_validation.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

validate_environment_config() {
    local env_file="$1"
    
    if [[ ! -f "$env_file" ]]; then
        log "ERROR: Environment file not found: $env_file"
        return 1
    fi
    
    # Check required variables
    local required_vars=("POSTGRES_PASSWORD" "JWT_SECRET" "ANON_KEY" "SERVICE_ROLE_KEY")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            log "ERROR: Required variable missing in $env_file: $var"
            return 1
        fi
        
        # Check if variable has a value
        local value=$(grep "^${var}=" "$env_file" | cut -d'=' -f2-)
        if [[ -z "$value" || "$value" == *"change_me"* ]]; then
            log "ERROR: Variable $var in $env_file needs to be set"
            return 1
        fi
    done
    
    log "Configuration validation passed for: $env_file"
    return 0
}

validate_docker_config() {
    log "Validating Docker Compose configuration..."
    
    if docker compose config > /dev/null 2>&1; then
        log "Docker Compose configuration is valid"
        return 0
    else
        log "ERROR: Docker Compose configuration is invalid"
        return 1
    fi
}

main() {
    log "Starting configuration validation..."
    
    local errors=0
    
    # Validate environment files
    for env_file in .env .env.staging .env.production; do
        if [[ -f "$env_file" ]]; then
            validate_environment_config "$env_file" || ((errors++))
        fi
    done
    
    # Validate Docker configuration
    validate_docker_config || ((errors++))
    
    if [[ $errors -eq 0 ]]; then
        log "All configuration validations passed"
        exit 0
    else
        log "$errors configuration validation(s) failed"
        exit 1
    fi
}

main "$@"
EOF
    
    sudo cp /tmp/validate_config.sh /usr/local/bin/supabase-validate-config
    sudo chmod +x /usr/local/bin/supabase-validate-config
    
    # Create configuration backup script
    cat > /tmp/backup_config.sh << 'EOF'
#!/bin/bash
# Configuration Backup Script

set -euo pipefail

BACKUP_DIR="/opt/supabase/config/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Backup configuration files
tar -czf "$BACKUP_DIR/config_backup_${DATE}.tar.gz" \
    -C /opt/supabase \
    docker-compose*.yml \
    .env* \
    configs/

log "Configuration backup created: config_backup_${DATE}.tar.gz"

# Keep only last 30 backups
find "$BACKUP_DIR" -name "config_backup_*.tar.gz" -mtime +30 -delete
EOF
    
    sudo cp /tmp/backup_config.sh /usr/local/bin/supabase-backup-config
    sudo chmod +x /usr/local/bin/supabase-backup-config
    
    # Create configuration monitoring script
    cat > /tmp/monitor_config.sh << 'EOF'
#!/bin/bash
# Configuration Monitoring Script

set -euo pipefail

CONFIG_FILES=(
    "/opt/supabase/docker-compose.yml"
    "/opt/supabase/.env"
    "/opt/supabase/configs/backup.env"
)

LOG_FILE="/var/log/config_monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_config_changes() {
    local config_file="$1"
    local checksum_file="${config_file}.checksum"
    
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi
    
    local current_checksum=$(md5sum "$config_file" | cut -d' ' -f1)
    
    if [[ -f "$checksum_file" ]]; then
        local stored_checksum=$(cat "$checksum_file")
        
        if [[ "$current_checksum" != "$stored_checksum" ]]; then
            log "Configuration change detected: $config_file"
            
            # Backup configuration
            supabase-backup-config
            
            # Validate new configuration
            if supabase-validate-config; then
                log "Configuration validation passed for: $config_file"
                echo "$current_checksum" > "$checksum_file"
            else
                log "ERROR: Configuration validation failed for: $config_file"
                return 1
            fi
        fi
    else
        echo "$current_checksum" > "$checksum_file"
        log "Initial checksum created for: $config_file"
    fi
}

main() {
    log "Starting configuration monitoring..."
    
    for config_file in "${CONFIG_FILES[@]}"; do
        check_config_changes "$config_file"
    done
    
    log "Configuration monitoring completed"
}

if [[ "${1:-}" == "daemon" ]]; then
    # Run as daemon
    while true; do
        main
        sleep 300  # Check every 5 minutes
    done
else
    main
fi
EOF
    
    sudo cp /tmp/monitor_config.sh /usr/local/bin/supabase-monitor-config
    sudo chmod +x /usr/local/bin/supabase-monitor-config
    
    log "Configuration management deployment completed"
}

# Function to deploy capacity planning
deploy_capacity_planning() {
    log "Deploying capacity planning and scaling..."
    
    # Copy capacity planner script
    sudo cp "$SCRIPT_DIR/scaling/capacity_planner.sh" /usr/local/bin/supabase-capacity-planner
    sudo chmod +x /usr/local/bin/supabase-capacity-planner
    
    # Create scaling configuration
    cat > /tmp/scaling.conf << 'EOF'
# Supabase Scaling Configuration

# CPU thresholds
SCALE_UP_CPU_THRESHOLD=80
SCALE_DOWN_CPU_THRESHOLD=30

# Memory thresholds
SCALE_UP_MEMORY_THRESHOLD=85
SCALE_DOWN_MEMORY_THRESHOLD=40

# Response time thresholds (seconds)
SCALE_UP_RESPONSE_TIME=2.0
SCALE_DOWN_RESPONSE_TIME=0.5

# Error rate thresholds (percentage)
SCALE_UP_ERROR_RATE=1.0

# Instance limits
MIN_INSTANCES=2
MAX_INSTANCES=10

# Scaling cooldown (seconds)
SCALE_UP_COOLDOWN=300
SCALE_DOWN_COOLDOWN=600

# Monitoring endpoints
PROMETHEUS_URL=http://localhost:9090
GRAFANA_URL=http://localhost:3000
EOF
    
    sudo cp /tmp/scaling.conf /opt/supabase/config/scaling.conf
    
    # Create capacity planning cron jobs
    cat > /tmp/capacity_cron << 'EOF'
# Supabase Capacity Planning Cron Jobs

# Run capacity analysis every 5 minutes
*/5 * * * * root /usr/local/bin/supabase-capacity-planner analyze >> /var/log/capacity_planner.log 2>&1

# Generate weekly capacity report
0 6 * * 1 root /usr/local/bin/supabase-capacity-planner report >> /var/log/capacity_planner.log 2>&1

# Database optimization hourly
0 * * * * root /usr/local/bin/supabase-capacity-planner optimize >> /var/log/capacity_planner.log 2>&1
EOF
    
    sudo cp /tmp/capacity_cron /etc/cron.d/supabase_capacity
    sudo chmod 644 /etc/cron.d/supabase_capacity
    
    log "Capacity planning deployment completed"
}

# Function to setup operations monitoring
setup_operations_monitoring() {
    log "Setting up operations monitoring..."
    
    # Create operations dashboard for Grafana
    cat > /tmp/operations_dashboard.json << 'EOF'
{
    "dashboard": {
        "id": null,
        "title": "Supabase Operations Dashboard",
        "tags": ["supabase", "operations"],
        "timezone": "browser",
        "panels": [
            {
                "title": "Deployment Status",
                "type": "stat",
                "targets": [
                    {
                        "expr": "deployment_success_total"
                    }
                ],
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
            },
            {
                "title": "Scaling Events",
                "type": "graph",
                "targets": [
                    {
                        "expr": "scaling_events_total"
                    }
                ],
                "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
            },
            {
                "title": "Configuration Changes",
                "type": "logs",
                "targets": [
                    {
                        "expr": "{job=\"supabase-operations\"} |= \"configuration\""
                    }
                ],
                "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
            }
        ]
    }
}
EOF
    
    # Install dashboard if Grafana is available
    if curl -f http://localhost:3000/api/health &>/dev/null; then
        curl -X POST http://localhost:3000/api/dashboards/db \
            -H "Content-Type: application/json" \
            -d @/tmp/operations_dashboard.json || true
        log "Operations dashboard installed in Grafana"
    fi
    
    log "Operations monitoring setup completed"
}

# Function to run deployment tests
run_operations_tests() {
    log "Running operations deployment tests..."
    
    local test_errors=0
    
    # Test runbooks accessibility
    if [[ -f "/opt/supabase/runbooks/OPERATIONS_RUNBOOK.md" ]]; then
        log "✅ Runbooks test passed"
    else
        log "❌ Runbooks test failed"
        ((test_errors++))
    fi
    
    # Test automation scripts
    if command -v supabase-deploy &> /dev/null; then
        log "✅ Automation scripts test passed"
    else
        log "❌ Automation scripts test failed"
        ((test_errors++))
    fi
    
    # Test configuration management
    if command -v supabase-validate-config &> /dev/null; then
        log "✅ Configuration management test passed"
    else
        log "❌ Configuration management test failed"
        ((test_errors++))
    fi
    
    # Test capacity planning
    if command -v supabase-capacity-planner &> /dev/null; then
        log "✅ Capacity planning test passed"
    else
        log "❌ Capacity planning test failed"
        ((test_errors++))
    fi
    
    # Test cron jobs
    if sudo crontab -l | grep -q supabase; then
        log "✅ Cron jobs test passed"
    else
        log "❌ Cron jobs test failed"
        ((test_errors++))
    fi
    
    if [[ $test_errors -eq 0 ]]; then
        log "All operations tests passed"
        return 0
    else
        log "$test_errors operations tests failed"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    log "=== Operations Deployment Summary ==="
    
    echo "
🎉 Supabase Operations System Deployed Successfully!

📋 **Deployed Components:**
- ✅ Operational runbooks and procedures
- ✅ CI/CD automation with GitHub Actions
- ✅ Infrastructure as Code (Terraform)
- ✅ Configuration management and validation
- ✅ Intelligent capacity planning and scaling
- ✅ Operations monitoring and dashboards

🔧 **Available Commands:**
- supabase-deploy                # Deploy with various strategies
- supabase-validate-config       # Validate configurations
- supabase-backup-config         # Backup configurations
- supabase-monitor-config        # Monitor config changes
- supabase-capacity-planner      # Capacity planning and scaling

📊 **Automation Features:**
- Automated deployments with blue-green, canary, and rolling strategies
- Configuration drift detection and validation
- Intelligent auto-scaling based on metrics
- Capacity planning with trend analysis
- Weekly capacity reports

📂 **Key Locations:**
- Runbooks: /opt/supabase/runbooks/
- Terraform: $SCRIPT_DIR/terraform/
- GitHub Actions: $SCRIPT_DIR/.github/workflows/
- Configuration: /opt/supabase/config/
- Logs: /var/log/

🔗 **Next Steps:**
1. Configure GitHub Actions secrets
2. Initialize Terraform infrastructure
3. Set up environment-specific configurations
4. Review and customize runbooks
5. Configure monitoring endpoints

📞 **Support:**
- Runbooks: /opt/supabase/runbooks/OPERATIONS_RUNBOOK.md
- Logs: tail -f /var/log/deploy_operations.log
- Status: systemctl status supabase
"
}

# Main deployment function
main() {
    local action="${1:-deploy}"
    
    case "$action" in
        "deploy")
            deploy_runbooks
            deploy_automation
            deploy_infrastructure
            deploy_configuration_management
            deploy_capacity_planning
            setup_operations_monitoring
            
            if run_operations_tests; then
                display_summary
                log "Operations deployment completed successfully"
                exit 0
            else
                log "Operations deployment tests failed - please check logs"
                exit 1
            fi
            ;;
        "test")
            run_operations_tests
            ;;
        "status")
            echo "Operations deployment status:"
            echo "- Runbooks: $(test -f /opt/supabase/runbooks/OPERATIONS_RUNBOOK.md && echo "✅ Deployed" || echo "❌ Missing")"
            echo "- Automation: $(command -v supabase-deploy &> /dev/null && echo "✅ Deployed" || echo "❌ Missing")"
            echo "- Config Management: $(command -v supabase-validate-config &> /dev/null && echo "✅ Deployed" || echo "❌ Missing")"
            echo "- Capacity Planning: $(command -v supabase-capacity-planner &> /dev/null && echo "✅ Deployed" || echo "❌ Missing")"
            ;;
        *)
            echo "Usage: $0 {deploy|test|status}"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "Operations deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"
