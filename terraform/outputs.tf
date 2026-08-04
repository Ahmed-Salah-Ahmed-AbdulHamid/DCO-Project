# ==========================================================================
# outputs.tf — Exported Values
# DCO Phase 2: Infrastructure Provisioning
# ==========================================================================

output "ec2_public_ip" {
  description = "Public IPv4 address of the DCO EC2 instance."
  value       = aws_instance.dco_server.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the DCO EC2 instance."
  value       = aws_instance.dco_server.public_dns
}

output "ecr_repository_url" {
  description = "Full URI of the ECR repository (used in docker push)."
  value       = aws_ecr_repository.dco_api.repository_url
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for processed images."
  value       = aws_s3_bucket.images.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket (useful for additional IAM policies)."
  value       = aws_s3_bucket.images.arn
}

output "ssh_command" {
  description = "Quick SSH command to connect to the instance."
  value       = var.key_pair_name != "" ? "ssh -i <your-key>.pem ubuntu@${aws_instance.dco_server.public_ip}" : "No key pair configured — SSH key-based login disabled."
}

output "app_url" {
  description = "URL to access the running FastAPI application."
  value       = "http://${aws_instance.dco_server.public_ip}"
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.dco_alb.dns_name
}
