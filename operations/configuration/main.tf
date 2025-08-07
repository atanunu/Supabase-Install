# Terraform Configuration for Supabase Infrastructure
# Enterprise-grade infrastructure as code

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
  
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "supabase/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "min_capacity" {
  description = "Minimum number of instances"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN"
  type        = string
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name        = "supabase-vpc-${var.environment}"
    Environment = var.environment
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name        = "supabase-igw-${var.environment}"
    Environment = var.environment
  }
}

# Subnets
resource "aws_subnet" "public" {
  count = length(var.availability_zones)
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name        = "supabase-public-${var.availability_zones[count.index]}-${var.environment}"
    Environment = var.environment
    Type        = "public"
  }
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name        = "supabase-private-${var.availability_zones[count.index]}-${var.environment}"
    Environment = var.environment
    Type        = "private"
  }
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = {
    Name        = "supabase-public-rt-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  count = length(var.availability_zones)
  
  domain = "vpc"
  
  tags = {
    Name        = "supabase-nat-eip-${count.index + 1}-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)
  
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = {
    Name        = "supabase-nat-${count.index + 1}-${var.environment}"
    Environment = var.environment
  }
  
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  count = length(var.availability_zones)
  
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  
  tags = {
    Name        = "supabase-private-rt-${count.index + 1}-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups
resource "aws_security_group" "alb" {
  name        = "supabase-alb-${var.environment}"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name        = "supabase-alb-sg-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_security_group" "app" {
  name        = "supabase-app-${var.environment}"
  description = "Security group for Supabase application instances"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name        = "supabase-app-sg-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_security_group" "rds" {
  name        = "supabase-rds-${var.environment}"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  
  tags = {
    Name        = "supabase-rds-sg-${var.environment}"
    Environment = var.environment
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "supabase-db-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
  
  tags = {
    Name        = "supabase-db-subnet-group-${var.environment}"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "postgres" {
  identifier = "supabase-postgres-${var.environment}"
  
  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.medium"
  
  allocated_storage     = 100
  max_allocated_storage = 1000
  storage_type          = "gp3"
  storage_encrypted     = true
  
  db_name  = "supabase"
  username = "supabase"
  password = random_password.db_password.result
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  backup_retention_period   = 30
  backup_window            = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade = true
  
  skip_final_snapshot = false
  final_snapshot_identifier = "supabase-postgres-${var.environment}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  
  tags = {
    Name        = "supabase-postgres-${var.environment}"
    Environment = var.environment
  }
}

# Random password for database
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store database password in Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "supabase-db-password-${var.environment}"
  description             = "Database password for Supabase ${var.environment}"
  recovery_window_in_days = 30
  
  tags = {
    Name        = "supabase-db-password-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

# IAM Role for RDS monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "supabase-rds-monitoring-${var.environment}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name        = "supabase-rds-monitoring-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ElastiCache for Redis
resource "aws_elasticache_subnet_group" "main" {
  name       = "supabase-cache-subnet-${var.environment}"
  subnet_ids = aws_subnet.private[*].id
  
  tags = {
    Name        = "supabase-cache-subnet-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_security_group" "redis" {
  name        = "supabase-redis-${var.environment}"
  description = "Security group for Redis"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
  
  tags = {
    Name        = "supabase-redis-sg-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "supabase-redis-${var.environment}"
  description                = "Redis for Supabase ${var.environment}"
  
  node_type                  = "cache.t3.micro"
  port                       = 6379
  parameter_group_name       = "default.redis7"
  
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  subnet_group_name = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  
  tags = {
    Name        = "supabase-redis-${var.environment}"
    Environment = var.environment
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "supabase-alb-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  
  enable_deletion_protection = true
  
  tags = {
    Name        = "supabase-alb-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "app" {
  name     = "supabase-tg-${var.environment}"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }
  
  tags = {
    Name        = "supabase-tg-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Launch Template
resource "aws_launch_template" "app" {
  name_prefix   = "supabase-${var.environment}-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  
  vpc_security_group_ids = [aws_security_group.app.id]
  
  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    environment = var.environment
    db_host     = aws_db_instance.postgres.endpoint
    redis_host  = aws_elasticache_replication_group.redis.primary_endpoint_address
  }))
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "supabase-instance-${var.environment}"
      Environment = var.environment
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "supabase-asg-${var.environment}"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300
  
  min_size         = var.min_capacity
  max_size         = var.max_capacity
  desired_capacity = var.min_capacity
  
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  
  tag {
    key                 = "Name"
    value               = "supabase-asg-${var.environment}"
    propagate_at_launch = false
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "supabase-scale-up-${var.environment}"
  scaling_adjustment     = 2
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "supabase-scale-down-${var.environment}"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "supabase-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  
  tags = {
    Name        = "supabase-cpu-high-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "supabase-cpu-low-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  
  tags = {
    Name        = "supabase-cpu-low-${var.environment}"
    Environment = var.environment
  }
}

# S3 Buckets for backups
resource "aws_s3_bucket" "backups" {
  bucket = "supabase-backups-${var.environment}-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name        = "supabase-backups-${var.environment}"
    Environment = var.environment
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "backups" {
  bucket = aws_s3_bucket.backups.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  
  rule {
    id     = "backup_lifecycle"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
    
    expiration {
      days = 2555  # 7 years
    }
  }
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  sensitive   = true
}

output "load_balancer_dns" {
  description = "Load balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "backup_bucket" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.backups.bucket
}
