# postgres-operator-go

[![CI](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/ci.yml/badge.svg)](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/vibhordubey333/postgres-operator-go)](https://github.com/vibhordubey333/postgres-operator-go/releases)

**postgres-operator-go** is a lightweight, Go-based Kubernetes operator designed to automate the deployment, scaling, and lifecycle management of PostgreSQL instances within a Kubernetes cluster. By defining a declarative `PostgresDatabase` Custom Resource (CR), developers can easily provision self-healing PostgreSQL databases along with their corresponding Kubernetes StatefulSets, headless Services, and connection Secrets.

## Description

Running stateful databases in Kubernetes can be challenging. This operator solves that by implementing operational best practices directly in Go using the `controller-runtime` and `Kubebuilder` frameworks. It continuously reconciles the desired state of a `PostgresDatabase` resource with the live cluster resources.

### Architecture & Key Features

*   **Automated Resource Provisioning**: Automatically generates and reconciles a `StatefulSet` running PostgreSQL, a headless `Service` for network routing, and a `Secret` containing generated database credentials (including the `DATABASE_URL`).
*   **Flexible Configuration**: Configure database versions, replica counts (1-5), storage specs (size and StorageClass), and resource CPU/memory requests and limits directly via the Custom Resource Spec.
*   **Secure Connection Management**: Supports environment-controlled database SSL modes (e.g., `require` or `disable`) when configuring connection strings, protecting data in transit.
*   **Production Infrastructure Ready**: Includes production-grade Terraform configurations to spin up a fully-configured AWS EKS cluster, complete with private subnets, ECR repository, EBS CSI drivers, and dedicated memory-optimized node pools specifically tuned and tainted for running PostgreSQL workloads.
*   **Status & Health Monitoring**: Provides real-time phase updates (`Provisioning`, `Ready`, `Failed`, `Deleting`) and detailed status conditions directly on the Custom Resource.

## Database SSL Mode

The operator configures the `DATABASE_URL` in the generated credentials secret with an SSL mode. This is controlled by the `DATABASE_SSLMODE` environment variable on the operator deployment (defaults to `require`).

For local development or clusters without Postgres TLS, you can set `DATABASE_SSLMODE=disable`.

**Migration Caveat for Existing Databases:**
The operator creates the credentials secret only once (when it is absent). If you change `DATABASE_SSLMODE`, existing secrets will **not** be updated automatically to avoid accidental password rotation. To apply the new SSL mode to an existing database, you must delete its credentials secret and let the operator recreate it, or create a fresh `PostgresDatabase` resource.

## Getting Started

### Prerequisites
- go version v1.22.0+
- docker version 17.03+.
- kubectl version v1.11.3+.
- Access to a Kubernetes v1.11.3+ cluster.

### To Deploy on the cluster
**Build and push your image to the location specified by `IMG`:**

```sh
make docker-build docker-push IMG=<some-registry>/postgres-operator-go:tag
```

**NOTE:** This image ought to be published in the personal registry you specified.
And it is required to have access to pull the image from the working environment.
Make sure you have the proper permission to the registry if the above commands don’t work.

**Install the CRDs into the cluster:**

```sh
make install
```

**Deploy the Manager to the cluster with the image specified by `IMG`:**

```sh
make deploy IMG=<some-registry>/postgres-operator-go:tag
```

> **NOTE**: If you encounter RBAC errors, you may need to grant yourself cluster-admin
privileges or be logged in as admin.

**Create instances of your solution**
You can apply the samples (examples) from the config/sample:

```sh
kubectl apply -k config/samples/
```

>**NOTE**: Ensure that the samples has default values to test it out.

### To Uninstall
**Delete the instances (CRs) from the cluster:**

```sh
kubectl delete -k config/samples/
```

**Delete the APIs(CRDs) from the cluster:**

```sh
make uninstall
```

**UnDeploy the controller from the cluster:**

```sh
make undeploy
```

## Project Distribution

Following are the steps to build the installer and distribute this project to users.

1. Build the installer for the image built and published in the registry:

```sh
make build-installer IMG=<some-registry>/postgres-operator-go:tag
```

NOTE: The makefile target mentioned above generates an 'install.yaml'
file in the dist directory. This file contains all the resources built
with Kustomize, which are necessary to install this project without
its dependencies.

2. Using the installer

Users can just run kubectl apply -f <URL for YAML BUNDLE> to install the project, i.e.:

```sh
kubectl apply -f https://raw.githubusercontent.com/<org>/postgres-operator-go/<tag or branch>/dist/install.yaml
```

## Running and Deploying Locally

For local development and testing, you can either run the operator on your host machine targeting a local Kubernetes cluster (fastest for development) or package and run it inside the cluster using Helm.

### Option 1: Running on Host (Fastest for Development)

This method runs the operator controller as a local Go process on your host machine, connecting to whichever Kubernetes cluster is currently set in your active kubeconfig context (e.g. Kind or Minikube).

#### 1. Install the CRD
Install the `PostgresDatabase` Custom Resource Definition into your local cluster:
```sh
make install
```

#### 2. Run the Controller
Run the operator process locally on your host. It will automatically watch resources across all namespaces:
```sh
make run
```

#### 3. Test and Verify
In a separate terminal, deploy a sample database:
```sh
kubectl apply -f config/samples/postgres_v1alpha1_postgresdatabase.yaml
```

Verify that the operator is active and provisions the StatefulSet, credentials Secret, and Service:
```sh
kubectl get postgresdatabases
kubectl get statefulset,svc,secret
```

#### 4. Clean Up
Stop the local process with `Ctrl+C`, then clean up resources:
```sh
kubectl delete -f config/samples/postgres_v1alpha1_postgresdatabase.yaml
make uninstall
```

---

### Option 2: Deploying inside Cluster with Helm (Kind/Minikube)

Use the local Helm chart at [`deploy/helm/postgres-operator-go`](deploy/helm/postgres-operator-go) to install the operator container directly on a local Kubernetes cluster such as Kind or Minikube.

#### Prerequisites

- Docker running locally.
- Helm installed.
- `kubectl` configured for your local cluster.
- A local Kubernetes cluster, for example Kind or Minikube.

#### Install on Kind

Build the controller image locally:

```sh
make docker-build IMG=postgres-operator-go:local
```
Find the cluster name
```sh
kind get clusters
```

Load the image into your Kind cluster:

```sh
kind load docker-image postgres-operator-go:local --name <cluster-name>
```

If you created the cluster with Kind's default name, use `--name kind`.

Check whether the `PostgresDatabase` CRD already exists:

```sh
kubectl get crd postgresdatabases.postgres.vibhordubey.com
```

If the command returns `NotFound`, install the operator and let Helm create the CRD:

```sh
helm upgrade --install postgres-operator ./deploy/helm/postgres-operator-go \
  --namespace postgres-operator-system \
  --create-namespace \
  --set replicaCount=1 \
  --set image.repository=postgres-operator-go \
  --set image.tag=local \
  --set image.pullPolicy=IfNotPresent
```

If the CRD already exists because you previously ran `make install`, Kustomize, or another non-Helm install, keep the existing CRD and install only the operator resources:

```sh
helm upgrade --install postgres-operator ./deploy/helm/postgres-operator-go \
  --namespace postgres-operator-system \
  --create-namespace \
  --set installCRDs=false \
  --set replicaCount=1 \
  --set image.repository=postgres-operator-go \
  --set image.tag=local \
  --set image.pullPolicy=IfNotPresent
```

If Helm reports that the CRD "exists and cannot be imported into the current release" because ownership metadata is missing, use the `installCRDs=false` command above. That error means the CRD is already present but was not created by this Helm release.

#### Minikube Alternative

For Minikube, build the image directly inside Minikube's Docker environment before running the appropriate Helm install command for your CRD state:

```sh
eval $(minikube docker-env)
make docker-build IMG=postgres-operator-go:local
```

#### Verify the Local Install

Wait for the operator deployment:

```sh
kubectl rollout status deployment/postgres-operator-postgres-operator-go -n postgres-operator-system
kubectl get pods -n postgres-operator-system
```

Create a sample `PostgresDatabase`:

```sh
kubectl apply -f config/samples/postgres_v1alpha1_postgresdatabase.yaml
kubectl get postgresdatabases
```

#### Clean Up

Delete the sample database resource:

```sh
kubectl delete -f config/samples/postgres_v1alpha1_postgresdatabase.yaml --ignore-not-found
```

Uninstall the Helm release:

```sh
helm uninstall postgres-operator -n postgres-operator-system --ignore-not-found
```

The chart marks the CRD with `helm.sh/resource-policy: keep`, so Helm keeps it after uninstall. Deleting the CRD removes all `PostgresDatabase` custom resources, so only run this on a disposable local cluster or when you intentionally want to reset the CRD:

```sh
kubectl delete crd postgresdatabases.postgres.vibhordubey.com
```

## Deploying to AWS EKS

For production, deploy to AWS EKS with Terraform. Terraform owns the AWS foundation in [`terraform/infra`](terraform/infra) and the operator Helm release in [`terraform/operator`](terraform/operator). See [`terraform/README.md`](terraform/README.md) for the full workflow.

### Prerequisites

- Local AWS credentials with permission to create/update EKS, VPC, IAM, ECR, and Kubernetes resources.
- An S3 backend bucket for Terraform state; copy and fill in `terraform/infra/backend.example.hcl` and `terraform/operator/backend.example.hcl`.
- `AWS_ROLE_TO_ASSUME` configured as a GitHub Actions secret after `terraform/infra` creates the release role.
- `AWS_DEPLOY_ROLE_TO_ASSUME` configured as a GitHub Actions secret after `terraform/infra` creates the deploy role.
- `TF_STATE_BUCKET` configured as a GitHub Actions variable with the S3 backend bucket name.
- Optional GitHub Actions variables `AWS_REGION` and `EKS_CLUSTER` for the deploy job. If unset, the workflow uses `us-east-1` and `pg-operator-prod`.

### Bootstrap Production Once

Run the infra commands from the repository root on your local machine, where your AWS credentials are configured. This is a one-time production bootstrap that creates the EKS cluster, VPC, node groups, ECR repository, EBS CSI add-on, and GitHub OIDC IAM roles used by the release pipeline:

```sh
terraform -chdir=terraform/infra init -backend-config=backend.hcl -reconfigure
terraform -chdir=terraform/infra plan
terraform -chdir=terraform/infra apply
```

After apply, copy these outputs into GitHub Actions secrets:

```sh
terraform -chdir=terraform/infra output github_actions_release_role_arn
terraform -chdir=terraform/infra output github_actions_deploy_role_arn
```

Set `TF_STATE_BUCKET` in GitHub Actions variables to the same S3 bucket used by your Terraform backend.

### Automatic Release Deployment

After the bootstrap is complete and the workflow changes are pushed to `master`, create and push a `v*` tag from the repository root. Pushing the tag starts the release pipeline, and the `deploy-eks` job deploys the same immutable release to EKS through Terraform:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release pipeline builds and pushes the image to ECR/GHCR, publishes the Helm chart to the GitHub Release, then the `deploy-eks` job runs `terraform -chdir=terraform/operator apply` with `TF_VAR_release_version` set to the tag.

Because this setup uses GitHub-hosted runners, the EKS public API endpoint must be reachable from those runners. For stricter production networking, move the deploy job to CodeBuild in the VPC or a private self-hosted runner instead of widening EKS public endpoint access.

For manual recovery or one-off redeploys, you can still run the operator root locally after setting the release version:

```sh
export TF_VAR_release_version=v0.1.0
terraform -chdir=terraform/operator init -backend-config=backend.hcl -reconfigure
terraform -chdir=terraform/operator plan
terraform -chdir=terraform/operator apply
```

Set `manage_operator_crds=false` in `terraform/operator/terraform.tfvars` if the `PostgresDatabase` CRD already exists outside Helm. Set `enable_service_monitor=true` only after Prometheus Operator CRDs are installed.

### Verify

```sh
aws eks update-kubeconfig --region "$AWS_REGION" --name pg-operator-prod
kubectl rollout status deployment/postgres-operator-postgres-operator-go -n postgres-operator-system
kubectl get pods -n postgres-operator-system
kubectl get crd postgresdatabases.postgres.vibhordubey.com
kubectl get storageclass gp3
```

### Create a `PostgresDatabase` using `gp3`

Create a small EKS-backed smoke test database only after the `gp3` storage class exists:

```sh
kubectl apply -f - <<EOF
apiVersion: postgres.vibhordubey.com/v1alpha1
kind: PostgresDatabase
metadata:
  name: eks-smoke-db
  namespace: default
spec:
  databaseName: smoke_app
  storage:
    size: 10Gi
    storageClass: gp3
EOF

kubectl get postgresdatabases
kubectl get pvc
```

## Contributing
We welcome contributions to `postgres-operator-go`! To get started:

1. **Fork the Repository**: Create a personal fork and clone it.
2. **Implement Changes**: Add tests for new features or bug fixes.
3. **Format & Lint**: Ensure your code meets quality standards:
   ```sh
   make fmt
   make vet
   ```
4. **Generate Manifests**: If you update the Custom Resource API schemas (`api/v1alpha1/*_types.go`) or controller RBAC annotations, run:
   ```sh
   make manifests
   ```
5. **Run Tests**: Make sure all unit and integration tests pass:
   ```sh
   make test
   ```
6. **Submit a PR**: Open a Pull Request with a clear description of your changes.

**NOTE:** Run `make help` for more information on all potential `make` targets

More information can be found via the [Kubebuilder Documentation](https://book.kubebuilder.io/introduction.html)

## License

Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
