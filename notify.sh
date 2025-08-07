#!/bin/bash
# notify.sh - Comprehensive notification system for Supabase monitoring
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️  Config file not found. Notifications disabled."
    exit 1
fi

# Check if notifications are enabled
if [[ "${NOTIFICATION_ENABLED:-false}" != "true" ]]; then
    exit 0
fi

# Function to send email notification
send_email() {
    local subject="$1"
    local message="$2"
    local priority="${3:-normal}"
    
    if [[ "${EMAIL_ENABLED:-false}" != "true" ]]; then
        return 0
    fi
    
    if [[ -z "${SMTP_SERVER:-}" || -z "${SMTP_FROM:-}" || -z "${SMTP_TO:-}" ]]; then
        echo "⚠️  Email configuration incomplete"
        return 1
    fi
    
    # Create email content
    local email_content
    email_content=$(cat << EOF
Subject: $subject
From: $SMTP_FROM
To: $SMTP_TO
Date: $(date -R)
Priority: $priority

$message

---
Sent from Supabase Monitor
Server: $(hostname)
Time: $(date)
EOF
)
    
    # Send email using different methods
    if command -v sendmail >/dev/null 2>&1; then
        echo "$email_content" | sendmail "$SMTP_TO"
    elif command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$subject" "$SMTP_TO"
    elif command -v msmtp >/dev/null 2>&1; then
        echo "$email_content" | msmtp "$SMTP_TO"
    elif command -v curl >/dev/null 2>&1; then
        # Use curl for SMTP
        local auth_flag=""
        if [[ -n "${SMTP_USERNAME:-}" && -n "${SMTP_PASSWORD:-}" ]]; then
            auth_flag="--user ${SMTP_USERNAME}:${SMTP_PASSWORD}"
        fi
        
        local tls_flag=""
        if [[ "${SMTP_USE_TLS:-true}" == "true" ]]; then
            tls_flag="--ssl-reqd"
        fi
        
        echo "$email_content" | curl --silent \
            --url "smtps://${SMTP_SERVER}:${SMTP_PORT}" \
            $auth_flag \
            $tls_flag \
            --mail-from "$SMTP_FROM" \
            --mail-rcpt "$SMTP_TO" \
            --upload-file -
    else
        echo "⚠️  No email client available"
        return 1
    fi
}

# Function to send Slack notification
send_slack() {
    local message="$1"
    local status="${2:-INFO}"
    local color="${3:-#36a64f}"
    
    if [[ "${SLACK_ENABLED:-false}" != "true" || -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        return 0
    fi
    
    # Set color based on status
    case "$status" in
        "SUCCESS") color="#36a64f" ;;
        "WARNING") color="#ff9500" ;;
        "ERROR"|"FAILED") color="#ff0000" ;;
        "INFO") color="#0099cc" ;;
    esac
    
    local payload
    payload=$(cat << EOF
{
    "channel": "${SLACK_CHANNEL:-#alerts}",
    "username": "${SLACK_USERNAME:-Supabase Monitor}",
    "icon_emoji": ":computer:",
    "attachments": [
        {
            "color": "$color",
            "title": "Supabase Alert - $status",
            "text": "$message",
            "fields": [
                {
                    "title": "Server",
                    "value": "$(hostname)",
                    "short": true
                },
                {
                    "title": "Time",
                    "value": "$(date)",
                    "short": true
                }
            ],
            "footer": "Supabase Monitor",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" >/dev/null 2>&1
}

# Function to send Telegram notification
send_telegram() {
    local message="$1"
    local status="${2:-INFO}"
    
    if [[ "${TELEGRAM_ENABLED:-false}" != "true" || -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        return 0
    fi
    
    # Add status emoji
    local emoji=""
    case "$status" in
        "SUCCESS") emoji="✅" ;;
        "WARNING") emoji="⚠️" ;;
        "ERROR"|"FAILED") emoji="❌" ;;
        "INFO") emoji="ℹ️" ;;
    esac
    
    local formatted_message
    formatted_message=$(cat << EOF
$emoji *Supabase Alert - $status*

$message

🖥️ Server: \`$(hostname)\`
🕐 Time: \`$(date)\`
EOF
)
    
    curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$formatted_message" \
        -d parse_mode="Markdown" >/dev/null 2>&1
}

# Function to send Discord notification
send_discord() {
    local message="$1"
    local status="${2:-INFO}"
    
    if [[ "${DISCORD_ENABLED:-false}" != "true" || -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
        return 0
    fi
    
    # Set color based on status
    local color=3447003  # Blue
    case "$status" in
        "SUCCESS") color=3066993 ;;  # Green
        "WARNING") color=16776960 ;; # Yellow
        "ERROR"|"FAILED") color=15158332 ;; # Red
    esac
    
    local payload
    payload=$(cat << EOF
{
    "embeds": [
        {
            "title": "Supabase Alert - $status",
            "description": "$message",
            "color": $color,
            "fields": [
                {
                    "name": "Server",
                    "value": "$(hostname)",
                    "inline": true
                },
                {
                    "name": "Time",
                    "value": "$(date)",
                    "inline": true
                }
            ],
            "footer": {
                "text": "Supabase Monitor"
            },
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
        }
    ]
}
EOF
)
    
    curl -H "Content-Type: application/json" \
        -X POST \
        -d "$payload" \
        "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1
}

# Function to send Microsoft Teams notification
send_teams() {
    local message="$1"
    local status="${2:-INFO}"
    
    if [[ "${TEAMS_ENABLED:-false}" != "true" || -z "${TEAMS_WEBHOOK_URL:-}" ]]; then
        return 0
    fi
    
    # Set theme color based on status
    local theme_color="0078D4"  # Blue
    case "$status" in
        "SUCCESS") theme_color="107C10" ;;  # Green
        "WARNING") theme_color="FF8C00" ;;  # Orange
        "ERROR"|"FAILED") theme_color="D13438" ;; # Red
    esac
    
    local payload
    payload=$(cat << EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "$theme_color",
    "summary": "Supabase Alert - $status",
    "sections": [
        {
            "activityTitle": "Supabase Alert - $status",
            "activitySubtitle": "$(hostname)",
            "activityImage": "https://supabase.com/favicon.ico",
            "facts": [
                {
                    "name": "Status",
                    "value": "$status"
                },
                {
                    "name": "Server",
                    "value": "$(hostname)"
                },
                {
                    "name": "Time",
                    "value": "$(date)"
                }
            ],
            "text": "$message"
        }
    ]
}
EOF
)
    
    curl -H "Content-Type: application/json" \
        -X POST \
        -d "$payload" \
        "$TEAMS_WEBHOOK_URL" >/dev/null 2>&1
}

# Main notification function
send_notification() {
    local title="$1"
    local message="$2"
    local status="${3:-INFO}"
    
    # Log notification
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending notification: $title ($status)"
    
    # Send to all enabled channels
    send_email "$title" "$message" "$status" &
    send_slack "$message" "$status" &
    send_telegram "$message" "$status" &
    send_discord "$message" "$status" &
    send_teams "$message" "$status" &
    
    # Wait for all notifications to complete
    wait
    
    echo "✅ Notifications sent"
}

# Test notification function
test_notifications() {
    echo "🧪 Testing notification channels..."
    
    local test_message="This is a test notification from Supabase Monitor. If you receive this, your notification setup is working correctly!"
    
    echo "Sending test notifications..."
    send_notification "Supabase Monitor Test" "$test_message" "INFO"
    
    echo "✅ Test notifications sent to all enabled channels"
}

# Show usage if no arguments
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <title> <message> [status]"
    echo ""
    echo "Arguments:"
    echo "  title    - Notification title"
    echo "  message  - Notification message"
    echo "  status   - Status level (INFO, SUCCESS, WARNING, ERROR) [default: INFO]"
    echo ""
    echo "Options:"
    echo "  --test   - Send test notifications to all enabled channels"
    echo "  --help   - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 'Backup Failed' 'Database backup failed at 2:00 AM' ERROR"
    echo "  $0 'Update Complete' 'Supabase updated successfully' SUCCESS"
    echo "  $0 --test"
    exit 0
fi

# Handle special arguments
case "${1:-}" in
    "--test")
        test_notifications
        exit 0
        ;;
    "--help"|"-h")
        exec "$0"
        ;;
    *)
        # Normal notification
        if [[ $# -lt 2 ]]; then
            echo "❌ Error: Title and message are required"
            exec "$0"
        fi
        
        send_notification "$1" "$2" "${3:-INFO}"
        ;;
esac
