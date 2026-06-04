output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA data."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN."
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_url" {
  description = "Production ECR repository URL for the operator image."
  value       = aws_ecr_repository.postgres_operator.repository_url
}

output "github_actions_release_role_arn" {
  description = "IAM role ARN to store in the GitHub Actions AWS_ROLE_TO_ASSUME secret."
  value       = aws_iam_role.github_actions_release.arn
}

output "github_actions_deploy_role_arn" {
  description = "IAM role ARN to store in the GitHub Actions AWS_DEPLOY_ROLE_TO_ASSUME secret."
  value       = aws_iam_role.github_actions_deploy.arn
}

output "aws_region" {
  description = "AWS region used by this stack."
  value       = var.aws_region
}
