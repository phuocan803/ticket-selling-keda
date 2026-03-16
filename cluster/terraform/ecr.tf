################################################################################
# ECR Repositories — one per service + dashboard
################################################################################

locals {
  services = ["auth", "client", "tickets", "orders", "payments", "expiration", "dashboard"]
}

resource "aws_ecr_repository" "services" {
  for_each             = toset(local.services)
  name                 = "ticket-selling-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "ticket-selling-${each.key}"
  }
}

# Lifecycle policy — keep last 10 images per repo
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
