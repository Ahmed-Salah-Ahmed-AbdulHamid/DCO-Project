data "aws_iam_user" "github_actions" {
  user_name = "finalproject"
}

resource "aws_iam_user_policy" "github_actions_eks" {
  name = "github-actions-eks-access"
  user = data.aws_iam_user.github_actions.user_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
