# ==========================================================================
# eks.tf — Amazon EKS Cluster & Node Group
# ==========================================================================

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "filtered" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  supported_subnets = [
    for s in data.aws_subnet.filtered : s.id if s.availability_zone != "us-east-1e"
  ]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  vpc_id                   = data.aws_vpc.default.id
  subnet_ids               = local.supported_subnets

  # Grant cluster admin permissions to the Terraform runner (the current user)
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    github_actions = {
      kubernetes_groups = []
      principal_arn     = data.aws_iam_user.github_actions.arn

      policy_associations = {
        cluster_admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type       = "cluster"
          }
        }
      }
    }
  }

  # Managed Node Group
  eks_managed_node_groups = {
    dco_nodes = {
      # Instances configuration
      instance_types = ["t3.medium"] # Needed for Prometheus/Grafana memory requirements
      capacity_type  = "ON_DEMAND"

      # Scaling configuration as requested: max 5
      min_size     = 1
      max_size     = 5
      desired_size = 1

      # Attached IAM policies for the Node Group
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        AmazonS3FullAccess           = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        ClusterAutoscaler            = aws_iam_policy.cluster_autoscaler.arn
      }
    }
  }

  tags = {
    Environment = "dev"
    Project     = "DCO"
  }
}
