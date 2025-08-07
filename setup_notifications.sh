#!/bin/bash
# setup_notifications.sh - Interactive setup for notifications and cloud backup
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

echo "🔔 Supabase Notifications & Cloud Backup Setup"
echo "=============================================="
echo ""

# Create config file if it doesn't exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    cp "${SCRIPT_DIR}/config.env.example" "$CONFIG_FILE"
    echo "✅ Created configuration file: $CONFIG_FILE"
fi

# Function to update config value
update_config() {
    local key="$1"
    local value="$2"
    
    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

# Function to get current config value
get_config() {
    local key="$1"
    grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2- || echo ""
}

# Setup notifications
setup_notifications() {
    echo "📧 Setting up notifications..."
    echo ""
    
    read -p "Enable notifications? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_config "NOTIFICATION_ENABLED" "true"
        
        # Email setup
        echo ""
        read -p "Setup email notifications? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_config "EMAIL_ENABLED" "true"
            
            read -p "SMTP server (e.g., smtp.gmail.com): " smtp_server
            update_config "SMTP_SERVER" "$smtp_server"
            
            read -p "SMTP port (usually 587): " smtp_port
            update_config "SMTP_PORT" "$smtp_port"
            
            read -p "SMTP username: " smtp_user
            update_config "SMTP_USERNAME" "$smtp_user"
            
            read -s -p "SMTP password: " smtp_pass
            echo
            update_config "SMTP_PASSWORD" "$smtp_pass"
            
            read -p "From email address: " smtp_from
            update_config "SMTP_FROM" "$smtp_from"
            
            read -p "To email address: " smtp_to
            update_config "SMTP_TO" "$smtp_to"
            
            echo "✅ Email configuration saved"
        fi
        
        # Slack setup
        echo ""
        read -p "Setup Slack notifications? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_config "SLACK_ENABLED" "true"
            
            echo "To setup Slack notifications:"
            echo "1. Go to https://api.slack.com/messaging/webhooks"
            echo "2. Create a new webhook for your workspace"
            echo "3. Copy the webhook URL"
            echo ""
            
            read -p "Slack webhook URL: " slack_webhook
            update_config "SLACK_WEBHOOK_URL" "$slack_webhook"
            
            read -p "Slack channel (e.g., #alerts): " slack_channel
            update_config "SLACK_CHANNEL" "$slack_channel"
            
            echo "✅ Slack configuration saved"
        fi
        
        # Telegram setup
        echo ""
        read -p "Setup Telegram notifications? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_config "TELEGRAM_ENABLED" "true"
            
            echo "To setup Telegram notifications:"
            echo "1. Create a bot by messaging @BotFather on Telegram"
            echo "2. Get your bot token"
            echo "3. Get your chat ID by messaging @userinfobot"
            echo ""
            
            read -p "Telegram bot token: " telegram_token
            update_config "TELEGRAM_BOT_TOKEN" "$telegram_token"
            
            read -p "Telegram chat ID: " telegram_chat
            update_config "TELEGRAM_CHAT_ID" "$telegram_chat"
            
            echo "✅ Telegram configuration saved"
        fi
        
        # Discord setup
        echo ""
        read -p "Setup Discord notifications? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_config "DISCORD_ENABLED" "true"
            
            echo "To setup Discord notifications:"
            echo "1. Go to your Discord server settings"
            echo "2. Go to Integrations > Webhooks"
            echo "3. Create a new webhook and copy the URL"
            echo ""
            
            read -p "Discord webhook URL: " discord_webhook
            update_config "DISCORD_WEBHOOK_URL" "$discord_webhook"
            
            echo "✅ Discord configuration saved"
        fi
        
    else
        update_config "NOTIFICATION_ENABLED" "false"
    fi
}

# Setup cloud backup
setup_cloud_backup() {
    echo ""
    echo "☁️  Setting up cloud backup..."
    echo ""
    
    read -p "Enable cloud backup? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_config "CLOUD_BACKUP_ENABLED" "true"
        
        echo "Choose cloud provider:"
        echo "1) rclone (supports OneDrive, Dropbox, Google Drive, etc.)"
        echo "2) AWS S3"
        echo "3) Hetzner Object Storage (S3-compatible)"
        echo "4) Hetzner Storage Box (SFTP)"
        echo "5) Google Cloud Storage"
        echo "6) Azure Blob Storage"
        echo "7) Multi-cloud (backup to multiple providers)"
        
        read -p "Enter choice (1-7): " -n 1 -r provider_choice
        echo
        
        case $provider_choice in
            1)
                update_config "CLOUD_PROVIDER" "rclone"
                
                echo ""
                echo "To setup rclone:"
                echo "1. Install rclone: curl https://rclone.org/install.sh | sudo bash"
                echo "2. Configure a remote: rclone config"
                echo "3. Follow the interactive setup for your cloud provider"
                echo ""
                
                read -p "rclone remote name: " rclone_remote
                update_config "RCLONE_REMOTE_NAME" "$rclone_remote"
                
                read -p "rclone remote path (e.g., supabase-backups): " rclone_path
                update_config "RCLONE_REMOTE_PATH" "$rclone_path"
                
                echo "✅ rclone configuration saved"
                echo "Don't forget to run: rclone config"
                ;;
            2)
                update_config "CLOUD_PROVIDER" "aws"
                
                read -p "AWS S3 bucket name: " s3_bucket
                update_config "AWS_S3_BUCKET" "$s3_bucket"
                
                read -p "AWS region (e.g., us-east-1): " aws_region
                update_config "AWS_REGION" "$aws_region"
                
                echo "✅ AWS S3 configuration saved"
                echo "Don't forget to run: aws configure"
                ;;
            3)
                update_config "CLOUD_PROVIDER" "hetzner"
                
                echo ""
                echo "Hetzner Object Storage Setup:"
                echo "1. Login to Hetzner Cloud Console"
                echo "2. Go to Object Storage and create a bucket"
                echo "3. Generate access credentials"
                echo ""
                
                read -p "Hetzner S3 bucket name: " hetzner_bucket
                update_config "HETZNER_S3_BUCKET" "$hetzner_bucket"
                
                read -p "Hetzner S3 endpoint (e.g., https://fsn1.your-objectstorage.com): " hetzner_endpoint
                update_config "HETZNER_S3_ENDPOINT" "$hetzner_endpoint"
                
                read -p "Hetzner S3 region (e.g., fsn1): " hetzner_region
                update_config "HETZNER_S3_REGION" "$hetzner_region"
                
                read -p "Hetzner access key: " hetzner_access_key
                update_config "HETZNER_ACCESS_KEY" "$hetzner_access_key"
                
                read -s -p "Hetzner secret key: " hetzner_secret_key
                echo
                update_config "HETZNER_SECRET_KEY" "$hetzner_secret_key"
                
                echo "✅ Hetzner Object Storage configuration saved"
                ;;
            4)
                update_config "CLOUD_PROVIDER" "hetzner-sftp"
                
                echo ""
                echo "Hetzner Storage Box Setup:"
                echo "1. Login to Hetzner Robot Console"
                echo "2. Order a Storage Box or use existing one"
                echo "3. Note your Storage Box credentials"
                echo ""
                
                read -p "Storage Box hostname (e.g., your-backup.your-storagebox.de): " hetzner_host
                update_config "HETZNER_STORAGEBOX_HOST" "$hetzner_host"
                
                read -p "Storage Box username: " hetzner_user
                update_config "HETZNER_STORAGEBOX_USER" "$hetzner_user"
                
                read -s -p "Storage Box password: " hetzner_pass
                echo
                update_config "HETZNER_STORAGEBOX_PASS" "$hetzner_pass"
                
                read -p "Storage path (e.g., /backups/supabase): " hetzner_path
                update_config "HETZNER_STORAGEBOX_PATH" "$hetzner_path"
                
                echo "✅ Hetzner Storage Box configuration saved"
                ;;
            5)
                update_config "CLOUD_PROVIDER" "gcp"
                
                read -p "Google Cloud Storage bucket name: " gcp_bucket
                update_config "GCP_BUCKET" "$gcp_bucket"
                
                echo "✅ Google Cloud Storage configuration saved"
                echo "Don't forget to install and configure Google Cloud SDK"
                ;;
            6)
                update_config "CLOUD_PROVIDER" "azure"
                
                read -p "Azure Storage container name: " azure_container
                update_config "AZURE_CONTAINER" "$azure_container"
                
                echo "✅ Azure Blob Storage configuration saved"
                echo "Don't forget to install and configure Azure CLI"
                ;;
            7)
                update_config "MULTI_CLOUD_ENABLED" "true"
                
                echo ""
                echo "Multi-cloud backup setup:"
                echo "Available providers: aws, hetzner, hetzner-sftp, onedrive, dropbox, googledrive"
                echo "Example: aws,onedrive,hetzner"
                echo ""
                
                read -p "Enter providers (comma-separated): " multi_providers
                update_config "MULTI_CLOUD_PROVIDERS" "$multi_providers"
                
                echo ""
                echo "⚠️  You'll need to configure each provider separately:"
                
                if [[ "$multi_providers" == *"aws"* ]]; then
                    echo "- Configure AWS: aws configure"
                fi
                
                if [[ "$multi_providers" == *"hetzner"* ]]; then
                    echo "- Configure Hetzner Object Storage credentials in config.env"
                fi
                
                if [[ "$multi_providers" == *"onedrive"* || "$multi_providers" == *"dropbox"* || "$multi_providers" == *"googledrive"* ]]; then
                    echo "- Configure rclone remotes: rclone config"
                fi
                
                echo "✅ Multi-cloud configuration saved"
                ;;
            *)
                echo "Invalid choice. Skipping cloud backup setup."
                update_config "CLOUD_BACKUP_ENABLED" "false"
                ;;
        esac
    else
        update_config "CLOUD_BACKUP_ENABLED" "false"
    fi
}

# Test notifications
test_notifications() {
    echo ""
    echo "🧪 Testing notifications..."
    
    if [[ -f "${SCRIPT_DIR}/notify.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/notify.sh"
        "${SCRIPT_DIR}/notify.sh" --test
    else
        echo "❌ notify.sh script not found"
    fi
}

# Test cloud backup
test_cloud_backup() {
    echo ""
    echo "🧪 Testing cloud backup connectivity..."
    
    if [[ -f "${SCRIPT_DIR}/cloud_backup.sh" ]]; then
        chmod +x "${SCRIPT_DIR}/cloud_backup.sh"
        "${SCRIPT_DIR}/cloud_backup.sh" --test
    else
        echo "❌ cloud_backup.sh script not found"
    fi
}

# Main setup flow
main() {
    setup_notifications
    setup_cloud_backup
    
    echo ""
    echo "✅ Configuration completed!"
    echo ""
    echo "Configuration saved to: $CONFIG_FILE"
    echo ""
    
    read -p "Test notifications now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_notifications
    fi
    
    if [[ "$(get_config "CLOUD_BACKUP_ENABLED")" == "true" ]]; then
        echo ""
        read -p "Test cloud backup connectivity? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            test_cloud_backup
        fi
    fi
    
    echo ""
    echo "🎉 Setup complete!"
    echo ""
    echo "Next steps:"
    echo "1. Review configuration: $CONFIG_FILE"
    echo "2. Test backup: ./backup_supabase.sh"
    echo "3. Setup cron jobs for automation"
    echo ""
    echo "For more help, see: ./README.md"
}

# Show current configuration
show_config() {
    echo "Current configuration:"
    echo "====================="
    echo ""
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Notifications enabled: $(get_config "NOTIFICATION_ENABLED")"
        echo "Email enabled: $(get_config "EMAIL_ENABLED")"
        echo "Slack enabled: $(get_config "SLACK_ENABLED")"
        echo "Telegram enabled: $(get_config "TELEGRAM_ENABLED")"
        echo "Discord enabled: $(get_config "DISCORD_ENABLED")"
        echo ""
        echo "Cloud backup enabled: $(get_config "CLOUD_BACKUP_ENABLED")"
        echo "Cloud provider: $(get_config "CLOUD_PROVIDER")"
        echo ""
    else
        echo "No configuration file found."
        echo "Run without arguments to start setup."
    fi
}

# Handle command line arguments
case "${1:-}" in
    "--show-config"|"-s")
        show_config
        exit 0
        ;;
    "--test-notifications")
        test_notifications
        exit 0
        ;;
    "--test-cloud")
        test_cloud_backup
        exit 0
        ;;
    "--help"|"-h")
        echo "Usage: $0 [options]"
        echo ""
        echo "Interactive setup for notifications and cloud backup"
        echo ""
        echo "Options:"
        echo "  -s, --show-config         Show current configuration"
        echo "  --test-notifications      Test notification systems"
        echo "  --test-cloud             Test cloud backup connectivity"
        echo "  -h, --help               Show this help message"
        exit 0
        ;;
    "")
        # Interactive setup
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
