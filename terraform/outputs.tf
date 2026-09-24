output "ecr_repository_url" {
  description = "URL of the ECR repository used for application images."
  value       = aws_ecr_repository.app.repository_url
}
