provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-secure-eks-platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
