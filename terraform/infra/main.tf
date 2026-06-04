terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  tags = merge(
    {
      Project     = "postgres-operator-go"
      ManagedBy   = "terraform"
      Environment = var.environment
    },
    var.tags,
  )

  cluster_admin_policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  admin_access_entries = {
    for index, principal_arn in var.admin_principal_arns :
    "admin-${index}" => {
      kubernetes_groups = []
      principal_arn     = principal_arn

      policy_associations = {
        cluster-admin = {
          policy_arn = local.cluster_admin_policy_arn
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  github_actions_deploy_access_entry = {
    github-actions-deploy = {
      kubernetes_groups = []
      principal_arn     = aws_iam_role.github_actions_deploy.arn

      policy_associations = {
        cluster-admin = {
          policy_arn = local.cluster_admin_policy_arn
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_access_entries = merge(
    local.admin_access_entries,
    local.github_actions_deploy_access_entry,
  )

  terraform_state_bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket_name}"

  operator_state_object_arns = [
    "${local.terraform_state_bucket_arn}/${var.operator_state_key}",
    "${local.terraform_state_bucket_arn}/${var.operator_state_key}.tflock",
  ]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.2"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  authentication_mode = "API"
  access_entries      = local.eks_access_entries

  enable_cluster_creator_admin_permissions = false

  cluster_endpoint_private_access        = true
  cluster_endpoint_public_access         = true
  cluster_endpoint_public_access_cidrs   = var.allowed_cidrs
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.control_plane_log_retention_days

  cluster_encryption_config = {
    resources = ["secrets"]
  }

  kms_key_deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_kms_key_rotation         = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    system = {
      instance_types = var.system_node_instance_types
      min_size       = var.system_node_min_size
      max_size       = var.system_node_max_size
      desired_size   = var.system_node_desired_size
      disk_size      = 50
      labels         = { role = "system" }
    }

    postgres = {
      instance_types = var.postgres_node_instance_types
      min_size       = var.postgres_node_min_size
      max_size       = var.postgres_node_max_size
      desired_size   = var.postgres_node_desired_size
      disk_size      = 100
      labels         = { role = "postgres" }
      taints = [
        {
          key    = "dedicated"
          value  = "postgres"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  tags = local.tags
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

resource "aws_ecr_repository" "postgres_operator" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "postgres_operator" {
  repository = aws_ecr_repository.postgres_operator.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last ${var.ecr_images_to_keep} tagged images"
        selection = {
          tagStatus   = "tagged"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_images_to_keep
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    data.tls_certificate.github_actions.certificates[0].sha1_fingerprint,
  ]

  tags = local.tags
}

data "aws_iam_policy_document" "github_actions_release_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.github_actions.arn,
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/tags/v*"]
    }
  }
}

resource "aws_iam_role" "github_actions_release" {
  name               = "${var.cluster_name}-github-release"
  assume_role_policy = data.aws_iam_policy_document.github_actions_release_assume_role.json
}

data "aws_iam_policy_document" "github_actions_deploy_assume_role" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.github_actions.arn,
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.github_actions_deploy_environment}"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "${var.cluster_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_deploy_assume_role.json
}

data "aws_iam_policy_document" "github_actions_release_ecr" {
  statement {
    sid    = "EcrLogin"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "PushOperatorImages"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]

    resources = [
      aws_ecr_repository.postgres_operator.arn,
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_release_ecr" {
  name   = "ecr-publish"
  role   = aws_iam_role.github_actions_release.id
  policy = data.aws_iam_policy_document.github_actions_release_ecr.json
}

data "aws_iam_policy_document" "github_actions_deploy" {
  statement {
    sid    = "ReadEksCluster"
    effect = "Allow"

    actions = [
      "eks:DescribeCluster",
    ]

    resources = [
      module.eks.cluster_arn,
    ]
  }

  statement {
    sid    = "ListOperatorTerraformState"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
    ]

    resources = [
      local.terraform_state_bucket_arn,
    ]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        var.operator_state_key,
        "${var.operator_state_key}.tflock",
      ]
    }
  }

  statement {
    sid    = "ReadWriteOperatorTerraformState"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = local.operator_state_object_arns
  }

  statement {
    sid    = "DeleteOperatorTerraformLock"
    effect = "Allow"

    actions = [
      "s3:DeleteObject",
    ]

    resources = [
      "${local.terraform_state_bucket_arn}/${var.operator_state_key}.tflock",
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name   = "operator-terraform-deploy"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.github_actions_deploy.json
}
