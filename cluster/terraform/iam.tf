################################################################################
# IRSA roles for all application services + KEDA + ADOT + Dashboard
################################################################################

locals {
  # Services that need SQS access
  app_services = {
    auth       = { queue_key = "auth" }
    client     = { queue_key = "client" }
    tickets    = { queue_key = "tickets" }
    orders     = { queue_key = "orders_service" }
    payments   = { queue_key = "payments" }
    expiration = { queue_key = "expiration" }
  }
}

################################################################################
# IRSA — Application services (SQS read/write)
################################################################################

data "aws_iam_policy_document" "app_sqs_assume" {
  for_each = local.app_services

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${each.key}-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_sqs" {
  for_each           = local.app_services
  name               = "ticket-selling-${each.key}-sqs-role"
  assume_role_policy = data.aws_iam_policy_document.app_sqs_assume[each.key].json
}

resource "aws_iam_policy" "app_sqs" {
  for_each = local.app_services
  name     = "ticket-selling-${each.key}-sqs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.queues[each.value.queue_key].arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_sqs" {
  for_each   = local.app_services
  role       = aws_iam_role.app_sqs[each.key].name
  policy_arn = aws_iam_policy.app_sqs[each.key].arn
}

################################################################################
# IRSA — KEDA operator (query AMP + assume app service roles for SQS)
################################################################################

data "aws_iam_policy_document" "keda_operator_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:keda:keda-operator"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "keda_operator" {
  name               = "${var.cluster_name}-keda-operator-role"
  assume_role_policy = data.aws_iam_policy_document.keda_operator_assume.json
}

resource "aws_iam_policy" "keda_operator" {
  name = "${var.cluster_name}-keda-operator-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Query AMP metrics for Prometheus triggers
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.main.arn
      },
      # Assume app service roles to read their SQS queues
      {
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = [for r in aws_iam_role.app_sqs : r.arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "keda_operator" {
  role       = aws_iam_role.keda_operator.name
  policy_arn = aws_iam_policy.keda_operator.arn
}

# Allow each app service role to be assumed by KEDA operator
resource "aws_iam_role_policy" "app_sqs_trust_keda" {
  for_each = local.app_services
  name     = "allow-keda-assume"
  role     = aws_iam_role.app_sqs[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = ["sts:AssumeRole"]
        Principal = { AWS = aws_iam_role.keda_operator.arn }
      }
    ]
  })
}

################################################################################
# IRSA — ADOT collector (remote-write to AMP)
################################################################################

data "aws_iam_policy_document" "adot_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:adot:adot-collector"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "adot" {
  name               = "${var.cluster_name}-adot-role"
  assume_role_policy = data.aws_iam_policy_document.adot_assume.json
}

resource "aws_iam_policy" "adot" {
  name = "${var.cluster_name}-adot-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
        Resource = aws_prometheus_workspace.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "adot" {
  role       = aws_iam_role.adot.name
  policy_arn = aws_iam_policy.adot.arn
}

################################################################################
# IRSA — Dashboard service (read SQS + AMP query + read K8s via API server)
################################################################################

data "aws_iam_policy_document" "dashboard_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.namespace}:dashboard-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dashboard" {
  name               = "${var.cluster_name}-dashboard-role"
  assume_role_policy = data.aws_iam_policy_document.dashboard_assume.json
}

resource "aws_iam_policy" "dashboard" {
  name = "${var.cluster_name}-dashboard-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ListQueues"
        ]
        Resource = [for q in aws_sqs_queue.queues : q.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.main.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dashboard" {
  role       = aws_iam_role.dashboard.name
  policy_arn = aws_iam_policy.dashboard.arn
}
