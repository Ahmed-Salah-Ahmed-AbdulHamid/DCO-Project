# ==========================================================================
# outputs.tf — Exported Values
# DCO Phase 2/6: Infrastructure Provisioning
# ==========================================================================

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

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.dco_alb.dns_name
}

output "app_url" {
  description = "URL to access the running FastAPI application through the ALB."
  value       = "http://${aws_lb.dco_alb.dns_name}"
}
