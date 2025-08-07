#!/bin/bash

# Enhanced Health Check Script with Web API Endpoint
# Provides comprehensive system health monitoring with JSON API output

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
HEALTH_CHECK_PORT="8888"
LOG_FILE="/var/log/supabase-health.log"
METRICS_FILE="/tmp/supabase-metrics.json"

# Function to log with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if service is running
check_service() {
    local service_name=$1
    local port=$2
    
    if docker compose ps | grep -q "$service_name.*Up"; then
        if nc -z localhost "$port" 2>/dev/null; then
            echo "healthy"
        else
            echo "unhealthy"
        fi
    else
        echo "stopped"
    fi
}

# Function to get service metrics
get_service_metrics() {
    local service_name=$1
    
    # Get container stats
    if docker ps --format "table {{.Names}}" | grep -q "$service_name"; then
        local stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}}" "$service_name" 2>/dev/null || echo "0%,0B / 0B")
        local cpu=$(echo "$stats" | cut -d',' -f1 | sed 's/%//')
        local memory=$(echo "$stats" | cut -d',' -f2 | cut -d'/' -f1 | sed 's/B//' | sed 's/[^0-9.]//g')
        
        echo "{\"cpu\": \"$cpu\", \"memory\": \"$memory\"}"
    else
        echo "{\"cpu\": \"0\", \"memory\": \"0\"}"
    fi
}

# Function to check database health
check_database() {
    local db_container="supabase_db_supabase"
    
    if docker exec "$db_container" pg_isready -U postgres >/dev/null 2>&1; then
        local connections=$(docker exec "$db_container" psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs || echo "0")
        local db_size=$(docker exec "$db_container" psql -U postgres -t -c "SELECT pg_size_pretty(pg_database_size('postgres'));" 2>/dev/null | xargs || echo "Unknown")
        
        echo "{\"status\": \"healthy\", \"connections\": $connections, \"size\": \"$db_size\"}"
    else
        echo "{\"status\": \"unhealthy\", \"connections\": 0, \"size\": \"Unknown\"}"
    fi
}

# Function to check SSL certificate
check_ssl() {
    local domain=${1:-"localhost"}
    
    if command -v openssl >/dev/null 2>&1; then
        local ssl_info=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "")
        
        if [[ -n "$ssl_info" ]]; then
            local expire_date=$(echo "$ssl_info" | grep "notAfter" | cut -d'=' -f2)
            local days_until_expiry=$(( ($(date -d "$expire_date" +%s) - $(date +%s)) / 86400 ))
            
            if [[ $days_until_expiry -gt 30 ]]; then
                echo "{\"status\": \"valid\", \"days_until_expiry\": $days_until_expiry}"
            elif [[ $days_until_expiry -gt 0 ]]; then
                echo "{\"status\": \"expiring_soon\", \"days_until_expiry\": $days_until_expiry}"
            else
                echo "{\"status\": \"expired\", \"days_until_expiry\": $days_until_expiry}"
            fi
        else
            echo "{\"status\": \"no_certificate\", \"days_until_expiry\": 0}"
        fi
    else
        echo "{\"status\": \"unknown\", \"days_until_expiry\": 0}"
    fi
}

# Function to get system metrics
get_system_metrics() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' || echo "0")
    local memory_info=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' || echo "0")
    local disk_usage=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//' || echo "0")
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' || echo "0")
    
    echo "{\"cpu\": \"$cpu_usage\", \"memory\": \"$memory_info\", \"disk\": \"$disk_usage\", \"load\": \"$load_avg\"}"
}

# Function to perform comprehensive health check
comprehensive_health_check() {
    log_message "Starting comprehensive health check..."
    
    # Check core services
    local kong_status=$(check_service "kong" "8000")
    local auth_status=$(check_service "auth" "9999")
    local rest_status=$(check_service "rest" "3000")
    local realtime_status=$(check_service "realtime" "4000")
    local storage_status=$(check_service "storage" "5000")
    local meta_status=$(check_service "meta" "8080")
    
    # Check database
    local db_metrics=$(check_database)
    
    # Check monitoring services
    local prometheus_status=$(check_service "prometheus" "9090")
    local grafana_status=$(check_service "grafana" "3000")
    
    # Get system metrics
    local system_metrics=$(get_system_metrics)
    
    # Check SSL if domain is provided
    local ssl_status="{\"status\": \"not_configured\"}"
    if [[ -n "${DOMAIN:-}" ]]; then
        ssl_status=$(check_ssl "$DOMAIN")
    fi
    
    # Generate overall health score
    local healthy_services=0
    local total_services=6
    
    [[ "$kong_status" == "healthy" ]] && ((healthy_services++))
    [[ "$auth_status" == "healthy" ]] && ((healthy_services++))
    [[ "$rest_status" == "healthy" ]] && ((healthy_services++))
    [[ "$realtime_status" == "healthy" ]] && ((healthy_services++))
    [[ "$storage_status" == "healthy" ]] && ((healthy_services++))
    [[ "$meta_status" == "healthy" ]] && ((healthy_services++))
    
    local health_score=$((healthy_services * 100 / total_services))
    
    # Overall system status
    local overall_status="healthy"
    if [[ $health_score -lt 100 ]]; then
        if [[ $health_score -ge 80 ]]; then
            overall_status="degraded"
        else
            overall_status="unhealthy"
        fi
    fi
    
    # Generate JSON output
    cat > "$METRICS_FILE" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "overall_status": "$overall_status",
    "health_score": $health_score,
    "services": {
        "kong": "$kong_status",
        "auth": "$auth_status",
        "rest": "$rest_status",
        "realtime": "$realtime_status",
        "storage": "$storage_status",
        "meta": "$meta_status",
        "prometheus": "$prometheus_status",
        "grafana": "$grafana_status"
    },
    "database": $db_metrics,
    "ssl": $ssl_status,
    "system": $system_metrics,
    "uptime": "$(uptime -p)",
    "version": "1.0.0"
}
EOF
    
    log_message "Health check completed. Status: $overall_status (Score: $health_score%)"
    
    # Output summary to console
    echo -e "${BLUE}=== Supabase Health Check Summary ===${NC}"
    echo -e "Overall Status: $([ "$overall_status" == "healthy" ] && echo -e "${GREEN}$overall_status${NC}" || echo -e "${YELLOW}$overall_status${NC}")"
    echo -e "Health Score: $health_score%"
    echo -e "Services Status:"
    echo -e "  Kong: $([ "$kong_status" == "healthy" ] && echo -e "${GREEN}$kong_status${NC}" || echo -e "${RED}$kong_status${NC}")"
    echo -e "  Auth: $([ "$auth_status" == "healthy" ] && echo -e "${GREEN}$auth_status${NC}" || echo -e "${RED}$auth_status${NC}")"
    echo -e "  REST: $([ "$rest_status" == "healthy" ] && echo -e "${GREEN}$rest_status${NC}" || echo -e "${RED}$rest_status${NC}")"
    echo -e "  Realtime: $([ "$realtime_status" == "healthy" ] && echo -e "${GREEN}$realtime_status${NC}" || echo -e "${RED}$realtime_status${NC}")"
    echo -e "  Storage: $([ "$storage_status" == "healthy" ] && echo -e "${GREEN}$storage_status${NC}" || echo -e "${RED}$storage_status${NC}")"
    echo -e "  Meta: $([ "$meta_status" == "healthy" ] && echo -e "${GREEN}$meta_status${NC}" || echo -e "${RED}$meta_status${NC}")"
    echo -e "${BLUE}===================================${NC}"
}

# Function to start health check API server
start_health_api() {
    log_message "Starting health check API server on port $HEALTH_CHECK_PORT..."
    
    # Simple HTTP server using Python or netcat
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import http.server
import socketserver
import json
import os

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            try:
                with open('$METRICS_FILE', 'r') as f:
                    self.wfile.write(f.read().encode())
            except:
                error_response = {\"error\": \"Health data not available\", \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}
                self.wfile.write(json.dumps(error_response).encode())
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found')

with socketserver.TCPServer(('', $HEALTH_CHECK_PORT), HealthHandler) as httpd:
    print('Health API server running on port $HEALTH_CHECK_PORT')
    httpd.serve_forever()
" &
        echo $! > /tmp/health-api.pid
        log_message "Health API server started (PID: $(cat /tmp/health-api.pid))"
    else
        log_message "Python3 not available. Health API server not started."
    fi
}

# Function to stop health check API server
stop_health_api() {
    if [[ -f /tmp/health-api.pid ]]; then
        local pid=$(cat /tmp/health-api.pid)
        if kill "$pid" 2>/dev/null; then
            log_message "Health API server stopped (PID: $pid)"
            rm -f /tmp/health-api.pid
        else
            log_message "Health API server was not running"
        fi
    else
        log_message "Health API server PID file not found"
    fi
}

# Main execution
case "${1:-check}" in
    "check")
        comprehensive_health_check
        ;;
    "api")
        comprehensive_health_check
        start_health_api
        ;;
    "stop-api")
        stop_health_api
        ;;
    "json")
        comprehensive_health_check
        cat "$METRICS_FILE"
        ;;
    "watch")
        while true; do
            clear
            comprehensive_health_check
            echo -e "\n${BLUE}Refreshing in 30 seconds... (Ctrl+C to stop)${NC}"
            sleep 30
        done
        ;;
    *)
        echo "Usage: $0 {check|api|stop-api|json|watch}"
        echo "  check     - Run single health check"
        echo "  api       - Start health check API server"
        echo "  stop-api  - Stop health check API server"
        echo "  json      - Output health data as JSON"
        echo "  watch     - Continuous monitoring"
        exit 1
        ;;
esac
