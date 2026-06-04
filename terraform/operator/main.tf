terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

locals {
  operator_chart = coalesce(
    var.operator_chart,
    abspath("${path.module}/../../deploy/helm/postgres-operator-go"),
  )

  operator_image_repository = coalesce(
    var.operator_image_repository,
    "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_repository_name}",
  )

  service_account_annotations = var.operator_irsa_role_arn == null ? null : {
    "eks.amazonaws.com/role-arn" = var.operator_irsa_role_arn
  }

  helm_values = {
    replicaCount = var.operator_replica_count

    image = {
      repository = local.operator_image_repository
      tag        = var.release_version
      pullPolicy = var.operator_image_pull_policy
    }

    imagePullSecrets = var.image_pull_secrets

    env = {
      DATABASE_SSLMODE = var.database_sslmode
    }

    installCRDs = var.manage_operator_crds

    metrics = {
      serviceMonitor = {
        enabled = var.enable_service_monitor
      }
    }

    serviceAccount = {
      annotations = local.service_account_annotations
    }
  }
}

resource "kubernetes_namespace_v1" "operator" {
  metadata {
    name = var.operator_namespace

    labels = {
      "app.kubernetes.io/name"       = "postgres-operator-go"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "postgres_operator" {
  name      = var.operator_release_name
  namespace = kubernetes_namespace_v1.operator.metadata[0].name
  chart     = local.operator_chart

  atomic          = true
  cleanup_on_fail = true
  lint            = true
  max_history     = 10
  timeout         = var.helm_timeout_seconds
  wait            = true

  values = [
    yamlencode(local.helm_values),
  ]

  depends_on = [
    kubernetes_namespace_v1.operator,
  ]
}
