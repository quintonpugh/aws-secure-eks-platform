variable "aws_region" {
  description = "AWS region used for the EKS platform."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name used when creating project resources."
  type        = string
  default     = "secure-eks"
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC."
  type        = string
  default     = "10.30.0.0/16"
}
