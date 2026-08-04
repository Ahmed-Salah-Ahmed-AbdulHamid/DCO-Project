# ==========================================================================
# variables.tf — Input Variables
# DCO Phase 2: Infrastructure Provisioning
# ==========================================================================

# --------------------------------------------------------------------------
# General
# --------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy all resources into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Short project identifier used in resource naming."
  type        = string
  default     = "dco"
}

# --------------------------------------------------------------------------
# S3
# --------------------------------------------------------------------------
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for processed image storage. Must be globally unique."
  type        = string
  default     = "dco-image-processing-bucket"
}

# --------------------------------------------------------------------------
# ECR
# --------------------------------------------------------------------------
variable "ecr_repository_name" {
  description = "Name of the ECR repository for the API Docker image."
  type        = string
  default     = "dco-image-processing-api"
}

# --------------------------------------------------------------------------
# EC2
# --------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type. Use t2.micro or t3.micro for Free Tier eligibility."
  type        = string
  default     = "t2.micro"
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Key Pair for SSH access. Leave empty to disable SSH key-based login."
  type        = string
  default     = ""
}

# --------------------------------------------------------------------------
# Networking
# --------------------------------------------------------------------------
variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the EC2 instance. Restrict to your IP in production."
  type        = string
  default     = "0.0.0.0/0"
}
