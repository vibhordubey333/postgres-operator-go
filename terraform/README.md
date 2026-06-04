# Terraform Deployment

This directory contains two Terraform root modules:

- `infra`: AWS foundation for production EKS, including VPC, EKS, EBS CSI, EKS access entries, KMS-backed secret encryption, and the production ECR repository.
- `operator`: Kubernetes namespace and Helm release for `postgres-operator-go`.

The states are intentionally split. Create or update the cluster with `infra` first, then let the release workflow deploy the operator with `operator`. This avoids coupling Kubernetes/Helm provider lifecycle to cluster creation and makes release upgrades a small Terraform change.

## Backend Configuration

Copy each backend example and replace it with your real state bucket details:

```sh
cp terraform/infra/backend.example.hcl terraform/infra/backend.hcl
cp terraform/operator/backend.example.hcl terraform/operator/backend.hcl
```

Initialize each root with its backend file:

```sh
terraform -chdir=terraform/infra init -backend-config=backend.hcl -reconfigure
terraform -chdir=terraform/operator init -backend-config=backend.hcl -reconfigure
```

## Deploy Infra

Create an infra tfvars file from the example and set your admin principal ARNs, API allowlist CIDRs, and Terraform state bucket name:

```sh
cp terraform/infra/terraform.tfvars.example terraform/infra/terraform.tfvars
terraform -chdir=terraform/infra plan
terraform -chdir=terraform/infra apply
```

The infra root creates an immutable ECR repository named `postgres-operator-go`, a GitHub Actions OIDC role scoped to release tags, and a separate deploy role scoped to the `production` GitHub Environment. After apply, copy the role outputs into GitHub Actions secrets:

```sh
terraform -chdir=terraform/infra output github_actions_release_role_arn
terraform -chdir=terraform/infra output github_actions_deploy_role_arn
```

Use these GitHub settings:

- Secret `AWS_ROLE_TO_ASSUME`: value from `github_actions_release_role_arn`
- Secret `AWS_DEPLOY_ROLE_TO_ASSUME`: value from `github_actions_deploy_role_arn`
- Variable `TF_STATE_BUCKET`: the S3 bucket used by both Terraform backends

## Deploy Operator Automatically

After the infra bootstrap and GitHub settings are complete, push a release tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow publishes the image and chart, then the `deploy-eks` job runs the `operator` Terraform root with:

```text
TF_VAR_release_version=<tag>
TF_VAR_operator_chart=https://github.com/vibhordubey333/postgres-operator-go/releases/download/<tag>/postgres-operator-go-<tag>.tgz
```

Because the selected free path uses GitHub-hosted runners, the EKS public API endpoint must be reachable from those runners. For stricter production networking, move deployment to CodeBuild in the VPC or to a private self-hosted runner.

For manual recovery or one-off redeploys, run:

```sh
export TF_VAR_release_version=v0.1.0

terraform -chdir=terraform/operator plan
terraform -chdir=terraform/operator apply
```

By default, the operator image repository is:

```text
<account-id>.dkr.ecr.<region>.amazonaws.com/postgres-operator-go
```

Override `operator_image_repository` only when deploying from another registry. Set `manage_operator_crds=false` if the `PostgresDatabase` CRD already exists outside the Helm release. Set `enable_service_monitor=true` only after Prometheus Operator CRDs are installed.

## Verify

```sh
aws eks update-kubeconfig --region us-east-1 --name pg-operator-prod
kubectl rollout status deployment/postgres-operator-postgres-operator-go -n postgres-operator-system
kubectl get pods -n postgres-operator-system
kubectl get crd postgresdatabases.postgres.vibhordubey.com
kubectl get storageclass gp3
```

Future operator upgrades happen by pushing a new release tag. Manual recovery should change only `release_version` and be applied through the `operator` Terraform root.
