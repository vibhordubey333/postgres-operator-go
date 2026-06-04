variable "cluster_name" {
  description = "Name of the target EKS cluster."
  type        = string
  default     = "pg-operator-prod"
}

variable "aws_region" {
  description = "AWS region for the target EKS cluster."
  type        = string
  default     = "us-east-1"
}

variable "release_version" {
  description = "Immutable release version to deploy, e.g. v0.1.0. Must match an image tag published by the release pipeline."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.release_version))
    error_message = "release_version must look like a semantic Git tag, for example v0.1.0."
  }
}

variable "operator_chart" {
  description = "Helm chart source. Defaults to the local chart path; may be set to an immutable GitHub Release .tgz URL."
  type        = string
  default     = null
}

variable "operator_release_name" {
  description = "Helm release name for the operator."
  type        = string
  default     = "postgres-operator"
}

variable "operator_namespace" {
  description = "Kubernetes namespace for the operator."
  type        = string
  default     = "postgres-operator-system"
}

variable "operator_image_repository" {
  description = "Operator image repository. Defaults to the production ECR repository in the current AWS account and region."
  type        = string
  default     = null
}

variable "ecr_repository_name" {
  description = "ECR repository name used when operator_image_repository is not provided."
  type        = string
  default     = "postgres-operator-go"
}

variable "operator_image_pull_policy" {
  description = "Kubernetes image pull policy for the operator."
  type        = string
  default     = "IfNotPresent"
}

variable "image_pull_secrets" {
  description = "Optional Kubernetes image pull secrets for private registries, e.g. [{ name = \"ghcr-credentials\" }]. ECR usually does not need this on EKS nodes."
  type = list(object({
    name = string
  }))
  default = []
}

variable "operator_replica_count" {
  description = "Number of operator replicas."
  type        = number
  default     = 2
}

variable "manage_operator_crds" {
  description = "Whether the Helm release should install and manage the PostgresDatabase CRD. Set false if the CRD already exists outside Helm."
  type        = bool
  default     = true
}

variable "enable_service_monitor" {
  description = "Create a ServiceMonitor. Requires Prometheus Operator CRDs to already exist."
  type        = bool
  default     = false
}

variable "operator_irsa_role_arn" {
  description = "Optional IAM role ARN for the operator service account. Leave null until the operator needs AWS API access."
  type        = string
  default     = null
}

variable "database_sslmode" {
  description = "DATABASE_SSLMODE passed to the operator."
  type        = string
  default     = "require"
}

variable "helm_timeout_seconds" {
  description = "Timeout for Helm install/upgrade operations."
  type        = number
  default     = 600
}
