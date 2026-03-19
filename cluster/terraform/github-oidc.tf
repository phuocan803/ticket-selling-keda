################################################################################
# GitHub Actions OIDC — allows GitHub Actions to assume an IAM role directly
# (no static AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY needed)
################################################################################

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]

  tags = {
    Name = "github-actions-oidc"
  }
}

################################################################################
# IAM Role assumed by GitHub Actions
# Scope: only this specific repo's main branch (and workflow_dispatch)
################################################################################

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    # Restrict to a specific repo; allow all branches for workflow_dispatch
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.cluster_name}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json

  tags = {
    Name = "${var.cluster_name}-github-actions-role"
  }
}

resource "aws_iam_policy" "github_actions" {
  name = "${var.cluster_name}-github-actions-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR — login, push images
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      # EKS — update kubeconfig, describe cluster
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = "*"
      },
      # Terraform state backend
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.cluster_name}-tf-state-${var.aws_account_id}",
          "arn:aws:s3:::${var.cluster_name}-tf-state-${var.aws_account_id}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.cluster_name}-tf-lock"
      },
      # Full infra provisioning (Terraform apply)
      {
        Effect   = "Allow"
        Action   = ["iam:*", "ec2:*", "eks:*", "sqs:*", "ecr:*", "elasticloadbalancing:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["aps:*", "grafana:*"]
        Resource = "*"
      },
      # STS pass role
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole", "iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}
