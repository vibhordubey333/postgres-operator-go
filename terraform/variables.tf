variable "cluster_name" {
  default = "pg-operator-prod"
  type    = string
}

variable "aws_region" {
  default = "us-east-1"
  type    = string
}

variable "environment" {
  default = "prod"
  type    = string
}

variable "allowed_cidrs" {
  description = "CIDRs for EKS API access — must be set explicitly (VPN/office IPs)"
  type        = list(string)
  # No default — must be supplied explicitly to avoid public EKS API exposure
}