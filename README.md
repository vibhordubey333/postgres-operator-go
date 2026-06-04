# postgres-operator-go

[![CI](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/ci.yml/badge.svg)](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/ci.yml)
[![Release](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/release.yml/badge.svg)](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/release.yml)

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

## Deploying Locally with Helm

Use the local Helm chart at [`deploy/helm/postgres-operator-go`](deploy/helm/postgres-operator-go) to install the operator on a local Kubernetes cluster such as Kind or Minikube.

### Prerequisites

- Docker running locally.
- Helm installed.
- `kubectl` configured for your local cluster.
- A local Kubernetes cluster, for example Kind or Minikube.

### Install on Kind

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

### Minikube Alternative

For Minikube, build the image directly inside Minikube's Docker environment before running the appropriate Helm install command for your CRD state:

```sh
eval $(minikube docker-env)
make docker-build IMG=postgres-operator-go:local
```

### Verify the Local Install

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

### Clean Up

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

Use the Helm chart published to GHCR (OCI) together with [`deploy/helm/values-eks-prod.yaml`](deploy/helm/values-eks-prod.yaml) for a production-oriented EKS install (GHCR image, IRSA-ready `ServiceAccount`, HA, `DATABASE_SSLMODE=require`, and optional `ServiceMonitor`).

### Prerequisites

- An EKS cluster and `kubectl` configured for it.
- [AWS EBS CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) installed so you can use EBS-backed storage classes (e.g. `gp3`).
- A Git tag / GitHub Release (e.g. `v0.1.0`) that has published the controller image and Helm chart to GHCR (see the Release workflow).
- (Optional) [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator) if you keep `metrics.serviceMonitor.enabled: true` in the values file.

### IAM Roles for Service Accounts (IRSA)

If the operator will call AWS APIs (for example S3 backups), create an IAM role trusted by the operator’s Kubernetes `ServiceAccount` and set its ARN in `deploy/helm/values-eks-prod.yaml` under `serviceAccount.annotations.eks.amazonaws.com/role-arn`. If you are not using IRSA yet, remove that annotation or set it to your real role ARN before applying.

### Install with Helm (OCI chart from GHCR)

From a checkout of this repository (so the values file path exists locally):

```bash
helm upgrade --install postgres-operator oci://ghcr.io/vibhordubey333/postgres-operator-go \
  --version v0.1.0 \
  --namespace postgres-operator-system \
  --create-namespace \
  -f deploy/helm/values-eks-prod.yaml \
  --set image.tag=v0.1.0
```

Replace `v0.1.0` with the chart/app version you are deploying. You can instead set `image.tag` inside `deploy/helm/values-eks-prod.yaml` and omit `--set`.

If the GHCR image is **private**, create a pull secret and reference it in `imagePullSecrets` in the same values file (see comments in that file).

### Create a `PostgresDatabase` using `gp3`

Ensure a `StorageClass` named `gp3` exists (often created when you install the EBS CSI driver add-on). Example:

```yaml
apiVersion: postgres.vibhordubey.com/v1alpha1
kind: PostgresDatabase
metadata:
  name: prod-db
  namespace: default
spec:
  databaseName: prod_app
  storage:
    size: 50Gi
    storageClass: gp3
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
