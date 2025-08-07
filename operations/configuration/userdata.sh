#!/bin/bash
# User Data Script for EC2 Instances
# Configures Supabase environment on instance launch

set -euo pipefail

# Variables from Terraform
ENVIRONMENT="${environment}"
DB_HOST="${db_host}"
REDIS_HOST="${redis_host}"

# Logging
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting Supabase instance configuration for environment: $ENVIRONMENT"

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y \
    docker.io \
    docker-compose \
    awscli \
    postgresql-client \
    redis-tools \
    nginx \
    certbot \
    python3-certbot-nginx \
    htop \
    curl \
    wget \
    git \
    jq \
    unzip

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Docker Compose v2
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create application directory
mkdir -p /opt/supabase
chown ubuntu:ubuntu /opt/supabase

# Clone Supabase configuration
cd /opt/supabase
git clone https://github.com/your-org/supabase-config.git .
chown -R ubuntu:ubuntu /opt/supabase

# Create environment configuration
cat > /opt/supabase/.env << EOF
# Environment: $ENVIRONMENT
POSTGRES_HOST=$DB_HOST
REDIS_HOST=$REDIS_HOST

# Retrieve other secrets from AWS Secrets Manager
# (These will be populated by the deployment script)
POSTGRES_PASSWORD=
JWT_SECRET=
ANON_KEY=
SERVICE_ROLE_KEY=
EOF

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf awscliv2.zip aws

# Configure CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/supabase",
                        "log_stream_name": "{instance_id}/user-data"
                    },
                    {
                        "file_path": "/opt/supabase/logs/*.log",
                        "log_group_name": "/aws/ec2/supabase",
                        "log_stream_name": "{instance_id}/application"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Supabase/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "diskio": {
                "measurement": ["io_time"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": ["tcp_established", "tcp_time_wait"],
                "metrics_collection_interval": 60
            },
            "swap": {
                "measurement": ["swap_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl start amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent

# Configure log rotation
cat > /etc/logrotate.d/supabase << 'EOF'
/opt/supabase/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 ubuntu ubuntu
}
EOF

# Install Node.js (for health checks and utilities)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Create health check script
cat > /opt/supabase/health_check.sh << 'EOF'
#!/bin/bash
# Health check script for Supabase services

HEALTH_ENDPOINT="http://localhost:8000/health"
MAX_RETRIES=5
RETRY_INTERVAL=10

for i in $(seq 1 $MAX_RETRIES); do
    if curl -f $HEALTH_ENDPOINT > /dev/null 2>&1; then
        echo "Health check passed"
        exit 0
    fi
    
    echo "Health check attempt $i failed, retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

echo "Health check failed after $MAX_RETRIES attempts"
exit 1
EOF

chmod +x /opt/supabase/health_check.sh

# Create service startup script
cat > /opt/supabase/start_services.sh << 'EOF'
#!/bin/bash
# Start Supabase services

cd /opt/supabase

# Fetch secrets from AWS Secrets Manager
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
DB_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "supabase-db-password-${ENVIRONMENT}" --region $REGION --query 'SecretString' --output text)

# Update environment file
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$DB_PASSWORD/" .env

# Start services
docker-compose --profile production up -d

# Wait for services to be ready
sleep 30

# Run health check
./health_check.sh
EOF

chmod +x /opt/supabase/start_services.sh

# Create systemd service for Supabase
cat > /etc/systemd/system/supabase.service << 'EOF'
[Unit]
Description=Supabase Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/supabase
ExecStart=/opt/supabase/start_services.sh
ExecStop=/usr/local/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF

# Enable and start Supabase service
systemctl daemon-reload
systemctl enable supabase

# Configure nginx as reverse proxy
cat > /etc/nginx/sites-available/supabase << 'EOF'
upstream supabase_backend {
    server 127.0.0.1:8000;
}

server {
    listen 80;
    server_name _;
    
    # Health check endpoint
    location /health {
        proxy_pass http://supabase_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Main application
    location / {
        proxy_pass http://supabase_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable nginx site
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx configuration
nginx -t && systemctl restart nginx

# Install monitoring agents
# Install node_exporter for Prometheus
wget https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-*linux-amd64.tar.gz
tar xvfz node_exporter-*linux-amd64.tar.gz
mv node_exporter-*linux-amd64/node_exporter /usr/local/bin/
rm -rf node_exporter-*

# Create node_exporter service
cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=nobody
Group=nobody
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Configure automatic security updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# Enable automatic updates
systemctl enable unattended-upgrades

# Create backup directories
mkdir -p /opt/supabase/backups
mkdir -p /opt/supabase/logs
chown -R ubuntu:ubuntu /opt/supabase

# Set up log forwarding to CloudWatch
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Signal that user data script is complete
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} || true

echo "Supabase instance configuration completed successfully"

# Start Supabase services
systemctl start supabase

echo "User data script completed at $(date)"
