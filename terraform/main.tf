# ==========================================================================
# main.tf — Core Infrastructure Resources
# DCO Phase 2: Infrastructure Provisioning
#
# Resources created:
#   1. S3 Bucket (private, force_destroy)
#   2. ECR Repository
#   3. IAM Role + Instance Profile (ECR pull + S3 put)
#   4. Security Group (SSH + HTTP in, all out)
#   5. EC2 Instance (Ubuntu 22.04 LTS, Docker bootstrap)
# ==========================================================================

# --------------------------------------------------------------------------
# Data Sources
# --------------------------------------------------------------------------

# Fetch the latest Ubuntu 22.04 LTS AMI from Canonical
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

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Current AWS account ID (used in ECR ARN)
data "aws_caller_identity" "current" {}

# Default VPC — used for the security group and EC2 instance
data "aws_vpc" "default" {
  default = true
}

# Current AWS region (used in ECR pull and CloudWatch dashboard)
data "aws_region" "current" {}

# ==========================================================================
# 1. S3 BUCKET
# ==========================================================================
resource "aws_s3_bucket" "images" {
  bucket        = var.s3_bucket_name
  force_destroy = true # Easy cleanup during project testing

  tags = {
    Name = "${var.project_name}-images"
  }
}

# Block all public access — the app uploads via IAM role, not public URLs
resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption (AES-256) by default
resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning for safety (optional but good practice)
resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ==========================================================================
# 2. ECR REPOSITORY
# ==========================================================================
resource "aws_ecr_repository" "dco_api" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true # Easy cleanup during project testing

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-api-repo"
  }
}

# Lifecycle policy — keep only the 5 most recent images to save storage costs
resource "aws_ecr_lifecycle_policy" "dco_api" {
  repository = aws_ecr_repository.dco_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 5 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ==========================================================================
# 3. IAM ROLE + INSTANCE PROFILE
# ==========================================================================

# Trust policy — allows EC2 to assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dco_ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# --- Policy: Pull images from ECR ----------------------------------------
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.dco_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# --- Policy: Put objects into the S3 bucket ------------------------------
data "aws_iam_policy_document" "s3_put_objects" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.images.arn,
      "${aws_s3_bucket.images.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "s3_put_objects" {
  name        = "${var.project_name}-s3-put-policy"
  description = "Allow the DCO EC2 instance to upload processed images to S3."
  policy      = data.aws_iam_policy_document.s3_put_objects.json
}

resource "aws_iam_role_policy_attachment" "s3_put" {
  role       = aws_iam_role.dco_ec2_role.name
  policy_arn = aws_iam_policy.s3_put_objects.arn
}

# --- Policy: CloudWatch Agent (push metrics & logs) ----------------------
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.dco_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# --- Instance Profile (bridges IAM Role → EC2) --------------------------
resource "aws_iam_instance_profile" "dco_ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.dco_ec2_role.name
}

# ==========================================================================
# 4. SECURITY GROUP
# ==========================================================================
resource "aws_security_group" "dco_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow SSH (22) and HTTP (80) inbound, all outbound."
  vpc_id      = data.aws_vpc.default.id

  # --- Ingress: SSH -------------------------------------------------------
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # --- Ingress: HTTP ------------------------------------------------------
  ingress {
    description = "HTTP access (FastAPI via Nginx/Docker)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- Ingress: FastAPI dev port (optional, useful during dev) ------------
  ingress {
    description = "FastAPI direct access (dev/testing)"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- Egress: All --------------------------------------------------------
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

# ==========================================================================
# 5. EC2 INSTANCE & KEY PAIR
# ==========================================================================

resource "aws_key_pair" "dco_key" {
  key_name   = "dco-key"
  public_key = file("dco-key.pub")
}

resource "aws_launch_template" "dco_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.dco_key.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.dco_ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.dco_sg.id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  monitoring {
    enabled = true
  }

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    echo ">>> [1/7] Updating system packages..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

    echo ">>> [2/7] Installing prerequisites..."
    apt-get install -y ca-certificates curl gnupg lsb-release unzip jq

    echo ">>> [3/7] Installing Docker (official repository)..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io

    systemctl start docker
    systemctl enable docker
    usermod -aG docker ubuntu

    echo ">>> [4/7] Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --update
    rm -rf /tmp/awscliv2.zip /tmp/aws

    echo ">>> [5/7] Authenticating with ECR..."
    export AWS_DEFAULT_REGION=${data.aws_region.current.name}
    ECR_REGISTRY="${data.aws_caller_identity.current.account_id}.dkr.ecr.$${AWS_DEFAULT_REGION}.amazonaws.com"
    aws ecr get-login-password --region $${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin $${ECR_REGISTRY}

    echo ">>> [6/7] Pulling latest Docker image..."
    ECR_IMAGE="$${ECR_REGISTRY}/${var.ecr_repository_name}:latest"
    # Try to pull up to 3 times in case ECR image doesn't exist yet
    for i in 1 2 3; do docker pull $${ECR_IMAGE} && break || sleep 10; done

    echo ">>> [7/7] Running the container..."
    docker run -d \
      --name dco-api \
      --restart unless-stopped \
      -p 80:8000 \
      -e AWS_REGION=$${AWS_DEFAULT_REGION} \
      -e S3_BUCKET_NAME=${var.s3_bucket_name} \
      $${ECR_IMAGE}

    echo ">>> Bootstrap complete!"
  USERDATA
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-server"
    }
  }
}

resource "aws_autoscaling_group" "dco_asg" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.dco_tg.arn]
  
  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.dco_lt.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "dco_cpu_policy" {
  name                   = "${var.project_name}-cpu-policy"
  autoscaling_group_name = aws_autoscaling_group.dco_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

# ==========================================================================
# 6. APPLICATION LOAD BALANCER (ALB)
# ==========================================================================

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "dco_alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP access from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_lb" "dco_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.dco_alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "dco_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_listener" "dco_listener" {
  load_balancer_arn = aws_lb.dco_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dco_tg.arn
  }
}

# ==========================================================================
# 7. SNS ALERTS & CLOUDWATCH DASHBOARD
# ==========================================================================

resource "aws_sns_topic" "dco_alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "dco_email_alert" {
  topic_arn = aws_sns_topic.dco_alerts.arn
  protocol  = "email"
  endpoint  = "eng.ahmedsalah.j@gmail.com"
}

resource "aws_autoscaling_notification" "dco_asg_notifications" {
  group_names = [aws_autoscaling_group.dco_asg.name]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
  ]

  topic_arn = aws_sns_topic.dco_alerts.arn
}

resource "aws_cloudwatch_dashboard" "dco_dashboard" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.dco_asg.name]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ASG Average CPU Utilization"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.dco_alb.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Total Requests"
        }
      }
    ]
  })
}