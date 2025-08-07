#!/bin/bash

# Supabase Deployment Validator
# Comprehensive validation script for production deployments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/supabase-validator.log"
VALIDATION_REPORT="/tmp/supabase-validation-report.json"

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Logging function
log_result() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case $level in
        "PASS")
            echo -e "${GREEN}✅ $message${NC}"
            ((PASSED_CHECKS++))
            ;;
        "FAIL")
            echo -e "${RED}❌ $message${NC}"
            ((FAILED_CHECKS++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ((WARNING_CHECKS++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
    ((TOTAL_CHECKS++))
}

# Validation functions
validate_prerequisites() {
    echo -e "${BLUE}=== Validating Prerequisites ===${NC}"
    
    # Check Docker
    if command -v docker >/dev/null 2>&1; then
        if docker --version | grep -q "Docker version"; then
            log_result "PASS" "Docker is installed and accessible"
        else
            log_result "FAIL" "Docker is installed but not accessible"
        fi
    else
        log_result "FAIL" "Docker is not installed"
    fi
    
    # Check Docker Compose
    if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
        log_result "PASS" "Docker Compose is available"
    else
        log_result "FAIL" "Docker Compose is not available"
    fi
    
    # Check system resources
    local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $memory_gb -ge 4 ]]; then
        log_result "PASS" "Sufficient memory available ($memory_gb GB)"
    elif [[ $memory_gb -ge 2 ]]; then
        log_result "WARN" "Limited memory available ($memory_gb GB) - 4GB+ recommended"
    else
        log_result "FAIL" "Insufficient memory ($memory_gb GB) - minimum 2GB required"
    fi
    
    # Check disk space
    local disk_space=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $disk_space -ge 20 ]]; then
        log_result "PASS" "Sufficient disk space available ($disk_space GB)"
    elif [[ $disk_space -ge 10 ]]; then
        log_result "WARN" "Limited disk space ($disk_space GB) - 20GB+ recommended"
    else
        log_result "FAIL" "Insufficient disk space ($disk_space GB) - minimum 10GB required"
    fi
    
    # Check required ports
    local required_ports=(80 443 3000 5432 8000 9090)
    for port in "${required_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            log_result "WARN" "Port $port is already in use"
        else
            log_result "PASS" "Port $port is available"
        fi
    done
}

validate_configuration() {
    echo -e "${BLUE}=== Validating Configuration ===${NC}"
    
    # Check for environment files
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        log_result "PASS" "Environment file (.env) exists"
        
        # Validate required variables
        local required_vars=("POSTGRES_PASSWORD" "JWT_SECRET" "ANON_KEY" "SERVICE_ROLE_KEY")
        for var in "${required_vars[@]}"; do
            if grep -q "^$var=" "$SCRIPT_DIR/.env"; then
                local value=$(grep "^$var=" "$SCRIPT_DIR/.env" | cut -d'=' -f2)
                if [[ -n "$value" && "$value" != "your-secret-here" ]]; then
                    log_result "PASS" "$var is configured"
                else
                    log_result "FAIL" "$var is not properly configured"
                fi
            else
                log_result "FAIL" "$var is missing from .env file"
            fi
        done
    else
        log_result "FAIL" "Environment file (.env) not found"
    fi
    
    # Check Docker Compose files
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        log_result "PASS" "Docker Compose file exists"
        
        # Validate compose file syntax
        if docker-compose -f "$SCRIPT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
            log_result "PASS" "Docker Compose file syntax is valid"
        else
            log_result "FAIL" "Docker Compose file has syntax errors"
        fi
    else
        log_result "FAIL" "Docker Compose file not found"
    fi
}

validate_ssl_configuration() {
    echo -e "${BLUE}=== Validating SSL Configuration ===${NC}"
    
    # Check if SSL certificates exist
    local ssl_dirs=("/etc/letsencrypt/live" "/etc/ssl/certs" "./ssl")
    local ssl_found=false
    
    for dir in "${ssl_dirs[@]}"; do
        if [[ -d "$dir" ]] && find "$dir" -name "*.crt" -o -name "*.pem" | grep -q .; then
            log_result "PASS" "SSL certificates found in $dir"
            ssl_found=true
            break
        fi
    done
    
    if [[ "$ssl_found" != true ]]; then
        log_result "WARN" "No SSL certificates found - HTTPS will not be available"
    fi
    
    # Check SSL configuration script
    if [[ -f "$SCRIPT_DIR/setup_ssl.sh" ]]; then
        log_result "PASS" "SSL setup script is available"
    else
        log_result "WARN" "SSL setup script not found"
    fi
}

validate_security_configuration() {
    echo -e "${BLUE}=== Validating Security Configuration ===${NC}"
    
    # Check firewall status
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            log_result "PASS" "UFW firewall is active"
        else
            log_result "WARN" "UFW firewall is not active"
        fi
    else
        log_result "WARN" "UFW firewall is not installed"
    fi
    
    # Check fail2ban
    if command -v fail2ban-client >/dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            log_result "PASS" "Fail2ban is active"
        else
            log_result "WARN" "Fail2ban is installed but not active"
        fi
    else
        log_result "WARN" "Fail2ban is not installed"
    fi
    
    # Check security script
    if [[ -f "$SCRIPT_DIR/implement_security.sh" ]]; then
        log_result "PASS" "Security implementation script is available"
    else
        log_result "WARN" "Security implementation script not found"
    fi
    
    # Check for default passwords
    if [[ -f "$SCRIPT_DIR/.env" ]]; then
        if grep -q "postgres" "$SCRIPT_DIR/.env" | grep -q "password"; then
            log_result "WARN" "Ensure default passwords have been changed"
        fi
    fi
}

validate_monitoring_setup() {
    echo -e "${BLUE}=== Validating Monitoring Setup ===${NC}"
    
    # Check monitoring configuration files
    local monitoring_files=("monitoring/prometheus.yml" "monitoring/grafana/provisioning/datasources/datasources.yml")
    
    for file in "${monitoring_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            log_result "PASS" "Monitoring file $file exists"
        else
            log_result "WARN" "Monitoring file $file not found"
        fi
    done
    
    # Check monitoring script
    if [[ -f "$SCRIPT_DIR/implement_monitoring.sh" ]]; then
        log_result "PASS" "Monitoring implementation script is available"
    else
        log_result "WARN" "Monitoring implementation script not found"
    fi
}

validate_backup_configuration() {
    echo -e "${BLUE}=== Validating Backup Configuration ===${NC}"
    
    # Check backup scripts
    local backup_scripts=("backup_supabase.sh" "deploy_backup_recovery.sh")
    
    for script in "${backup_scripts[@]}"; do
        if [[ -f "$SCRIPT_DIR/$script" ]]; then
            log_result "PASS" "Backup script $script exists"
        else
            log_result "WARN" "Backup script $script not found"
        fi
    done
    
    # Check backup directory
    if [[ -d "$SCRIPT_DIR/backup_recovery" ]]; then
        log_result "PASS" "Backup recovery directory exists"
    else
        log_result "WARN" "Backup recovery directory not found"
    fi
    
    # Check cron configuration
    if command -v crontab >/dev/null 2>&1; then
        if crontab -l 2>/dev/null | grep -q "backup"; then
            log_result "PASS" "Backup cron jobs are configured"
        else
            log_result "WARN" "No backup cron jobs found"
        fi
    else
        log_result "WARN" "Cron is not available"
    fi
}

validate_performance_setup() {
    echo -e "${BLUE}=== Validating Performance Setup ===${NC}"
    
    # Check performance scripts
    if [[ -f "$SCRIPT_DIR/deploy_performance.sh" ]]; then
        log_result "PASS" "Performance deployment script exists"
    else
        log_result "WARN" "Performance deployment script not found"
    fi
    
    # Check external database configuration
    if [[ -f "$SCRIPT_DIR/external_db/docker-compose.external-db.yml" ]]; then
        log_result "PASS" "External database configuration exists"
    else
        log_result "WARN" "External database configuration not found"
    fi
    
    # Check CDN configuration
    if [[ -f "$SCRIPT_DIR/cdn/setup_cdn.sh" ]]; then
        log_result "PASS" "CDN setup script exists"
    else
        log_result "WARN" "CDN setup script not found"
    fi
}

validate_operational_readiness() {
    echo -e "${BLUE}=== Validating Operational Readiness ===${NC}"
    
    # Check operations scripts
    if [[ -f "$SCRIPT_DIR/deploy_operations.sh" ]]; then
        log_result "PASS" "Operations deployment script exists"
    else
        log_result "FAIL" "Operations deployment script not found"
    fi
    
    # Check health check script
    if [[ -f "$SCRIPT_DIR/health_check.sh" ]]; then
        log_result "PASS" "Health check script exists"
    else
        log_result "WARN" "Health check script not found"
    fi
    
    # Check documentation
    local docs=("README.md" "DEPLOYMENT_GUIDE.md" "PRODUCTION_GUIDE.md")
    for doc in "${docs[@]}"; do
        if [[ -f "$SCRIPT_DIR/$doc" ]]; then
            log_result "PASS" "Documentation file $doc exists"
        else
            log_result "WARN" "Documentation file $doc not found"
        fi
    done
}

generate_validation_report() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local success_rate=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))
    
    local overall_status="PASS"
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        overall_status="FAIL"
    elif [[ $WARNING_CHECKS -gt 5 ]]; then
        overall_status="WARN"
    fi
    
    cat > "$VALIDATION_REPORT" <<EOF
{
    "timestamp": "$timestamp",
    "overall_status": "$overall_status",
    "success_rate": $success_rate,
    "summary": {
        "total_checks": $TOTAL_CHECKS,
        "passed": $PASSED_CHECKS,
        "failed": $FAILED_CHECKS,
        "warnings": $WARNING_CHECKS
    },
    "recommendations": [
        $([ $FAILED_CHECKS -gt 0 ] && echo '"Address all failed checks before production deployment",' || echo '')
        $([ $WARNING_CHECKS -gt 0 ] && echo '"Review and address warning items for optimal performance",' || echo '')
        "Run validation again after making changes",
        "Test deployment in staging environment first"
    ]
}
EOF
    
    echo -e "\n${BLUE}=== Validation Summary ===${NC}"
    echo -e "Overall Status: $([ "$overall_status" == "PASS" ] && echo -e "${GREEN}$overall_status${NC}" || echo -e "${RED}$overall_status${NC}")"
    echo -e "Success Rate: $success_rate%"
    echo -e "Total Checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNING_CHECKS${NC}"
    
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        echo -e "\n${RED}❌ Deployment is NOT ready for production${NC}"
        echo -e "Please address the failed checks above."
    elif [[ $WARNING_CHECKS -gt 5 ]]; then
        echo -e "\n${YELLOW}⚠️  Deployment has warnings${NC}"
        echo -e "Consider addressing warnings for optimal performance."
    else
        echo -e "\n${GREEN}✅ Deployment is ready for production!${NC}"
    fi
    
    echo -e "\nDetailed report saved to: $VALIDATION_REPORT"
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Supabase Deployment Validator${NC}"
    echo -e "${BLUE}===================================${NC}\n"
    
    # Initialize log file
    echo "=== Supabase Deployment Validation Started: $(date) ===" > "$LOG_FILE"
    
    # Run all validations
    validate_prerequisites
    validate_configuration
    validate_ssl_configuration
    validate_security_configuration
    validate_monitoring_setup
    validate_backup_configuration
    validate_performance_setup
    validate_operational_readiness
    
    # Generate final report
    generate_validation_report
    
    # Exit with appropriate code
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        exit 1
    elif [[ $WARNING_CHECKS -gt 5 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function
main "$@"
