"""Build the composed resources and published status for one Cluster XR.

A Cluster is the platform API. It composes the domain APIs - Network, GKE, Oss and Flux, each
published by its own Configuration package - and never a provider managed resource. Machine types,
chart versions and provider resources are implementation choices made here or in the domain
packages, so they can change without changing the Cluster schema or the Clusters built from it.

Dependencies between domains point one way and are read from published contracts: Apps are found
through their own API and matched on spec.parameters.providerConfigName, never through the Helm
Releases that happen to implement them.

Nothing here talks to Crossplane. build() returns models and status() a dict, so both can be
asserted on directly in unit tests, including that a resource is not composed.
"""

from models.io.crossplane.protection.usage import v1beta1 as usagev1beta1
from models.io.k8s.apimachinery.pkg.apis.meta import v1 as metav1
from models.io.upbound.platform.gcp.gke import v1alpha1 as gkev1alpha1
from models.io.upbound.platform.gcp.network import v1alpha1 as networkv1alpha1
from models.io.upbound.platform.gitops.flux import v1alpha1 as fluxv1alpha1
from models.io.upbound.platform.observe.oss import v1alpha1 as ossv1alpha1
from models.io.upbound.platformref.gcp.cluster import v1alpha1 as clusterv1alpha1
from pydantic import BaseModel

# Composition resource names identify composed resources across reconciles. Crossplane keeps an
# existing resource's name while its composition resource name is unchanged, so renaming one of
# these would replace the resource - for GKE, the cluster itself. Never rename them.
NETWORK = "composite-network-gcp"
GKE = "composite-cluster-gke"
OSS = "composite-observability-oss"
FLUX = "composite-gitops-flux"
USAGE_GKE_BY_FLUX = "usage-gke-by-flux"
USAGE_GKE_BY_OSS = "usage-gke-by-oss"
USAGE_GKE_BY_APP = "usage-gke-by-app-"  # suffixed with the App's name

# Apps labelled for deletion ordering keep the GKE cluster they run on until they're gone.
APP_API_VERSION = "platform.upbound.io/v1alpha1"
DELETION_ORDERING_LABEL = "platform.upbound.io/deletion-ordering"

CLUSTER_ID_LABEL = "gcp.platformref.upbound.io/cluster-id"
# Set on GKE before CLUSTER_ID_LABEL existed; kept for anything that selects on it.
GKE_CLUSTER_ID_LABEL = "xgke.gcp.platform.upbound.io/cluster-id"

# Implementation choices behind the API. Every Cluster that hasn't pinned an override follows a
# change here on its next reconcile, so roll edits out like any other change to running clusters.
MACHINE_TYPES = {
    "small": "n1-standard-2",
    "medium": "n1-standard-4",
    "large": "n1-standard-8",
}
FLUX_VERSION = "2.10.6"
FLUX_SYNC_VERSION = "1.7.2"
PROMETHEUS_VERSION = "52.1.0"

# deletionPolicy: Orphan manages everything except deletion, so cloud resources outlive the XR.
# Oss doesn't accept LateInitialize, and documents this list as its way to orphan.
ORPHAN_POLICIES = ["Create", "Observe", "Update", "LateInitialize"]
OSS_ORPHAN_POLICIES = ["Create", "Observe", "Update"]


def is_ready(observed: dict | None, name: str) -> bool:
    """Whether the observed composed resource reports Ready=True."""
    conditions = (((observed or {}).get(name) or {}).get("status") or {}).get("conditions") or []
    return any(c.get("type") == "Ready" and c.get("status") == "True" for c in conditions)


def _version(override, default: str) -> str:
    return override.version if override and override.version else default


def _gke_usage(name: str, labels: dict[str, str], by: usagev1beta1.By) -> usagev1beta1.Usage:
    """Keep this Cluster's GKE cluster until the using resource is gone."""
    return usagev1beta1.Usage(
        metadata=metav1.ObjectMeta(name=name, labels=labels),
        spec=usagev1beta1.Spec(
            replayDeletion=True,
            by=by,
            of=usagev1beta1.Of(
                apiVersion="gcp.platform.upbound.io/v1alpha1",
                kind="GKE",
                resourceSelector=usagev1beta1.ResourceSelectorModel(matchControllerRef=True),
            ),
        ),
    )


def build(
    xr_name: str,
    params: clusterv1alpha1.Parameters,
    *,
    observed: dict[str, dict] | None = None,
    apps: list[dict] = (),
) -> dict[str, BaseModel]:
    """Return the composed resources, as models, keyed by composition resource name.

    observed holds the observed composed resources keyed by composition resource name, or None
    offline; it gates the resources that run inside the cluster. apps are the App XRs in the
    Cluster's namespace that opted in to deletion ordering.
    """
    observed = observed or {}
    operators = params.operators or clusterv1alpha1.Operators()
    orphan = params.deletionPolicy == "Orphan"
    policies = ORPHAN_POLICIES if orphan else ["*"]
    labels = {CLUSTER_ID_LABEL: params.id}

    # Names derive from the XR so that Clusters can share a namespace. Existing resources keep
    # the names they were created with.
    resources: dict[str, BaseModel] = {
        NETWORK: networkv1alpha1.Network(
            metadata=metav1.ObjectMeta(name=f"{xr_name}-network", labels=labels),
            spec=networkv1alpha1.Spec(
                parameters=networkv1alpha1.Parameters(
                    id=params.id,
                    region=params.region,
                    managementPolicies=policies,
                    providerConfigName=params.providerConfigName,
                ),
            ),
        ),
        GKE: gkev1alpha1.GKE(
            metadata=metav1.ObjectMeta(
                name=f"{xr_name}-gke",
                labels=labels | {GKE_CLUSTER_ID_LABEL: params.id},
            ),
            spec=gkev1alpha1.Spec(
                parameters=gkev1alpha1.Parameters(
                    id=params.id,
                    region=params.region,
                    managementPolicies=policies,
                    providerConfigName=params.providerConfigName,
                    version=params.version,
                    nodes=gkev1alpha1.Nodes(
                        count=params.nodes.count,
                        instanceType=params.nodes.instanceType or MACHINE_TYPES[params.nodes.size],
                    ),
                ),
            ),
        ),
    }

    # The observability stack and Flux run inside the cluster, so wait for it. Once they exist
    # keep them, even if GKE stops reporting Ready, so a blip doesn't uninstall them.
    gke_ready = is_ready(observed, GKE)

    if gke_ready or OSS in observed:
        resources[OSS] = ossv1alpha1.Oss(
            metadata=metav1.ObjectMeta(name=f"{xr_name}-observability", labels=labels),
            spec=ossv1alpha1.Spec(
                parameters=ossv1alpha1.Parameters(
                    id=params.id,
                    managementPolicies=OSS_ORPHAN_POLICIES if orphan else ["*"],
                    operators=ossv1alpha1.Operators(
                        prometheus=ossv1alpha1.Prometheus(
                            version=_version(operators.prometheus, PROMETHEUS_VERSION),
                        ),
                    ),
                ),
            ),
        )
        resources[USAGE_GKE_BY_OSS] = _gke_usage(
            f"{params.id}-gke-by-oss",
            labels,
            usagev1beta1.By(
                apiVersion="observe.platform.upbound.io/v1alpha1",
                kind="Oss",
                resourceSelector=usagev1beta1.ResourceSelector(matchControllerRef=True),
            ),
        )

    if gke_ready or FLUX in observed:
        resources[FLUX] = fluxv1alpha1.FluxModel(
            metadata=metav1.ObjectMeta(name=f"{xr_name}-gitops", labels=labels),
            spec=fluxv1alpha1.Spec(
                parameters=fluxv1alpha1.Parameters(
                    # GKE publishes a Helm ProviderConfig named after the cluster ID.
                    providerConfigName=params.id,
                    managementPolicies=policies,
                    operators=fluxv1alpha1.Operators(
                        flux=fluxv1alpha1.Flux(version=_version(operators.flux, FLUX_VERSION)),
                        fluxSync=fluxv1alpha1.FluxSync(
                            version=_version(operators.flux_sync, FLUX_SYNC_VERSION),
                        ),
                    ),
                    source=params.gitops.model_dump(exclude_none=True),
                ),
            ),
        )
        resources[USAGE_GKE_BY_FLUX] = _gke_usage(
            f"{params.id}-gke-by-flux",
            labels,
            usagev1beta1.By(
                apiVersion="gitops.platform.upbound.io/v1alpha1",
                kind="Flux",
                resourceSelector=usagev1beta1.ResourceSelector(matchControllerRef=True),
            ),
        )

    # One Usage per App deployed to this cluster, named by reference so each App is protected.
    for app in apps:
        app_name = app["metadata"]["name"]
        if (app.get("spec") or {}).get("parameters", {}).get("providerConfigName") != params.id:
            continue
        resources[USAGE_GKE_BY_APP + app_name] = _gke_usage(
            f"{params.id}-gke-by-app-{app_name}",
            labels,
            usagev1beta1.By(
                apiVersion=APP_API_VERSION,
                kind="App",
                resourceRef=usagev1beta1.ResourceRef(name=app_name),
            ),
        )

    return resources


def status(params: clusterv1alpha1.Parameters, *, observed: dict[str, dict] | None = None) -> dict:
    """Return what the Cluster publishes for the resources that build on it."""
    observed = observed or {}
    gke_ready = is_ready(observed, GKE)

    kubernetes = {"ready": gke_ready, "providerConfigName": params.id}
    if gke_ready:
        # The GKE domain publishes its kubeconfig in a Secret named after the GKE XR.
        gke_name = observed[GKE]["metadata"]["name"]
        kubernetes["kubeconfigSecretRef"] = {"name": f"{gke_name}-connection", "key": "kubeconfig"}

    return {
        "network": {"id": params.id, "ready": is_ready(observed, NETWORK)},
        "kubernetes": kubernetes,
        "observability": {"ready": is_ready(observed, OSS)},
        "gitops": {"ready": is_ready(observed, FLUX)},
    }
