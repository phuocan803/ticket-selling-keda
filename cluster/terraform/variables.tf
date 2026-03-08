variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "ticket-selling-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "ticket-selling"
}

variable "github_org" {
  description = "GitHub organization or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "vscode-aws-dev-environment-setup"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS node group"
  type        = string
  default     = "m5.large"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}

variable "redis_url" {
  description = "Redis/ElastiCache endpoint URL"
  type        = string
  sensitive   = true
}

variable "jwt_key" {
  description = "JWT signing key for all services"
  type        = string
  sensitive   = true
}

variable "stripe_key" {
  description = "Stripe API key"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default = {
    Project     = "ticket-selling"
    ManagedBy   = "terraform"
    Environment = "production"
  }
}
