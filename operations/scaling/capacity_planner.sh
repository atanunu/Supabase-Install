#!/bin/bash
# Intelligent Capacity Planning and Scaling System
# Automated scaling based on metrics and predictions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/capacity_planner.log"
METRICS_ENDPOINT="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_ENDPOINT="${GRAFANA_URL:-http://localhost:3000}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to get current metrics
get_current_metrics() {
    log "Collecting current system metrics..."
    
    # CPU utilization
    local cpu_usage=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=100-avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    # Memory utilization
    local memory_usage=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=(1-node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes)*100" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    # Database connections
    local db_connections=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=pg_stat_database_numbackends" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    # API request rate
    local request_rate=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=rate(http_requests_total[5m])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    # Disk usage
    local disk_usage=$(df / | awk 'NR==2 {print ($3/$2)*100}')
    
    # Response time
    local response_time=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=histogram_quantile(0.95,rate(http_request_duration_seconds_bucket[5m]))" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    # Error rate
    local error_rate=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=rate(http_requests_total{status=~\"5..\"}[5m])/rate(http_requests_total[5m])*100" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    cat > /tmp/current_metrics.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "cpu_usage": ${cpu_usage},
    "memory_usage": ${memory_usage},
    "db_connections": ${db_connections},
    "request_rate": ${request_rate},
    "disk_usage": ${disk_usage},
    "response_time": ${response_time},
    "error_rate": ${error_rate}
}
EOF
    
    log "Current metrics collected: CPU: ${cpu_usage}%, Memory: ${memory_usage}%, DB: ${db_connections} conn"
}

# Function to analyze trends
analyze_trends() {
    log "Analyzing historical trends..."
    
    # Get historical data for the last 24 hours
    local end_time=$(date +%s)
    local start_time=$((end_time - 86400))  # 24 hours ago
    
    # CPU trend
    local cpu_trend=$(curl -s "${METRICS_ENDPOINT}/api/v1/query_range?query=100-avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]))*100&start=${start_time}&end=${end_time}&step=3600" | jq -r '.data.result[0].values | length')
    
    # Calculate growth rates
    local request_growth=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=increase(http_requests_total[1h])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    local db_growth=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=increase(pg_stat_database_numbackends[1h])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    # Peak hour analysis
    local peak_hour=$(curl -s "${METRICS_ENDPOINT}/api/v1/query?query=max_over_time(rate(http_requests_total[5m])[24h:])" | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0")
    
    cat > /tmp/trend_analysis.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "request_growth_1h": ${request_growth},
    "db_growth_1h": ${db_growth},
    "peak_request_rate_24h": ${peak_hour},
    "data_points_24h": ${cpu_trend}
}
EOF
    
    log "Trend analysis completed: Growth rates calculated"
}

# Function to predict future capacity needs
predict_capacity() {
    log "Predicting future capacity requirements..."
    
    # Load current metrics and trends
    local current_metrics=$(cat /tmp/current_metrics.json)
    local trend_analysis=$(cat /tmp/trend_analysis.json)
    
    # Simple linear prediction (in production, use more sophisticated models)
    local current_cpu=$(echo "$current_metrics" | jq -r '.cpu_usage')
    local current_memory=$(echo "$current_metrics" | jq -r '.memory_usage')
    local current_requests=$(echo "$current_metrics" | jq -r '.request_rate')
    
    local request_growth=$(echo "$trend_analysis" | jq -r '.request_growth_1h')
    local peak_requests=$(echo "$trend_analysis" | jq -r '.peak_request_rate_24h')
    
    # Predict capacity for next 7 days (simplified linear model)
    local predicted_cpu=$(echo "$current_cpu + ($request_growth * 0.1 * 7)" | bc -l)
    local predicted_memory=$(echo "$current_memory + ($request_growth * 0.05 * 7)" | bc -l)
    local predicted_requests=$(echo "$current_requests + ($request_growth * 7)" | bc -l)
    
    # Calculate recommended scaling
    local recommended_instances=1
    if (( $(echo "$predicted_cpu > 70" | bc -l) )); then
        recommended_instances=$((recommended_instances + 1))
    fi
    if (( $(echo "$predicted_memory > 80" | bc -l) )); then
        recommended_instances=$((recommended_instances + 1))
    fi
    if (( $(echo "$predicted_requests > 1000" | bc -l) )); then
        recommended_instances=$((recommended_instances + 1))
    fi
    
    cat > /tmp/capacity_prediction.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "prediction_horizon_days": 7,
    "predicted_cpu_usage": ${predicted_cpu},
    "predicted_memory_usage": ${predicted_memory},
    "predicted_request_rate": ${predicted_requests},
    "recommended_instances": ${recommended_instances},
    "confidence_level": 0.75,
    "next_review_date": "$(date -d '+1 week' -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Capacity prediction completed: Recommended instances: $recommended_instances"
}

# Function to check scaling triggers
check_scaling_triggers() {
    log "Checking scaling triggers..."
    
    local current_metrics=$(cat /tmp/current_metrics.json)
    local cpu_usage=$(echo "$current_metrics" | jq -r '.cpu_usage')
    local memory_usage=$(echo "$current_metrics" | jq -r '.memory_usage')
    local response_time=$(echo "$current_metrics" | jq -r '.response_time')
    local error_rate=$(echo "$current_metrics" | jq -r '.error_rate')
    
    local scale_action="none"
    local scale_reason=""
    
    # Scale up triggers
    if (( $(echo "$cpu_usage > 80" | bc -l) )); then
        scale_action="scale_up"
        scale_reason="High CPU usage: ${cpu_usage}%"
    elif (( $(echo "$memory_usage > 85" | bc -l) )); then
        scale_action="scale_up"
        scale_reason="High memory usage: ${memory_usage}%"
    elif (( $(echo "$response_time > 2.0" | bc -l) )); then
        scale_action="scale_up"
        scale_reason="High response time: ${response_time}s"
    elif (( $(echo "$error_rate > 1.0" | bc -l) )); then
        scale_action="scale_up"
        scale_reason="High error rate: ${error_rate}%"
    # Scale down triggers (only if system is stable)
    elif (( $(echo "$cpu_usage < 30" | bc -l) )) && (( $(echo "$memory_usage < 40" | bc -l) )) && (( $(echo "$response_time < 0.5" | bc -l) )); then
        # Check if we have more than minimum instances
        local current_instances=$(docker ps --filter "name=supabase" --format "table {{.Names}}" | wc -l)
        if [[ $current_instances -gt 2 ]]; then
            scale_action="scale_down"
            scale_reason="Low resource utilization"
        fi
    fi
    
    cat > /tmp/scaling_decision.json << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "scale_action": "${scale_action}",
    "scale_reason": "${scale_reason}",
    "trigger_metrics": {
        "cpu_usage": ${cpu_usage},
        "memory_usage": ${memory_usage},
        "response_time": ${response_time},
        "error_rate": ${error_rate}
    }
}
EOF
    
    log "Scaling decision: $scale_action ($scale_reason)"
    echo "$scale_action"
}

# Function to execute scaling action
execute_scaling() {
    local action="$1"
    local reason="$2"
    
    case "$action" in
        "scale_up")
            log "Executing scale up action: $reason"
            
            # Scale up application containers
            docker compose up -d --scale rest=3 --scale realtime=2
            
            # If using AWS Auto Scaling Group
            if command -v aws &> /dev/null; then
                local current_desired=$(aws autoscaling describe-auto-scaling-groups \
                    --auto-scaling-group-names "supabase-asg-production" \
                    --query 'AutoScalingGroups[0].DesiredCapacity' \
                    --output text 2>/dev/null || echo "0")
                
                if [[ "$current_desired" != "0" && "$current_desired" -lt 10 ]]; then
                    local new_desired=$((current_desired + 1))
                    aws autoscaling set-desired-capacity \
                        --auto-scaling-group-name "supabase-asg-production" \
                        --desired-capacity "$new_desired"
                    
                    log "AWS ASG scaled up to $new_desired instances"
                fi
            fi
            
            # Wait for services to be ready
            sleep 30
            
            # Verify scaling was successful
            if curl -f http://localhost:8000/health > /dev/null 2>&1; then
                log "Scale up completed successfully"
                send_scaling_notification "SUCCESS" "Scale up" "$reason"
            else
                log "Scale up failed - health check failed"
                send_scaling_notification "FAILED" "Scale up" "$reason"
            fi
            ;;
            
        "scale_down")
            log "Executing scale down action: $reason"
            
            # Scale down application containers
            docker compose up -d --scale rest=2 --scale realtime=1
            
            # If using AWS Auto Scaling Group
            if command -v aws &> /dev/null; then
                local current_desired=$(aws autoscaling describe-auto-scaling-groups \
                    --auto-scaling-group-names "supabase-asg-production" \
                    --query 'AutoScalingGroups[0].DesiredCapacity' \
                    --output text 2>/dev/null || echo "0")
                
                if [[ "$current_desired" != "0" && "$current_desired" -gt 2 ]]; then
                    local new_desired=$((current_desired - 1))
                    aws autoscaling set-desired-capacity \
                        --auto-scaling-group-name "supabase-asg-production" \
                        --desired-capacity "$new_desired"
                    
                    log "AWS ASG scaled down to $new_desired instances"
                fi
            fi
            
            # Verify scaling was successful
            sleep 15
            if curl -f http://localhost:8000/health > /dev/null 2>&1; then
                log "Scale down completed successfully"
                send_scaling_notification "SUCCESS" "Scale down" "$reason"
            else
                log "Scale down failed - health check failed"
                send_scaling_notification "FAILED" "Scale down" "$reason"
            fi
            ;;
            
        "none")
            log "No scaling action required"
            ;;
    esac
}

# Function to send scaling notifications
send_scaling_notification() {
    local status="$1"
    local action="$2"
    local reason="$3"
    
    local emoji="📈"
    if [[ "$action" == "Scale down" ]]; then
        emoji="📉"
    fi
    
    if [[ "$status" == "FAILED" ]]; then
        emoji="❌"
    fi
    
    local message="$emoji Supabase Auto-Scaling: $action $status
    
    Reason: $reason
    Timestamp: $(date)
    Environment: ${ENVIRONMENT:-production}"
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" || true
    fi
    
    # Update Grafana annotation
    if [[ -n "${GRAFANA_API_KEY:-}" ]]; then
        curl -X POST \
            -H "Authorization: Bearer $GRAFANA_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{
                \"text\":\"$action: $reason\",
                \"tags\":[\"scaling\",\"automation\"],
                \"time\":$(date +%s)000
            }" \
            "$GRAFANA_ENDPOINT/api/annotations" || true
    fi
}

# Function to generate capacity report
generate_capacity_report() {
    log "Generating capacity planning report..."
    
    local report_date=$(date +%Y-%m-%d)
    local report_file="/tmp/capacity_report_${report_date}.json"
    
    # Combine all analysis data
    local current_metrics=$(cat /tmp/current_metrics.json 2>/dev/null || echo '{}')
    local trend_analysis=$(cat /tmp/trend_analysis.json 2>/dev/null || echo '{}')
    local capacity_prediction=$(cat /tmp/capacity_prediction.json 2>/dev/null || echo '{}')
    local scaling_decision=$(cat /tmp/scaling_decision.json 2>/dev/null || echo '{}')
    
    jq -n \
        --argjson current "$current_metrics" \
        --argjson trends "$trend_analysis" \
        --argjson prediction "$capacity_prediction" \
        --argjson scaling "$scaling_decision" \
        '{
            report_date: "'$report_date'",
            current_metrics: $current,
            trend_analysis: $trends,
            capacity_prediction: $prediction,
            scaling_decision: $scaling,
            recommendations: {
                immediate_actions: [],
                long_term_planning: [],
                cost_optimization: []
            }
        }' > "$report_file"
    
    # Add recommendations based on analysis
    local cpu_usage=$(echo "$current_metrics" | jq -r '.cpu_usage // 0')
    local memory_usage=$(echo "$current_metrics" | jq -r '.memory_usage // 0')
    local predicted_instances=$(echo "$capacity_prediction" | jq -r '.recommended_instances // 1')
    
    # Generate recommendations
    local recommendations=""
    
    if (( $(echo "$cpu_usage > 70" | bc -l) )); then
        recommendations+="Consider upgrading to higher CPU instances. "
    fi
    
    if (( $(echo "$memory_usage > 80" | bc -l) )); then
        recommendations+="Consider upgrading to higher memory instances. "
    fi
    
    if [[ "$predicted_instances" -gt 3 ]]; then
        recommendations+="Plan for horizontal scaling - consider load balancer optimization. "
    fi
    
    # Update report with recommendations
    jq --arg rec "$recommendations" \
        '.recommendations.immediate_actions = [$rec]' \
        "$report_file" > "${report_file}.tmp" && mv "${report_file}.tmp" "$report_file"
    
    log "Capacity report generated: $report_file"
    
    # Upload to S3 if configured
    if [[ -n "${AWS_S3_BUCKET:-}" ]]; then
        aws s3 cp "$report_file" "s3://${AWS_S3_BUCKET}/capacity-reports/" || true
        log "Capacity report uploaded to S3"
    fi
}

# Function to optimize database connections
optimize_database() {
    log "Optimizing database configuration..."
    
    local current_metrics=$(cat /tmp/current_metrics.json)
    local db_connections=$(echo "$current_metrics" | jq -r '.db_connections')
    local cpu_usage=$(echo "$current_metrics" | jq -r '.cpu_usage')
    
    # Get current PostgreSQL settings
    local max_connections=$(psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SHOW max_connections;" | xargs)
    local shared_buffers=$(psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SHOW shared_buffers;" | xargs)
    
    log "Current DB config: max_connections=$max_connections, shared_buffers=$shared_buffers"
    
    # Optimize based on current load
    if (( $(echo "$db_connections > 150" | bc -l) )) && [[ "$max_connections" -lt 300 ]]; then
        log "Increasing max_connections due to high usage"
        psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
            "ALTER SYSTEM SET max_connections = 300; SELECT pg_reload_conf();"
    fi
    
    # Optimize shared_buffers based on memory usage
    if (( $(echo "$cpu_usage < 50" | bc -l) )) && [[ "$shared_buffers" == "256MB" ]]; then
        log "Increasing shared_buffers for better performance"
        psql -h localhost -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
            "ALTER SYSTEM SET shared_buffers = '512MB'; SELECT pg_reload_conf();"
    fi
}

# Main capacity planning function
main() {
    local action="${1:-analyze}"
    
    case "$action" in
        "analyze")
            log "=== Starting Capacity Planning Analysis ==="
            
            get_current_metrics
            analyze_trends
            predict_capacity
            
            local scaling_action=$(check_scaling_triggers)
            local scaling_reason=$(cat /tmp/scaling_decision.json | jq -r '.scale_reason')
            
            execute_scaling "$scaling_action" "$scaling_reason"
            optimize_database
            generate_capacity_report
            
            log "=== Capacity Planning Analysis Complete ==="
            ;;
            
        "scale-up")
            execute_scaling "scale_up" "Manual scale up requested"
            ;;
            
        "scale-down")
            execute_scaling "scale_down" "Manual scale down requested"
            ;;
            
        "report")
            get_current_metrics
            analyze_trends
            predict_capacity
            generate_capacity_report
            ;;
            
        "optimize")
            get_current_metrics
            optimize_database
            ;;
            
        "daemon")
            # Run capacity planning daemon
            while true; do
                main analyze
                sleep 300  # Check every 5 minutes
            done
            ;;
            
        *)
            echo "Usage: $0 {analyze|scale-up|scale-down|report|optimize|daemon}"
            exit 1
            ;;
    esac
}

# Signal handlers
trap 'log "Capacity planner interrupted"; exit 1' INT TERM

# Create required directories
mkdir -p /tmp /var/log

# Ensure required tools are available
command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed. Aborting." >&2; exit 1; }
command -v bc >/dev/null 2>&1 || { echo "bc is required but not installed. Aborting." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required but not installed. Aborting." >&2; exit 1; }

# Run main function
main "$@"
