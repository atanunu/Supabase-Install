#!/bin/bash
# Production Deployment Checklist
# Execute these steps to move from development to production

set -euo pipefail

echo "🚀 Supabase Production Deployment Checklist"
echo "==========================================="

# Phase 1: Environment Configuration
echo "📋 Phase 1: Environment Configuration"
echo "1. Configure production environment variables"
echo "   - Copy .env.production.example to .env.production"
echo "   - Update with your production values"
echo "   - Validate configuration: supabase-validate-config"

echo ""
echo "2. Domain and DNS setup"
echo "   - Point your domain to server IP"
echo "   - Configure DNS A records"
echo "   - Set up CNAME for subdomains (if needed)"

echo ""
echo "3. SSL certificate setup"
echo "   - Run: ./ubuntu_ssl_setup.sh your-domain.com"
echo "   - Verify SSL: openssl s_client -connect your-domain.com:443"

# Phase 2: Infrastructure Deployment
echo ""
echo "📋 Phase 2: Infrastructure Deployment (Optional - for AWS)"
echo "1. Configure Terraform variables"
echo "   - Edit terraform/terraform.tfvars"
echo "   - Set AWS credentials and region"
echo "   - Configure instance types and scaling"

echo ""
echo "2. Deploy AWS infrastructure"
echo "   - cd terraform && ./init.sh"
echo "   - terraform plan -var-file='terraform.tfvars'"
echo "   - terraform apply -var-file='terraform.tfvars'"

# Phase 3: CI/CD Setup
echo ""
echo "📋 Phase 3: CI/CD Setup (Optional - for automated deployments)"
echo "1. Configure GitHub repository secrets:"
echo "   - AWS_ACCESS_KEY_ID"
echo "   - AWS_SECRET_ACCESS_KEY"
echo "   - DOCKER_REGISTRY_TOKEN"
echo "   - SLACK_WEBHOOK_URL (for notifications)"

echo ""
echo "2. Test deployment pipeline"
echo "   - Push to staging branch first"
echo "   - Verify automated deployment works"
echo "   - Test rollback procedures"

# Phase 4: Production Deployment
echo ""
echo "📋 Phase 4: Production Deployment"
echo "1. Deploy operations framework"
echo "   - ./deploy_operations.sh deploy"
echo "   - Verify: ./deploy_operations.sh status"

echo ""
echo "2. Deploy to production"
echo "   - supabase-deploy --strategy blue-green --environment production"
echo "   - Monitor deployment health"
echo "   - Verify all services operational"

# Phase 5: Monitoring and Validation
echo ""
echo "📋 Phase 5: Monitoring and Validation"
echo "1. Verify monitoring stack"
echo "   - Grafana: http://your-domain.com:3000"
echo "   - Prometheus: http://your-domain.com:9090"
echo "   - Check all dashboards loading"

echo ""
echo "2. Test backup system"
echo "   - Verify backups running: docker logs supabase_backup_manager"
echo "   - Test restore procedure"
echo "   - Validate cross-region sync"

echo ""
echo "3. Security validation"
echo "   - Run security scan: ./security_scan.sh"
echo "   - Verify SSL grade: https://www.ssllabs.com/ssltest/"
echo "   - Check firewall rules"

# Phase 6: Go Live
echo ""
echo "📋 Phase 6: Go Live"
echo "1. Update DNS to production"
echo "2. Monitor system health"
echo "3. Test user registration and API endpoints"
echo "4. Monitor logs and metrics"

echo ""
echo "🎉 Production deployment complete!"
echo "📊 Monitor: Grafana dashboard"
echo "📋 Documentation: /opt/supabase/runbooks/"
echo "🚨 Support: Check logs in /var/log/"
