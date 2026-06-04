### Terraform configuration for postgres-operator-go infrastructure ###
terraform {
  required_version = ">= 1.7"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    helm = { source = "hashicorp/helm", version = "~> 2.12" }
  }
  backend "s3" {
    bucket       = "your-org-tf-state"
    key          = "postgres-operator-go/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" { region = var.aws_region }

## VPC ──────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.2"

  name                 = "${var.cluster_name}-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = false # HA: one NAT per AZ
  enable_dns_hostnames = true
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

## EKS ──────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  cluster_endpoint_public_access           = true
  cluster_endpoint_public_access_cidrs     = var.allowed_cidrs
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 4
      desired_size   = 3
      disk_size      = 50
      labels         = { role = "system" }
    }
    postgres = {
      instance_types = ["r6g.xlarge"] # memory-optimised for PG
      min_size       = 1
      max_size       = 10
      desired_size   = 2
      disk_size      = 100
      labels         = { role = "postgres" }
      taints         = [{ key = "dedicated", value = "postgres", effect = "NoSchedule" }]
    }
  }

  tags = local.tags
}

## IAM/IRSA ──────────────────────────────────────────────────────
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

## ECR ──────────────────────────────────────────────────────────
resource "aws_ecr_repository" "pg_operator" {
  name                 = "postgres-operator-go"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "pg_operator" {
  repository = aws_ecr_repository.pg_operator.name
  policy = jsonencode({ rules = [{
    rulePriority = 1
    description  = "Keep last 20 images"
    selection    = { tagStatus = "tagged", countType = "imageCountMoreThan", countNumber = 20 }
    action       = { type = "expire" }
  }] })
}

locals {
  tags = { Project = "postgres-operator-go", ManagedBy = "terraform", Environment = var.environment }
}