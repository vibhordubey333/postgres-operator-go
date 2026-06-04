variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "pg-operator-prod"
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.31"
}

variable "aws_region" {
  description = "AWS region for all regional resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "prod"
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Use VPN/office/current admin IPs, never 0.0.0.0/0 for production."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "IAM principal ARNs that receive cluster-admin access through EKS access entries."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for the EKS VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones used by the VPC and EKS node groups."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs for EKS nodes and internal load balancers."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs for NAT gateways and internet-facing load balancers."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "control_plane_log_retention_days" {
  description = "CloudWatch retention for EKS control-plane logs."
  type        = number
  default     = 90
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the EKS secrets-encryption KMS key."
  type        = number
  default     = 30
}

variable "system_node_instance_types" {
  description = "Instance types for the general system node group."
  type        = list(string)
  default     = ["m5.large"]
}

variable "system_node_min_size" {
  description = "Minimum size for the system node group."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "Maximum size for the system node group."
  type        = number
  default     = 4
}

variable "system_node_desired_size" {
  description = "Desired size for the system node group."
  type        = number
  default     = 3
}

variable "postgres_node_instance_types" {
  description = "Instance types for the PostgreSQL workload node group."
  type        = list(string)
  default     = ["r6g.xlarge"]
}

variable "postgres_node_min_size" {
  description = "Minimum size for the PostgreSQL node group."
  type        = number
  default     = 1
}

variable "postgres_node_max_size" {
  description = "Maximum size for the PostgreSQL node group."
  type        = number
  default     = 10
}

variable "postgres_node_desired_size" {
  description = "Desired size for the PostgreSQL node group."
  type        = number
  default     = 2
}

variable "ecr_repository_name" {
  description = "ECR repository used for production operator images."
  type        = string
  default     = "postgres-operator-go"
}

variable "ecr_images_to_keep" {
  description = "Number of tagged ECR images retained by lifecycle policy."
  type        = number
  default     = 20
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the release role, in owner/name form."
  type        = string
  default     = "vibhordubey333/postgres-operator-go"
}

variable "github_actions_deploy_environment" {
  description = "GitHub Environment name allowed to assume the deploy role."
  type        = string
  default     = "production"
}

variable "terraform_state_bucket_name" {
  description = "S3 bucket that stores Terraform remote state. Used to scope the GitHub Actions deploy role to the operator state object."
  type        = string
}

variable "operator_state_key" {
  description = "S3 object key for the operator Terraform state."
  type        = string
  default     = "postgres-operator-go/operator/terraform.tfstate"
}

variable "tags" {
  description = "Additional tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
