# Google Cloud Platform (GCP) Reference Platform

This repository contains a reference GCP Platform Configuration for
[Crossplane](https://crossplane.io/) v2 built with [Upbound DevEx](https://docs.upbound.io/devex/). It's a great starting point for building
internal cloud platforms with GCP and offer a self-service API to your internal
development teams.

This platform offers APIs for setting up fully configured GKE clusters
with secure networking, stateful cloud services (Cloud SQL for MySQL and PostgreSQL) that can securely
connect to the GKE clusters, an Observability Stack, and a GitOps
System. All these components are built using cloud service tools from
the [Official Upbound Family GCP Provider](https://marketplace.upbound.io/providers/upbound/provider-family-gcp).

## Architecture

The platform is built in layers, so the API your teams use can stay put while
everything underneath it changes.

* **Platform API.** The [`Cluster`](apis/cluster/definition.yaml) is what
  application teams create. It describes what they want - a region, a node
  count and size, a Git repository to sync - and nothing about how it's built.
* **Domain APIs.** `Network`, `GKE`, `Oss` (observability) and `Flux` (GitOps),
  plus `SQLInstance` and `App`, each come from their own Configuration package
  with its own release cycle:
  * [configuration-gcp-network](https://github.com/upbound/configuration-gcp-network)
  * [configuration-gcp-gke](https://github.com/upbound/configuration-gcp-gke)
  * [configuration-gcp-database](https://github.com/upbound/configuration-gcp-database)
  * [configuration-app](https://github.com/upbound/configuration-app)
  * [configuration-observability-oss](https://github.com/upbound/configuration-observability-oss)
  * [configuration-gitops-flux](https://github.com/upbound/configuration-gitops-flux)
* **Implementation.** The compositions behind each API. This is the only layer
  that names provider resources, machine types or chart versions, and the only
  one expected to change often.

The `Cluster` is composed by a Python function, [`functions/cluster`](functions/cluster/function/core.py),
that creates domain resources only - never a provider managed resource.

```mermaid
graph LR;
    App(App)-- providerConfigName ---Cluster;
    DB(SQLInstance)-- networkRef.id ---Cluster;
    subgraph Platform API: platform-ref-gcp;
        Cluster(Cluster);
    end
    subgraph Domain APIs: configuration packages;
        Cluster---Network(Network);
        Cluster---GKE(GKE);
        Cluster---Oss(Oss);
        Cluster---Flux(Flux);
    end
    subgraph Implementation: provider-family-gcp, provider-helm, provider-kubernetes;
        Network---NetworkMRs(Network, Subnetwork);
        GKE---GKEMRs(Cluster, NodePool, ServiceAccount, ...);
        Oss---OssMRs(Helm Releases);
        Flux---FluxMRs(Helm Releases);
        DB---DBMRs(DatabaseInstance, User, GlobalAddress, ...);
    end
```

### The Cluster API

A Cluster needs an `id`, a `region`, `nodes.count` and a `gitops.git.url` and
`ref`. Everything else has a default.

| Field | Meaning |
|---|---|
| `nodes.size` | `small`, `medium` (default) or `large`. The platform maps this to a current machine type. |
| `version` | Kubernetes version, `latest` by default. |
| `deletionPolicy` | `Delete` (default), or `Orphan` to leave the network and cluster running in GCP when the Cluster is deleted. |
| `providerConfigName` | The GCP ProviderConfig in the Cluster's namespace to provision with, `default` by default. |
| `nodes.instanceType` | Override: an exact machine type, used instead of `size`. |
| `operators.*.version` | Override: pin a Flux, Flux sync or Prometheus chart version. |

Overrides are a deliberate escape hatch. A pinned value stays as written, so
the Cluster stops following platform updates for that choice. Leave them unset
unless you need them.

A Cluster publishes what other resources need in its `status`. Read these rather
than deriving names yourself:

| Field | Use |
|---|---|
| `status.network.id` | `networkRef.id` on a `SQLInstance` |
| `status.kubernetes.providerConfigName` | `providerConfigName` on an `App` |
| `status.kubernetes.kubeconfigSecretRef` | the Secret holding the cluster's kubeconfig |
| `status.{network,kubernetes,observability,gitops}.ready` | readiness of each part |

### Changing the platform

Before a field goes into the Cluster schema, ask: if we replaced the
implementation underneath, would this field still make sense? `nodes.size`
would; a provider field or a chart version wouldn't, so those live in the
function or the domain packages.

* **Schema changes are additive.** Add optional fields; don't remove, rename or
  tighten existing ones. A breaking change needs a new API version and a
  migration path.
* **Implementation choices live in the function.** Machine types for each size
  and default chart versions are constants in
  [core.py](functions/cluster/function/core.py). Changing one rolls out to every
  Cluster that hasn't pinned an override, so treat it as a change to running
  clusters.
* **Composition resource names are permanent.** Crossplane matches composed
  resources by them; renaming one replaces the resource.
* **Running clusters don't depend on the control plane.** If Crossplane stops,
  the GKE clusters, networks and databases keep running; only reconciliation
  pauses. `deletionPolicy: Orphan` also keeps them through deletion of the
  Cluster.

## Development

```console
# Build the project and generate the Python models from the XRDs
up project build

# Run the function's unit tests (needs pytest and pydantic)
(cd functions/cluster && python -m pytest tests -q)

# Run composition tests
up test run tests/test-cluster

# Run end-to-end tests (needs an Upbound control plane)
up test run tests/e2etest-cluster --e2e

# Render a Cluster
up composition render --xrd=apis/cluster/definition.yaml apis/cluster/composition.yaml examples/cluster-claim.yaml
```

The function and tests are Python. `up project build` generates typed models
for every API this project uses into `.up/python`, and the function builds its
domain resources with them, so a resource that doesn't match its schema fails
in the function rather than at the API server.

The function is split the same way as Upbound's other Python functions:
[core.py](functions/cluster/function/core.py) builds the composed resources and
status without talking to Crossplane, and [fn.py](functions/cluster/function/fn.py)
only handles the request. The unit tests in [functions/cluster/tests](functions/cluster/tests)
test `core.py` directly, including what the composition tests can't: that a
resource is not composed.

## Quickstart

### Pre-Requisites

Install the `up` CLI:

```console
curl -sL https://cli.upbound.io | sh
```

See [up docs](https://docs.upbound.io/cli/) for more install options, and
install the `crossplane` CLI following https://docs.crossplane.io/latest/cli/.

You need a Kubernetes cluster running Crossplane v2. For example, create a
[kind](https://kind.sigs.k8s.io) cluster and install Upbound Crossplane (UXP)
into it:

```console
kind create cluster
up uxp install
kubectl get pods --all-namespaces | grep crossplane
```

### Install the GCP Reference Platform

The platform is a [Crossplane configuration
package](https://docs.crossplane.io/latest/packages/configurations/). Install it
declaratively:

```console
kubectl apply -f examples/configuration.yaml
kubectl get configurations --watch
```

After all Configurations are healthy, check the Providers and Functions they
pulled in as dependencies:

```console
kubectl get providers,functions
```

Check the
[marketplace](https://marketplace.upbound.io/configurations/upbound/platform-ref-gcp/)
for the latest version of this platform.

### Configure the GCP provider

Create a JSON `gcp.json` key file for a GCP service account; GCP documents
[how to create a key file](https://cloud.google.com/iam/docs/creating-managing-service-account-keys#creating).
It looks like this:

```json
{
  "type": "service_account",
  "project_id": "caramel-goat-354919",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "my-sa-313@caramel-goat-354919.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "..."
}
```

Ensure that the following roles are added to your service account:

* `roles/compute.networkAdmin`
* `roles/container.admin`
* `roles/iam.serviceAccountUser`
* `roles/iam.securityAdmin`
* `roles/iam.serviceAccountAdmin`
* `roles/iam.serviceAccountKeyAdmin`
* `roles/cloudsql.admin`
* `roles/servicenetworking.networksAdmin`

It is convenient to assign roles with `gcloud` CLI, e.g.

```console
gcloud projects add-iam-policy-binding --role="$ROLE" $PROJECT_ID --member "serviceAccount:$SA"
```

Crossplane v2 resources are namespaced, and so is their ProviderConfig. Create
the credentials Secret and the ProviderConfig in the namespace you'll create
Clusters in - `default` here. Set `projectID` in the ProviderConfig to your
project first.

```console
kubectl create secret generic gcp-creds -n default --from-file=credentials=./gcp.json
kubectl apply -f examples/gcp-default-provider.yaml
```

To use Upbound's identity federation instead of a key file, see
[providerconfig-proidc.yaml](examples/providerconfig-proidc.yaml) and the
[provider-gcp docs](https://marketplace.upbound.io/providers/upbound/provider-gcp).

### Using the GCP reference platform

🎉 Congratulations. You have just installed your first Crossplane powered
platform!

Application teams can now request infrastructure, usually by keeping these
resources alongside their application code. Here we create them directly.

Create a cluster:
```console
kubectl apply -f examples/cluster-claim.yaml
```

Create a database on the cluster's network:
```console
kubectl apply -f examples/mysql-claim.yaml
```

Deploy the sample application to the cluster once it's ready:
```console
kubectl apply -f examples/app-claim.yaml
```

The application uses the MySQL database's connection Secret, and the
`platform.upbound.io/deletion-ordering: enabled` label keeps its cluster from
being deleted before it is.

Check what the cluster publishes, and inspect everything it's made of:

```console
kubectl get cluster platform-ref-gcp -n default -o jsonpath='{.status}'
crossplane resource trace cluster.gcp.platformref.upbound.io/platform-ref-gcp -n default
```

If you see an error about the `compute.globalAddresses.list` permission for the project, try running the following gcloud command:
```
gcloud projects add-iam-policy-binding HOST_PROJECT_NAME \
    --member=serviceAccount:service-HOST_PROJECT_NUMBER@service-networking.iam.gserviceaccount.com \
    --role=roles/servicenetworking.serviceAgent
```

This recommendation is an excerpt from [the official GCP
documentation](https://cloud.google.com/sql/docs/postgres/configure-private-services-access)

To delete the provisioned resources, delete them again. Usages make sure the
cluster outlives what runs on it:

```console
kubectl delete -f examples/app-claim.yaml -f examples/mysql-claim.yaml -f examples/cluster-claim.yaml
```

To uninstall the platform, delete its Configuration and then the
Configurations, Providers and Functions it installed as dependencies:

```console
kubectl delete -f examples/configuration.yaml
kubectl get configurations,providers,functions
```

## Customize for your Organization

Clone this repository, change it, and publish it as your own package. For
example, to make `large` nodes bigger, change `MACHINE_TYPES` in
[core.py](functions/cluster/function/core.py): Clusters keep the same API and pick
up the new machine type. To offer teams a new option, add an optional field to
the [Cluster schema](apis/cluster/definition.yaml) and handle it in the
function. See [Changing the platform](#changing-the-platform) first.

For the following examples we are using `my-org` and `my-platform`:

```console
ORG=my-org
PLATFORM=my-platform
```

### Pre-Requisites
First you need to create a [free Upbound
account](https://accounts.upbound.io/register) to push your custom platform.
Afterwards you can log in:

```console
up login
```

### Make the changes

```console
git clone https://github.com/upbound/platform-ref-gcp.git $PLATFORM && cd $PLATFORM
```

### Build and push your platform

```console
up project build
up test run tests/test-cluster
up project push --repository=xpkg.upbound.io/${ORG}/${PLATFORM} --tag=v0.1.0
```

The repository is not listed in the marketplace automatically, but it is
publicly accessible.

## Using your custom platform

Point [examples/configuration.yaml](examples/configuration.yaml) at your
package, `xpkg.upbound.io/${ORG}/${PLATFORM}:v0.1.0`, and apply it as in the
quickstart.

🎉 Congratulations. You have just build and installed your first custom
Crossplane powered platform!

## Questions?

For any questions, thoughts and comments don't hesitate to [reach
out](https://www.upbound.io/contact) or drop by
[slack.crossplane.io](https://slack.crossplane.io), and say hi!
