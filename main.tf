# terraform-aws-eks
# Opinionated EKS module — see CLAUDE.md for design decisions

locals {
  cluster_name = "${var.app_name}-${var.environment}"

  default_tags = {
    ManagedBy   = "terraform"
    Application = var.app_name
    Environment = var.environment
  }
}
