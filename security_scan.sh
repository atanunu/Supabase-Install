#!/bin/bash
# security_scan.sh - Security scanning and hardening script
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/supabase/security_scan.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check SSL configuration
check_ssl() {
    log "🔒 Checking SSL configuration..."
    
    # Check if SSL certificates exist
    if [[ -f "ssl/nginx/certificate.crt" && -f "ssl/nginx/private.key" ]]; then
        log "✅ SSL certificates found"
        
        # Check certificate validity
        if openssl x509 -in ssl/nginx/certificate.crt -noout -checkend 2592000; then
            log "✅ SSL certificate is valid for next 30 days"
        else
            log "⚠️  SSL certificate expires within 30 days"
        fi
    else
        log "❌ SSL certificates not found"
        log "   Run: openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ssl/nginx/private.key -out ssl/nginx/certificate.crt"
    fi
}

# Check database security
check_database_security() {
    log "🛡️  Checking database security..."
    
    # Check if database is accessible from outside
    if docker exec supabase-db psql -U postgres -c "\l" >/dev/null 2>&1; then
        log "✅ Database is accessible"
        
        # Check for default passwords
        if docker exec supabase-db psql -U postgres -c "SELECT usename FROM pg_user WHERE passwd IS NULL;" | grep -q postgres; then
            log "❌ Database has users with no password"
        else
            log "✅ All database users have passwords"
        fi
        
        # Check SSL mode
        ssl_mode=$(docker exec supabase-db psql -U postgres -t -c "SHOW ssl;" | tr -d ' ')
        if [[ "$ssl_mode" == "on" ]]; then
            log "✅ Database SSL is enabled"
        else
            log "⚠️  Database SSL is not enabled"
        fi
    else
        log "❌ Cannot connect to database"
    fi
}

# Check container security
check_container_security() {
    log "🐳 Checking container security..."
    
    # Check for containers running as root
    local root_containers
    root_containers=$(docker ps --format "table {{.Names}}\t{{.Image}}" | grep supabase | while read -r name image; do
        user=$(docker exec "$name" whoami 2>/dev/null || echo "unknown")
        if [[ "$user" == "root" ]]; then
            echo "$name"
        fi
    done)
    
    if [[ -z "$root_containers" ]]; then
        log "✅ No containers running as root"
    else
        log "⚠️  Containers running as root: $root_containers"
    fi
    
    # Check for containers with privileged mode
    local privileged_containers
    privileged_containers=$(docker ps --filter "label=com.docker.compose.project=supabase" --format "{{.Names}}" | while read -r container; do
        if docker inspect "$container" | grep -q '"Privileged": true'; then
            echo "$container"
        fi
    done)
    
    if [[ -z "$privileged_containers" ]]; then
        log "✅ No containers running in privileged mode"
    else
        log "⚠️  Containers running in privileged mode: $privileged_containers"
    fi
}

# Check network security
check_network_security() {
    log "🌐 Checking network security..."
    
    # Check exposed ports
    local exposed_ports
    exposed_ports=$(docker ps --filter "label=com.docker.compose.project=supabase" --format "{{.Ports}}" | grep -o "0.0.0.0:[0-9]*" | sort -u)
    
    log "📊 Exposed ports:"
    echo "$exposed_ports" | while read -r port; do
        log "   - $port"
    done
    
    # Check for unnecessary exposed ports
    if echo "$exposed_ports" | grep -q "5432"; then
        log "⚠️  PostgreSQL port (5432) is exposed to public"
    fi
    
    if echo "$exposed_ports" | grep -q "6379"; then
        log "⚠️  Redis port (6379) is exposed to public"
    fi
}

# Check authentication security
check_auth_security() {
    log "🔐 Checking authentication security..."
    
    # Check JWT secret strength
    if [[ -f ".env" ]]; then
        jwt_secret=$(grep "JWT_SECRET" .env | cut -d'=' -f2)
        if [[ ${#jwt_secret} -ge 32 ]]; then
            log "✅ JWT secret is sufficiently long"
        else
            log "⚠️  JWT secret should be at least 32 characters"
        fi
    else
        log "❌ .env file not found"
    fi
    
    # Check for default API keys
    if [[ -f ".env" ]] && grep -q "your-super-secret-jwt-token-with-at-least-32-characters-long" .env; then
        log "❌ Default JWT secret detected"
    fi
}

# Check file permissions
check_file_permissions() {
    log "📁 Checking file permissions..."
    
    # Check sensitive files
    sensitive_files=(".env" "config.env" "ssl/nginx/private.key")
    
    for file in "${sensitive_files[@]}"; do
        if [[ -f "$file" ]]; then
            perms=$(stat -c "%a" "$file")
            if [[ "$perms" == "600" || "$perms" == "640" ]]; then
                log "✅ $file has secure permissions ($perms)"
            else
                log "⚠️  $file has insecure permissions ($perms), should be 600 or 640"
            fi
        fi
    done
    
    # Check script permissions
    for script in *.sh; do
        if [[ -f "$script" ]]; then
            perms=$(stat -c "%a" "$script")
            if [[ "$perms" == "755" || "$perms" == "750" ]]; then
                log "✅ $script has correct permissions ($perms)"
            else
                log "⚠️  $script has unusual permissions ($perms)"
            fi
        fi
    done
}

# Run vulnerability scan
run_vulnerability_scan() {
    log "🔍 Running vulnerability scan..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log "⚠️  Running as root - this is not recommended"
    fi
    
    # Check for known vulnerabilities in images
    if command -v trivy >/dev/null 2>&1; then
        log "🔍 Scanning container images with Trivy..."
        docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "(supabase|postgres|kong)" | while read -r image; do
            log "Scanning $image..."
            trivy image --quiet --severity HIGH,CRITICAL "$image" | tee -a "$LOG_FILE"
        done
    else
        log "⚠️  Trivy not installed. Install with: sudo apt install trivy"
    fi
    
    # Check for outdated packages
    if command -v docker >/dev/null 2>&1; then
        docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        log "📊 Docker version: $docker_version"
    fi
}

# Generate security report
generate_security_report() {
    local report_file="/var/log/supabase/security_report_$(date +%Y%m%d_%H%M%S).json"
    
    log "📋 Generating security report: $report_file"
    
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "security_scan_results": {
    "ssl_configured": $([ -f "ssl/nginx/certificate.crt" ] && echo "true" || echo "false"),
    "database_ssl_enabled": $(docker exec supabase-db psql -U postgres -t -c "SHOW ssl;" 2>/dev/null | grep -q "on" && echo "true" || echo "false"),
    "exposed_ports": [$(docker ps --filter "label=com.docker.compose.project=supabase" --format "{{.Ports}}" | grep -o "0.0.0.0:[0-9]*" | sort -u | tr '\n' ',' | sed 's/,$//')],
    "containers_as_root": $(docker ps --format "table {{.Names}}" | grep supabase | wc -l),
    "env_file_exists": $([ -f ".env" ] && echo "true" || echo "false"),
    "config_file_exists": $([ -f "config.env" ] && echo "true" || echo "false")
  },
  "recommendations": [
    "Enable SSL/TLS for all communications",
    "Use strong passwords and API keys",
    "Limit exposed ports to necessary ones only",
    "Run containers with non-root users",
    "Regular security updates and scanning",
    "Implement proper backup encryption"
  ]
}
EOF
    
    log "✅ Security report generated: $report_file"
}

# Main security scan
main() {
    log "🔒 Starting comprehensive security scan..."
    
    mkdir -p /var/log/supabase
    
    check_ssl
    check_database_security
    check_container_security
    check_network_security
    check_auth_security
    check_file_permissions
    run_vulnerability_scan
    generate_security_report
    
    log "🎉 Security scan completed!"
    log "📋 Review the full log: $LOG_FILE"
    
    echo ""
    echo "🔒 Security Scan Summary"
    echo "========================"
    echo "📊 Log file: $LOG_FILE"
    echo "📋 Report: /var/log/supabase/security_report_*.json"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Review all warnings and recommendations"
    echo "2. Fix any critical security issues"
    echo "3. Update SSL certificates if needed"
    echo "4. Run scan regularly (weekly recommended)"
}

# Handle command line arguments
case "${1:-}" in
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo ""
        echo "Security scanning tool for Supabase installation"
        echo ""
        echo "Options:"
        echo "  --ssl-only     Check SSL configuration only"
        echo "  --db-only      Check database security only"
        echo "  --help         Show this help message"
        exit 0
        ;;
    "--ssl-only")
        check_ssl
        exit 0
        ;;
    "--db-only")
        check_database_security
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
