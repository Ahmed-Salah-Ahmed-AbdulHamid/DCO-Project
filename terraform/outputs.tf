output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "ecr_repository_url" {
  description = "ECR Repository URL for Docker images"
  value       = aws_ecr_repository.dco_api.repository_url
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for images"
  value       = aws_s3_bucket.images.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket created for images"
  value       = aws_s3_bucket.images.arn
}
