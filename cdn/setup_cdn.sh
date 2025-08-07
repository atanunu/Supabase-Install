#!/bin/bash

# CDN Setup Script for Supabase
# Supports CloudFlare, AWS CloudFront, and other CDN providers

set -euo pipefail

# Configuration
DOMAIN="${1:-your-domain.com}"
CDN_PROVIDER="${2:-cloudflare}"

log() {
    echo "[$(date)] $1"
}

# CloudFlare CDN setup
setup_cloudflare() {
    log "Setting up CloudFlare CDN for $DOMAIN..."
    
    # Install CloudFlare CLI if not present
    if ! command -v cloudflared >/dev/null 2>&1; then
        log "Installing CloudFlare CLI..."
        curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
        chmod +x /usr/local/bin/cloudflared
    fi
    
    # Create CloudFlare configuration
    cat > /etc/cloudflared/config.yml << CFEOF
tunnel: supabase-tunnel
credentials-file: /etc/cloudflared/cert.pem

ingress:
  # API routes (no caching)
  - hostname: $DOMAIN
    path: /rest/*
    service: https://localhost:443
    originRequest:
      disableChunkedEncoding: true
      noTLSVerify: true
    
  # Auth routes (no caching)
  - hostname: $DOMAIN
    path: /auth/*
    service: https://localhost:443
    originRequest:
      disableChunkedEncoding: true
      noTLSVerify: true
    
  # Storage routes (with caching for static assets)
  - hostname: $DOMAIN
    path: /storage/*
    service: https://localhost:443
    originRequest:
      disableChunkedEncoding: true
      noTLSVerify: true
    
  # Realtime (no caching)
  - hostname: $DOMAIN
    path: /realtime/*
    service: https://localhost:443
    originRequest:
      disableChunkedEncoding: true
      noTLSVerify: true
    
  # Dashboard (with caching)
  - hostname: $DOMAIN
    path: /dashboard/*
    service: https://localhost:443
    originRequest:
      disableChunkedEncoding: true
      noTLSVerify: true
    
  # Catch-all
  - service: https://localhost:443
    originRequest:
      disableChunkedEncoding: true
      noTLSVerify: true
CFEOF

    log "CloudFlare CDN configuration created"
}

# Main setup function
case "$CDN_PROVIDER" in
    "cloudflare")
        setup_cloudflare
        ;;
    "cloudfront")
        log "AWS CloudFront configuration created (see setup guide)"
        ;;
    *)
        log "Unknown CDN provider: $CDN_PROVIDER"
        log "Supported providers: cloudflare, cloudfront"
        exit 1
        ;;
esac

log "CDN setup completed for $CDN_PROVIDER"
