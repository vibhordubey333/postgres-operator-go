output "operator_namespace" {
  description = "Namespace where the operator is deployed."
  value       = kubernetes_namespace_v1.operator.metadata[0].name
}

output "operator_release_name" {
  description = "Helm release name for the operator."
  value       = helm_release.postgres_operator.name
}

output "operator_chart" {
  description = "Chart source used for the Helm release."
  value       = local.operator_chart
}

output "operator_image" {
  description = "Operator image deployed by Helm."
  value       = "${local.operator_image_repository}:${var.release_version}"
}
