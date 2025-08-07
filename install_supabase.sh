#!/bin/bash
# install_supabase.sh - Enhanced one-time setup script for Supabase self-hosting
# Created: $(date +%F)
# Author: Enhanced by GitHub Copilot

set -euo pipefail

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "⚠️  Config file not found. Using defaults..."
    INSTALL_DIR="/opt/supabase"
    LOG_DIR="/var/log/supabase"
    BACKUP_DIR="/var/backups/supabase"
fi

# Create log directory
sudo mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "❌ ERROR: $1"
    exit 1
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error_exit "This script should not be run as root. Run as a regular user with sudo privileges."
fi

# Check system requirements
check_requirements() {
    log "🔍 Checking system requirements..."
    
    # Check OS
    if ! command -v apt &> /dev/null; then
        error_exit "This script requires a Debian/Ubuntu system with apt package manager"
    fi
    
    # Check available disk space (minimum 10GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 10485760 ]]; then
        error_exit "Insufficient disk space. At least 10GB required."
    fi
    
    # Check memory (minimum 2GB)
    total_mem=$(free | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 2097152 ]]; then
        log "⚠️  Warning: Less than 2GB RAM detected. Supabase may run slowly."
    fi
    
    log "✅ System requirements check passed"
}

# Install Docker
install_docker() {
    log "🐳 Installing Docker..."
    
    if command -v docker &> /dev/null; then
        log "✅ Docker already installed"
        return 0
    fi
    
    # Remove old versions
    sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Update package index
    sudo apt update || error_exit "Failed to update package index"
    
    # Install prerequisites
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git || error_exit "Failed to install prerequisites"
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt update || error_exit "Failed to update package index after adding Docker repo"
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || error_exit "Failed to install Docker"
    
    # Add user to docker group
    sudo usermod -aG docker "$USER" || error_exit "Failed to add user to docker group"
    
    # Start and enable Docker
    sudo systemctl start docker || error_exit "Failed to start Docker"
    sudo systemctl enable docker || error_exit "Failed to enable Docker"
    
    log "✅ Docker installation completed"
}

# Setup Supabase
setup_supabase() {
    log "📦 Setting up Supabase..."
    
    # Create installation directory
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$USER" "$INSTALL_DIR"
    
    # Clone Supabase repository
    if [[ -d "$INSTALL_DIR/supabase" ]]; then
        log "📁 Supabase directory already exists, updating..."
        cd "$INSTALL_DIR/supabase"
        git pull origin master || error_exit "Failed to update Supabase repository"
    else
        log "📥 Cloning Supabase repository..."
        git clone https://github.com/supabase/supabase.git "$INSTALL_DIR/supabase" || error_exit "Failed to clone Supabase repository"
    fi
    
    cd "$INSTALL_DIR/supabase/docker" || error_exit "Failed to navigate to Supabase docker directory"
    
    # Setup environment file
    if [[ ! -f ".env" ]]; then
        log "⚙️  Setting up environment configuration..."
        cp .env.example .env || error_exit "Failed to copy environment file"
        
        # Generate secure passwords and secrets
        log "🔐 Generating secure credentials..."
        POSTGRES_PASSWORD=$(openssl rand -base64 32)
        JWT_SECRET=$(openssl rand -base64 64)
        ANON_KEY=$(openssl rand -base64 32)
        SERVICE_ROLE_KEY=$(openssl rand -base64 32)
        
        # Update .env file with generated values
        sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" .env
        sed -i "s/JWT_SECRET=.*/JWT_SECRET=${JWT_SECRET}/" .env
        sed -i "s/ANON_KEY=.*/ANON_KEY=${anon_key}/" .env
        sed -i "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}/" .env
        
        log "✅ Environment configuration completed"
        log "📝 Generated credentials saved to .env file"
    else
        log "✅ Environment file already exists"
    fi
}

# Create directories
create_directories() {
    log "📁 Creating necessary directories..."
    
    sudo mkdir -p "$BACKUP_DIR" "$LOG_DIR"
    sudo chown "$USER:$USER" "$BACKUP_DIR"
    
    log "✅ Directories created successfully"
}

# Create systemd service (optional)
create_service() {
    log "🔧 Creating systemd service..."
    
    cat > /tmp/supabase.service << EOF
[Unit]
Description=Supabase Self-Hosted
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR/supabase/docker
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF
    
    sudo mv /tmp/supabase.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable supabase.service
    
    log "✅ Systemd service created and enabled"
}

# Main installation process
main() {
    log "🚀 Starting Supabase installation..."
    log "📍 Installation directory: $INSTALL_DIR"
    log "📍 Backup directory: $BACKUP_DIR"
    log "📍 Log directory: $LOG_DIR"
    
    check_requirements
    install_docker
    setup_supabase
    create_directories
    create_service
    
    log "🎉 Installation completed successfully!"
    log ""
    log "📋 Next steps:"
    log "1. Review and customize the .env file: $INSTALL_DIR/supabase/docker/.env"
    log "2. Start Supabase: sudo systemctl start supabase"
    log "3. Check status: sudo systemctl status supabase"
    log "4. Access dashboard: http://localhost:3000"
    log "5. Setup automated backups with: ./backup_supabase.sh"
    log ""
    log "🔍 View logs: tail -f $LOG_FILE"
    
    echo ""
    echo "⚠️  IMPORTANT SECURITY NOTES:"
    echo "- Change default passwords in the .env file"
    echo "- Configure firewall rules for production use"
    echo "- Setup SSL/TLS certificates for external access"
    echo "- Review and secure all configuration files"
}

# Run main function
main "$@"
