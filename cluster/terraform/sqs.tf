################################################################################
# SQS Queues — 8 queues matching the original setup script
################################################################################

locals {
  queues = {
    auth              = "ticket-auth-queue"
    client            = "ticket-client-queue"
    tickets           = "ticket-tickets-queue"
    orders_service    = "ticket-orders-service-queue"
    orders_events     = "ticket-orders-queue"
    payments          = "ticket-payments-queue"
    expiration        = "ticket-expiration-queue"
    expiration_events = "ticket-expiration-events-queue"
  }
}

resource "aws_sqs_queue" "queues" {
  for_each = local.queues

  name                       = each.value
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400  # 1 day
  receive_wait_time_seconds  = 20     # long polling

  tags = {
    Name    = each.value
    Service = each.key
  }
}
