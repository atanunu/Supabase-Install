#!/bin/bash
# setup.sh - Complete setup script for enhanced Supabase self-hosting
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Enhanced Supabase Self-Hosting Setup"
echo "========================================"
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "❌ This script should not be run as root."
    echo "   Run as a regular user with sudo privileges."
    exit 1
fi

# Create configuration from template
echo "📋 Setting up configuration..."
if [[ ! -f "$SCRIPT_DIR/config.env" ]]; then
    cp "$SCRIPT_DIR/config.env.example" "$SCRIPT_DIR/config.env"
    echo "✅ Configuration file created: config.env"
    echo "   Please review and customize the settings."
else
    echo "✅ Configuration file already exists"
fi

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x "$SCRIPT_DIR"/*.sh
echo "✅ Scripts are now executable"

# Run installation
echo ""
echo "🛠️  Starting installation process..."
if "$SCRIPT_DIR/install_supabase.sh"; then
    echo "✅ Installation completed successfully!"
else
    echo "❌ Installation failed. Check logs for details."
    exit 1
fi

# Setup notifications and cloud backup
echo ""
read -p "🔔 Do you want to setup notifications and cloud backup? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Running notification setup..."
    if "$SCRIPT_DIR/setup_notifications.sh"; then
        echo "✅ Notifications and cloud backup configured!"
    else
        echo "⚠️  Notification setup encountered issues. You can run it later with:"
        echo "   $SCRIPT_DIR/setup_notifications.sh"
    fi
fi

# Setup cron jobs (optional)
echo ""
read -p "📅 Do you want to setup automated backups and updates? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Setting up cron jobs..."
    echo "Please run the following command to install cron jobs:"
    echo "sudo crontab -e"
    echo ""
    echo "Then add the contents from: $SCRIPT_DIR/crontab"
    echo ""
fi

# Run initial health check
echo "🏥 Running initial health check..."
if "$SCRIPT_DIR/health_check.sh"; then
    echo "✅ All systems are healthy!"
else
    echo "⚠️  Some issues detected. Check the health report above."
fi

echo ""
echo "🎉 Setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Review configuration: $SCRIPT_DIR/config.env"
echo "2. Test notifications: $SCRIPT_DIR/notify.sh --test"
echo "3. Test cloud backup: $SCRIPT_DIR/cloud_backup.sh --test"
echo "4. Start Supabase: cd \$INSTALL_DIR/supabase/docker && docker compose up -d"
echo "5. Access dashboard: http://localhost:3000"
echo "6. Setup monitoring: $SCRIPT_DIR/health_check.sh"
echo "7. Run manual backup: $SCRIPT_DIR/backup_supabase.sh"
echo ""
echo "📖 Documentation: $SCRIPT_DIR/README.md"
echo "🔍 View logs: tail -f /var/log/supabase/install.log"
