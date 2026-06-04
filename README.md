# postgres-operator-go

[![CI](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/ci.yml/badge.svg)](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/ci.yml)
[![Release](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/release.yml/badge.svg)](https://github.com/vibhordubey333/postgres-operator-go/actions/workflows/release.yml)

// TODO(user): Add simple overview of use/purpose

## Description
// TODO(user): An in-depth paragraph about your project and overview of use

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
// TODO(user): Add detailed information on how you would like others to contribute to this project

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

