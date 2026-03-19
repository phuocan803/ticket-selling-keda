################################################################################
# AMP — Amazon Managed Prometheus workspace
################################################################################

resource "aws_prometheus_workspace" "main" {
  alias = "${var.cluster_name}-amp"

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }

  tags = {
    Name = "${var.cluster_name}-amp"
  }
}

resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/prometheus/${var.cluster_name}"
  retention_in_days = 30
}
