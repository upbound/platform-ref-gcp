# Google Cloud Platform (GCP) Reference Platform

This repository contains a reference GCP Platform Configuration for
[Crossplane](https://crossplane.io/). It's a great starting point for building
internal cloud platforms with GCP and offer a self-service API to your internal
development teams.

This platform provides APIs to provision fully configured GKE clusters, with
secure networking, and stateful cloud services (Cloud SQL for PostgreSQL) designed to securely
connect to the nodes in each GKE cluster — all composed using cloud service
primitives from the [Official Upbound GCP
Provider](https://marketplace.upbound.io/providers/upbound/provider-family-gcp/). App
deployments can securely connect to the infrastructure they need using secrets
distributed directly to the app namespace.

## Overview

This reference platform outlines a specialized API for generating an GKE cluster
([XCluster](apis/cluster/definition.yaml)) that incorporates XRs from the specified configurations:

* [upbound-configuration-app](https://github.com/upbound/configuration-app)
* [upbound-configuration-gcp-database](https://github.com/upbound/configuration-gcp-database)
* [upbound-configuration-gcp-gke](https://github.com/upbound/configuration-gcp-gke)
* [upbound-configuration-gcp-network](https://github.com/upbound/configuration-gcp-network)
* [upbound-configuration-gitops-flux](https://github.com/upbound/configuration-gitops-flux)
* [upbound-configuration-observability-oss](https://github.com/upbound/configuration-observability-oss)


```mermaid
graph LR;
    MyApp(My App)---MyCluster(XRC: my-cluster);
    MyCluster---XRD1(XRD: XCluster);
    MyApp---MyDB(XRC: my-db);
    MyDB---XRD2(XRD: XPostgreSQLInstance);
		subgraph Configuration:upbound/platform-ref-gcp;
	    XRD1---Composition(XGKE, XNetwork, XServices);
	    XRD2---Composition2(Composition);
		end
		subgraph Provider:upbound/provider-gcp
	    Composition---Network.MRs(MRs: Network, Subnetwork);
	    Composition---GKE.MRs(MRs: Cluster, NodePool, ServiceAccount, ServiceAccountKey, ProjectIAMMember);
	    Composition2---Postgres.MRs(MRs: DatabaseInstance, User, Connection, GlobalAddress);
		end

style MyApp color:#000,fill:#e6e6e6,stroke:#000,stroke-width:2px
style MyCluster color:#000,fill:#D68A82,stroke:#000,stroke-width:2px
style MyDB color:#000,fill:#D68A82,stroke:#000,stroke-width:2px
style Configuration:upbound/platform-ref-gcp fill:#f1d16d,opacity:0.3
style Provider:upbound/provider-gcp fill:#81CABB,opacity:0.3
style XRD1 color:#000,fill:#f1d16d,stroke:#000,stroke-width:2px,stroke-dasharray: 5 5
style XRD2 color:#000,fill:#f1d16d,stroke:#000,stroke-width:2px,stroke-dasharray: 5 5
style Composition color:#000,fill:#f1d16d,stroke:#000,stroke-width:2px
style Composition2 color:#000,fill:#f1d16d,stroke:#000,stroke-width:2px

style Network.MRs color:#000,fill:#81CABB,stroke:#000,stroke-width:2px
style GKE.MRs color:#000,fill:#81CABB,stroke:#000,stroke-width:2px
style Postgres.MRs color:#000,fill:#81CABB,stroke:#000,stroke-width:2px
```

Learn more about Composite Resources in the [Crossplane
Docs](https://docs.crossplane.io/latest/concepts/compositions/).

## Quickstart

### Pre-Requisites

Before we can install the reference platform we want to install the `up` CLI.
This is a utility that makes following this quickstart guide easier. Everything
described here can also be done in a declarative approach which we highly
recommend for any production type use-case.
<!-- TODO enhance this guide: Getting ready for Gitops -->

To install `up` run this install script:
```console
curl -sL https://cli.upbound.io | sh
```
See [up docs](https://docs.upbound.io/cli/) for more install options.

For installing the platform we need a running Crossplane control plane. We are
using [Universal Crossplane (UXP)
](https://github.com/upbound/universal-crossplane). Ensure that your kubectl
context is pointing to the correct Kubernetes cluster or for example create a
[kind](https://kind.sigs.k8s.io) cluster:

```console
kind create cluster
```

Finally install UXP into the `upbound-system` namespace:

```console
up uxp install
```

You can validate the install by inspecting all installed components:

```console
kubectl get all -n upbound-system
```

### Install the GCP Reference Platform

Now you can install this reference platform. It's packaged as a [Crossplane
configuration package](https://docs.crossplane.io/latest/concepts/packages/)
so there is a single command to install it:

```console
up ctp configuration install xpkg.upbound.io/upbound/platform-ref-gcp:v0.5.0
```

Validate the install by inspecting the provider and configuration packages:
```console
kubectl get providers,providerrevision

kubectl get configurations,configurationrevisions
```

Check the
[marketplace](https://marketplace.upbound.io/configurations/upbound/platform-ref-gcp/)
for the latest version of this platform.

### Configure the GCP provider

Before we can use the reference platform we need to configure it with GCP
credentials.

Create a JSON `gcp.json` key file containing the GCP account credentials. GCP provides documentation on [how to create a key file](https://cloud.google.com/iam/docs/creating-managing-service-account-keys#creating).

Example `gcp.json` key should look similar to the structure below:
```json
{
  "type": "service_account",
  "project_id": "caramel-goat-354919",
  "private_key_id": "e97e40a4a27661f12345678f4bd92139324dbf46",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCwA+6MWRhmcPB3\nF/irb5MDPYAT6BWr7Vu/16U8FbCHk7xtsAWYjKXKHu5mGzum4F781sM0aMCeitlv\n+jr2y7Ny23S9uP5W2kfnD/lfj0EjCdfoaN3m7W0j4DrriJviV6ESeSdb0Ehg+iEW\ngNrkb/ljigYgsSLMuemby5lvJVINUazXJtGUEZew+iAOnI4/j/IrDXPCYVNo5z+b\neiMsDYWfccenWGOQf1hkbVWyKqzsInxu8NQef3tNhoUXNOn+/kgarOA5VTYvFUPr\n2l1P9TxzrcYuL8XK++HjVj5mcNaWXNN+jnFpxjMIJOiDJOZoAo0X7tuCJFXtAZbH\n9P61GjhbAgMBAAECggEARXo31kRw4jbgZFIdASa4hAXpoXHx4/x8Q9yOR4pUNR/2\nt+FMRCv4YTEWb01+nV9hfzISuYRDzBEIxS+jyLkda0/+48i69HOTAD0I9VRppLgE\ne97e40a4a27661f12345678f4bd92139324dbf46+2H7ulQDtbEgfcWpNMQcL2JiFq+WS\neh3H0gHSFFIWGnAM/xofrlhGsN64palZmbt2YiKXcHPT+WgLbD45mT5j9oMYxBJf\nPkUUX5QibSSBQyvNqCgRKHSnsY9yAkoNTbPnEV0clQ4FmSccogyS9uPEocQDefuY\nY7gpwSzjXpaw7tP5scK3NtWmmssi+dwDadfLrKF7oQKBgQDjIZ+jwAggCp7AYB/S\n6dznl5/G28Mw6CIM6kPgFnJ8P/C/Yi2y/OPKFKhMs2ecQI8lJfcvvpU/z+kZizcG\nr/7iRMR/SX8n1eqS8XfWKeBzIdwQmiKyRg2AKelGKljuVtI8sXKv9t6cm8RkWKuZ\n9uVroTCPWGpIrh2EMxLeOrlm0QKBgQDGYxoBvl5GfrOzjhYOa5GBgGYYPdE7kNny\nhpHE9CrPZFIcb5nGMlBCOfV+bqA9ALCXKFCr0eHhTjk9HjHfloxuxDmz34vC0xXG\ncegqfV9GNKZPDctysAlCWW/dMYw4+tzAgoG9Qm13Iyfi2Ikll7vfeMX7fH1cnJs0\nnYpN9LYPawKBgQCwMi09QoMLGDH+2pLVc0ZDAoSYJ3NMRUfk7Paqp784VAHW9bqt\n1zB+W3gTyDjgJdTl5IXVK+tsDUWu4yhUr8LylJY6iDF0HaZTR67HHMVZizLETk4M\nLfvbKKgmHkPO4NtG6gEmMESRCOVZUtAMKFPhIrIhAV2x9CBBpb1FWBjrgQKBgQCj\nkP3WRjDQipJ7DkEdLo9PaJ/EiOND60/m6BCzhGTvjVUt4M22XbFSiRrhXTB8W189\noZ2xrGBCNQ54V7bjE+tBQEQbC8rdnNAtR6kVrzyoU6xzLXp6Wq2nqLnUc4+bQypT\nBscVVfmO6stt+v5Iomvh+l+x05hAjVZh8Sog0AxzdQKBgQCMgMTXt0ZBs0ScrG9v\np5CGa18KC+S3oUOjK/qyACmCqhtd+hKHIxHx3/FQPBWb4rDJRsZHH7C6URR1pHzJ\nmhCWgKGsvYrXkNxtiyPXwnU7PNP9JNuCWa45dr/vE/uxcbccK4JnWJ8+Kk/9LEX0\nmjtDm7wtLVlTswYhP6AP69RoMQ==\n-----END PRIVATE KEY-----\n",
  "client_email": "my-sa-313@caramel-goat-354919.iam.gserviceaccount.com",
  "client_id": "103735491955093092925",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/my-sa-313%40caramel-goat-354919.iam.gserviceaccount.com"
}
```

### Create a K8s secret with the GCP creds:

```console
kubectl create secret generic gcp-creds -n upbound-system --from-file=credentials=./gcp.json
```

Ensure that the following roles are added to your service account:

* `roles/compute.networkAdmin`
* `roles/container.admin`
* `roles/iam.serviceAccountUser`
* `roles/iam.securityAdmin`
* `roles/iam.serviceAccountAdmin`
* `roles/iam.serviceAccountKeyAdmin`
* `roles/cloudsql.admin`

It is convenient to assign roles with `gcloud` CLI, e.g.

```console
gcloud projects add-iam-policy-binding --role="$ROLE" $PROJECT_ID --member "serviceAccount:$SA"
```

### Configure the GCP Provider to use the secret:
```console
kubectl apply -f https://raw.githubusercontent.com/upbound/platform-ref-gcp/main/examples/gcp-default-provider.yaml
```

See [provider-gcp docs](https://marketplace.upbound.io/providers/upbound/provider-gcp/latest/docs/configuration) for more detailed configuration options.

### Using the GCP reference platform

🎉 Congratulations. You have just installed your first Crossplane powered
platform!

Application developers can now use the platform to request resources which than
will provisioned in GCP. This would usually done by bundling a claim as part of
the application code. In our example here we simply create the claims directly:

Create a custom defined cluster:
```console
kubectl apply -f https://raw.githubusercontent.com/upbound/platform-ref-gcp/main/examples/cluster-claim.yaml
```

Create a custom defined database:
```console
kubectl apply -f https://raw.githubusercontent.com/upbound/platform-ref-gcp/main/examples/postgres-claim.yaml
```

You can verify status by inspecting the claims, composites and managed
resources:

```console
kubectl get claim,composite,managed
```

If you see an error about the `compute.globalAddresses.list` permission for the project, try running the following gcloud command:
```
gcloud projects add-iam-policy-binding HOST_PROJECT_NAME \
    --member=serviceAccount:service-HOST_PROJECT_NUMBER@service-networking.iam.gserviceaccount.com \
    --role=roles/servicenetworking.serviceAgent
```

This recommendation is an excerpt from [the official GCP
documentation](https://cloud.google.com/sql/docs/postgres/configure-private-services-access)

To delete the provisioned resources, you would simply delete the claims again:

```console
kubectl delete -f examples/cluster-claim.yaml,examples/postgres-claim.yaml
```

To uninstall the provider & platform configuration:

```console
kubectl delete configurations.pkg.crossplane.io upbound-platform-ref-gcp
kubectl delete configurations.pkg.crossplane.io upbound-configuration-app
kubectl delete configurations.pkg.crossplane.io upbound-configuration-gcp-database
kubectl delete configurations.pkg.crossplane.io upbound-configuration-gcp-gke
kubectl delete configurations.pkg.crossplane.io upbound-configuration-gcp-network
kubectl delete configurations.pkg.crossplane.io upbound-configuration-gitops-flux
kubectl delete configurations.pkg.crossplane.io upbound-configuration-observability-oss

kubectl delete provider.pkg.crossplane.io crossplane-contrib-provider-helm
kubectl delete provider.pkg.crossplane.io crossplane-contrib-provider-kubernetes
kubectl delete provider.pkg.crossplane.io grafana-provider-grafana
kubectl delete provider.pkg.crossplane.io upbound-provider-family-gcp
kubectl delete provider.pkg.crossplane.io upbound-provider-gcp-cloudplatform
kubectl delete provider.pkg.crossplane.io upbound-provider-gcp-compute
kubectl delete provider.pkg.crossplane.io upbound-provider-gcp-container
kubectl delete provider.pkg.crossplane.io upbound-provider-gcp-servicenetworking
kubectl delete provider.pkg.crossplane.io upbound-provider-gcp-sql

kubectl delete function.pkg.crossplane.io upbound-function-patch-and-transform
```

## Customize for your Organization

So far we have used the existing reference platform but haven't made any
changes. Lets change this and customize the platform by ensuring that GKE
Cluster is deployed to Frankfurt (eu-central-1) and that clusters are limitted
to 10 nodes.

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
up login --username=$ORG
```

### Make the changes

To make your changes clone this repository:

```console
git clone https://github.com/upbound/platform-ref-gcp.git $PLATFORM && cd $PLATFORM
```

### Build and push your platform

To share your new platform you need to build and distribute this package.

To build the package use the `up xpkg build` command:

```console
up xpkg build --name package.xpkg --package-root=package --examples-root=examples
```

Afterwards you can it to the marketplace. Don't worry it's private to you.

```console
TAG=v0.1.0
up repo create ${PLATFORM}
up xpkg push ${ORG}/${PLATFORM}:${TAG} -f package/package.xpkg
```

You can now see your listing in the marketplace:
```console
open https://marketplace.upbound.io/configurations/${ORG}/${PLATFORM}/${TAG}
```

## Using your custom platform

Now if you want to use it you can follow the steps from above. The only
difference is that you need to specify a package-pull-secret as the package is
currently private:

```console
up ctp pull-secret create personal-pull-secret
```

```console
up ctp configuration install xpkg.upbound.io/${ORG}/${PLATFORM}:${TAG} --package-pull-secrets=personal-pull-secret
```

For alternative declarative installation approach see the [example Configuration
manifest](examples/configuration.yaml). Please update to your org, platform and
tag before applying.

🎉 Congratulations. You have just build and installed your first custom
Crossplane powered platform!


## Questions?

For any questions, thoughts and comments don't hesitate to [reach
out](https://www.upbound.io/contact) or drop by
[slack.crossplane.io](https://slack.crossplane.io), and say hi!
