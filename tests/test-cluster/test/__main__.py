"""Generate the Cluster CompositionTests and print them as YAML."""

import copy

import yaml
from models.io.k8s.apimachinery.pkg.apis.meta import v1 as k8s
from models.io.upbound.dev.meta.compositiontest import v1alpha1 as compositiontest

COMPOSITION = "../../apis/cluster/composition.yaml"
XRD = "../../apis/cluster/definition.yaml"

NAME = "platform-ref-gcp"
ID = "platform-ref-gcp-id"
LABELS = {"gcp.platformref.upbound.io/cluster-id": ID}

# A Cluster as a consumer writes it, relying on the platform for everything optional.
XR = {
    "apiVersion": "gcp.platformref.upbound.io/v1alpha1",
    "kind": "Cluster",
    "metadata": {"name": NAME, "namespace": "default"},
    "spec": {
        "parameters": {
            "id": ID,
            "region": "us-west2",
            "deletionPolicy": "Delete",
            "providerConfigName": "default",
            "nodes": {"count": 1, "size": "medium"},
            "gitops": {
                "git": {
                    "url": "https://github.com/upbound/platform-ref-gcp/",
                    "path": "/",
                    "interval": "5m0s",
                    "timeout": "60s",
                    "ref": {"name": "refs/heads/main"},
                },
            },
        },
    },
}

READY = {
    "conditions": [
        {
            "type": "Ready",
            "status": "True",
            "reason": "Available",
            "lastTransitionTime": "2024-01-01T00:00:00Z",
        },
    ],
}

OBSERVED_GKE_READY = {
    "apiVersion": "gcp.platform.upbound.io/v1alpha1",
    "kind": "GKE",
    "metadata": {
        "name": f"{NAME}-gke",
        "namespace": "default",
        "annotations": {"crossplane.io/composition-resource-name": "composite-cluster-gke"},
    },
    "spec": {
        "parameters": {
            "id": ID,
            "region": "us-west2",
            "providerConfigName": "default",
            "nodes": {"count": 1, "instanceType": "n1-standard-4"},
        }
    },
    "status": READY,
}

# The KCL implementation gave every Cluster's GKE this fixed name.
OBSERVED_LEGACY_GKE_READY = copy.deepcopy(OBSERVED_GKE_READY)
OBSERVED_LEGACY_GKE_READY["metadata"]["name"] = "composite-cluster-gke"


def meta(name: str, resource_name: str, labels: dict | None = None) -> dict:
    return {
        "name": name,
        "labels": labels or LABELS,
        "annotations": {"crossplane.io/composition-resource-name": resource_name},
    }


def xr(**parameters) -> dict:
    out = copy.deepcopy(XR)
    out["spec"]["parameters"].update(parameters)
    return out


def gke_usage(name: str, resource_name: str, by: dict) -> dict:
    return {
        "apiVersion": "protection.crossplane.io/v1beta1",
        "kind": "Usage",
        "metadata": meta(name, resource_name),
        "spec": {
            "replayDeletion": True,
            "by": by,
            "of": {
                "apiVersion": "gcp.platform.upbound.io/v1alpha1",
                "kind": "GKE",
                "resourceSelector": {"matchControllerRef": True},
            },
        },
    }


def app(name: str, provider_config_name: str) -> dict:
    return {
        "apiVersion": "platform.upbound.io/v1alpha1",
        "kind": "App",
        "metadata": {
            "name": name,
            "namespace": "default",
            "labels": {"platform.upbound.io/deletion-ordering": "enabled"},
        },
        "spec": {"parameters": {"providerConfigName": provider_config_name}},
    }


def test(name: str, **spec) -> compositiontest.CompositionTest:
    return compositiontest.CompositionTest(
        metadata=k8s.ObjectMeta(name=name),
        spec=compositiontest.Spec(
            compositionPath=COMPOSITION,
            xrdPath=XRD,
            timeoutSeconds=300,
            validate=True,
            **spec,
        ),
    )


tests = [
    # Before GKE is ready only the network and cluster are composed, under names derived from
    # the XR so several Clusters can share a namespace, and size maps to a machine type.
    test(
        "cluster-initial",
        xr=xr(),
        assertResources=[
            {
                "apiVersion": "gcp.platformref.upbound.io/v1alpha1",
                "kind": "Cluster",
                "metadata": {"name": NAME},
                "status": {
                    "network": {"id": ID, "ready": False},
                    "kubernetes": {"ready": False, "providerConfigName": ID},
                    "observability": {"ready": False},
                    "gitops": {"ready": False},
                },
            },
            {
                "apiVersion": "gcp.platform.upbound.io/v1alpha1",
                "kind": "Network",
                "metadata": meta(f"{NAME}-network", "composite-network-gcp"),
                "spec": {
                    "parameters": {
                        "id": ID,
                        "region": "us-west2",
                        "managementPolicies": ["*"],
                        "providerConfigName": "default",
                    }
                },
            },
            {
                "apiVersion": "gcp.platform.upbound.io/v1alpha1",
                "kind": "GKE",
                "metadata": meta(
                    f"{NAME}-gke",
                    "composite-cluster-gke",
                    LABELS | {"xgke.gcp.platform.upbound.io/cluster-id": ID},
                ),
                "spec": {
                    "parameters": {
                        "id": ID,
                        "region": "us-west2",
                        "managementPolicies": ["*"],
                        "providerConfigName": "default",
                        "nodes": {"count": 1, "instanceType": "n1-standard-4"},
                    },
                },
            },
        ],
    ),
    # Once GKE is ready the in-cluster stack follows, each protected by a Usage, and the
    # Cluster publishes where its kubeconfig lives.
    test(
        "cluster-gke-ready",
        xr=xr(),
        observedResources=[OBSERVED_GKE_READY],
        assertResources=[
            {
                "apiVersion": "gcp.platformref.upbound.io/v1alpha1",
                "kind": "Cluster",
                "metadata": {"name": NAME},
                "status": {
                    "kubernetes": {
                        "ready": True,
                        "providerConfigName": ID,
                        "kubeconfigSecretRef": {
                            "name": f"{NAME}-gke-connection",
                            "key": "kubeconfig",
                        },
                    },
                },
            },
            {
                "apiVersion": "observe.platform.upbound.io/v1alpha1",
                "kind": "Oss",
                "metadata": meta(f"{NAME}-observability", "composite-observability-oss"),
                "spec": {
                    "parameters": {"id": ID, "operators": {"prometheus": {"version": "52.1.0"}}}
                },
            },
            {
                "apiVersion": "gitops.platform.upbound.io/v1alpha1",
                "kind": "Flux",
                "metadata": meta(f"{NAME}-gitops", "composite-gitops-flux"),
                "spec": {
                    "parameters": {
                        "managementPolicies": ["*"],
                        "providerConfigName": ID,
                        "source": XR["spec"]["parameters"]["gitops"],
                    },
                },
            },
            gke_usage(
                f"{ID}-gke-by-oss",
                "usage-gke-by-oss",
                {
                    "apiVersion": "observe.platform.upbound.io/v1alpha1",
                    "kind": "Oss",
                    "resourceSelector": {"matchControllerRef": True},
                },
            ),
            gke_usage(
                f"{ID}-gke-by-flux",
                "usage-gke-by-flux",
                {
                    "apiVersion": "gitops.platform.upbound.io/v1alpha1",
                    "kind": "Flux",
                    "resourceSelector": {"matchControllerRef": True},
                },
            ),
        ],
    ),
    # Apps opted in to deletion ordering and deployed to this cluster each get a Usage, found
    # through the App API rather than the Helm Releases behind it.
    test(
        "cluster-app-deletion-ordering",
        xr=xr(),
        extraResources=[app("ghost", ID), app("elsewhere", "another-cluster")],
        assertResources=[
            gke_usage(
                f"{ID}-gke-by-app-ghost",
                "usage-gke-by-app-ghost",
                {
                    "apiVersion": "platform.upbound.io/v1alpha1",
                    "kind": "App",
                    "resourceRef": {"name": "ghost"},
                },
            ),
        ],
    ),
    # Orphan keeps cloud resources when the Cluster goes, in each domain's own terms, and the
    # overrides beat the platform's choices.
    test(
        "cluster-orphan-with-overrides",
        xr=xr(
            deletionPolicy="Orphan",
            nodes={"count": 3, "size": "large", "instanceType": "e2-standard-8"},
            operators={"prometheus": {"version": "60.0.0"}},
        ),
        observedResources=[OBSERVED_GKE_READY],
        assertResources=[
            {
                "apiVersion": "gcp.platform.upbound.io/v1alpha1",
                "kind": "GKE",
                "metadata": {"name": f"{NAME}-gke"},
                "spec": {
                    "parameters": {
                        "managementPolicies": ["Create", "Observe", "Update", "LateInitialize"],
                        "nodes": {"count": 3, "instanceType": "e2-standard-8"},
                    },
                },
            },
            {
                "apiVersion": "observe.platform.upbound.io/v1alpha1",
                "kind": "Oss",
                "metadata": {"name": f"{NAME}-observability"},
                "spec": {
                    "parameters": {
                        "managementPolicies": ["Create", "Observe", "Update"],
                        "operators": {"prometheus": {"version": "60.0.0"}},
                    },
                },
            },
        ],
    ),
    # A Cluster created by the KCL implementation keeps its existing GKE, and publishes the
    # kubeconfig Secret under that GKE's name.
    test(
        "cluster-upgraded-from-kcl",
        xr=xr(),
        observedResources=[OBSERVED_LEGACY_GKE_READY],
        assertResources=[
            {
                "apiVersion": "gcp.platformref.upbound.io/v1alpha1",
                "kind": "Cluster",
                "metadata": {"name": NAME},
                "status": {
                    "kubernetes": {
                        "kubeconfigSecretRef": {
                            "name": "composite-cluster-gke-connection",
                            "key": "kubeconfig",
                        },
                    },
                },
            },
            {
                "apiVersion": "gcp.platform.upbound.io/v1alpha1",
                "kind": "GKE",
                "metadata": {"name": "composite-cluster-gke"},
            },
        ],
    ),
]

# The test runner expects an "items" array, one entry per test.
output = {"items": [t.model_dump(by_alias=True, exclude_none=True) for t in tests]}
print(yaml.dump(output))
