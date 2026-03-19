################################################################################
# AMG — Amazon Managed Grafana workspace
################################################################################

resource "aws_grafana_workspace" "main" {
  name                     = "${var.cluster_name}-amg"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.amg.arn

  data_sources = ["PROMETHEUS", "CLOUDWATCH", "XRAY"]

  tags = {
    Name = "${var.cluster_name}-amg"
  }
}

################################################################################
# IAM role for AMG to access AMP
################################################################################

data "aws_iam_policy_document" "amg_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:grafana:${var.aws_region}:${var.aws_account_id}:/workspaces/*"]
    }
  }
}

resource "aws_iam_role" "amg" {
  name               = "${var.cluster_name}-amg-role"
  assume_role_policy = data.aws_iam_policy_document.amg_assume.json
}

resource "aws_iam_policy" "amg" {
  name = "${var.cluster_name}-amg-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata",
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace"
        ]
        Resource = aws_prometheus_workspace.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "amg" {
  role       = aws_iam_role.amg.name
  policy_arn = aws_iam_policy.amg.arn
}
