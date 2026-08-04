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

resource "aws_instance" "dco_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.dco_ec2_profile.name
  vpc_security_group_ids = [aws_security_group.dco_sg.id]

  # Attach the newly created key pair
  key_name = aws_key_pair.dco_key.key_name

  # 20 GB root volume (gp3 for better baseline IOPS)
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # Enable detailed CloudWatch monitoring (useful for Phase 3+)
  monitoring = true

  # --- User Data: Bootstrap Docker on first boot -------------------------
  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail

    # ====================================================================
    # DCO Bootstrap Script — Ubuntu 22.04 LTS
    # Installs Docker, AWS CLI, and prepares the instance to run
    # the containerised FastAPI application.
    # ====================================================================

    echo ">>> [1/6] Updating system packages..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

    echo ">>> [2/6] Installing prerequisites..."
    apt-get install -y \
      ca-certificates \
      curl \
      gnupg \
      lsb-release \
      unzip

    echo ">>> [3/6] Installing Docker (official repository)..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    echo ">>> [4/6] Starting and enabling Docker service..."
    systemctl start docker
    systemctl enable docker

    echo ">>> [5/6] Adding 'ubuntu' user to the docker group..."
    usermod -aG docker ubuntu

    echo ">>> [6/6] Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install --update
    rm -rf /tmp/awscliv2.zip /tmp/aws

    echo ">>> Bootstrap complete! Docker version:"
    docker --version
    echo ">>> AWS CLI version:"
    aws --version
  USERDATA

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-server"
  }
}