################################################################################
# Terraform outputs — consumed by GitHub Actions via terraform output -json
################################################################################

# EKS
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

# AMP
output "amp_workspace_id" {
  description = "AMP workspace ID"
  value       = aws_prometheus_workspace.main.id
}

output "amp_remote_write_endpoint" {
  description = "AMP remote-write endpoint for ADOT"
  value       = "${aws_prometheus_workspace.main.prometheus_endpoint}api/v1/remote_write"
}

output "amp_query_endpoint" {
  description = "AMP query endpoint for KEDA SigV4 proxy"
  value       = aws_prometheus_workspace.main.prometheus_endpoint
}

# AMG
output "amg_workspace_id" {
  description = "AMG workspace ID"
  value       = aws_grafana_workspace.main.id
}

output "amg_workspace_url" {
  description = "AMG workspace URL (HTTPS)"
  value       = "https://${aws_grafana_workspace.main.endpoint}"
}

# ECR
output "ecr_registry" {
  description = "ECR registry base URL"
  value       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_repositories" {
  description = "Map of service name → ECR repository URI"
  value       = { for k, v in aws_ecr_repository.services : k => v.repository_url }
}

# SQS Queue URLs
output "sqs_queue_urls" {
  description = "Map of queue key → SQS queue URL"
  value       = { for k, v in aws_sqs_queue.queues : k => v.url }
}

output "sqs_queue_arns" {
  description = "Map of queue key → SQS queue ARN"
  value       = { for k, v in aws_sqs_queue.queues : k => v.arn }
}

# IRSA Role ARNs
output "irsa_role_arns" {
  description = "Map of service name → IRSA IAM role ARN"
  value = merge(
    { for k, v in aws_iam_role.app_sqs : k => v.arn },
    {
      keda      = aws_iam_role.keda_operator.arn
      adot      = aws_iam_role.adot.arn
      dashboard = aws_iam_role.dashboard.arn
    }
  )
}

# GitHub Actions role ARN (bootstrap output — needed to set up backend)
output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC"
  value       = aws_iam_role.github_actions.arn
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = var.aws_account_id
}
