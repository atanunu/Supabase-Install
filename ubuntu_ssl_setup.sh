#!/bin/bash

# 🚀 Quick SSL Setup for Ubuntu 24 LTS
# This script provides Ubuntu-specific SSL setup with optimized commands

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔐 SSL Setup for Supabase on Ubuntu 24 LTS${NC}"
echo

# Make the main script executable
chmod +x ./setup_ssl.sh

echo -e "${GREEN}Choose SSL setup type:${NC}"
echo "1. Self-signed certificates (Development/Testing)"
echo "2. Let's Encrypt certificates (Production)"
echo

read -p "Enter choice (1 or 2): " choice

case $choice in
    1)
        echo -e "${BLUE}Setting up self-signed certificates...${NC}"
        read -p "Enter domain name (default: localhost): " domain
        domain=${domain:-localhost}
        
        echo -e "${YELLOW}Installing required packages...${NC}"
        sudo apt update
        sudo apt install -y openssl
        
        echo -e "${BLUE}Generating certificates...${NC}"
        ./setup_ssl.sh --type self-signed --domain "$domain"
        ;;
    2)
        echo -e "${BLUE}Setting up Let's Encrypt certificates...${NC}"
        read -p "Enter your domain name: " domain
        read -p "Enter your email address: " email
        
        if [[ -z "$domain" || -z "$email" ]]; then
            echo -e "${YELLOW}Domain and email are required for Let's Encrypt${NC}"
            exit 1
        fi
        
        echo -e "${YELLOW}Installing required packages...${NC}"
        sudo apt update
        sudo apt install -y snapd
        sudo snap install core; sudo snap refresh core
        sudo snap install --classic certbot
        sudo ln -sf /snap/bin/certbot /usr/bin/certbot
        
        echo -e "${BLUE}Generating Let's Encrypt certificates...${NC}"
        sudo ./setup_ssl.sh --type letsencrypt --domain "$domain" --email "$email"
        ;;
    *)
        echo "Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo
echo -e "${GREEN}✅ SSL setup complete!${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. Start Supabase with SSL:"
echo "   sudo docker compose --profile production up -d"
echo
echo "2. Test your SSL setup:"
echo "   curl -k https://$domain/health"
echo
echo "3. View certificate info:"
echo "   openssl x509 -in ssl/nginx/certificate.crt -text -noout"
echo
if [[ $choice -eq 2 ]]; then
    echo "4. Check auto-renewal status:"
    echo "   sudo certbot renew --dry-run"
    echo
fi
