"""Unit tests for the Cluster's composed resources and status.

These cover what the CompositionTests can't express, mainly that a resource is NOT composed:
assertResources only matches resources that exist.
"""

import pytest
from function import core
from function.serialize import to_dict
from models.io.upbound.platformref.gcp.cluster import v1alpha1 as clusterv1alpha1

XR = "xr"
ID = "xr-id"

PARAMS = {
    "id": ID,
    "region": "us-west2",
    "deletionPolicy": "Delete",
    "providerConfigName": "default",
    "nodes": {"count": 1},
    "gitops": {
        "git": {
            "url": "https://github.com/upbound/platform-ref-gcp/",
            "path": "/",
            "interval": "5m0s",
            "timeout": "60s",
            "ref": {"name": "refs/heads/main"},
        },
    },
}

READY = {"conditions": [{"type": "Ready", "status": "True"}]}
NOT_READY = {"conditions": [{"type": "Ready", "status": "False"}]}


def params(**overrides) -> clusterv1alpha1.Parameters:
    return clusterv1alpha1.Parameters(**(PARAMS | overrides))


def gke(name: str = f"{XR}-gke", state: dict = READY) -> dict:
    return {"metadata": {"name": name}, "status": state}


def build(xr_name: str = XR, **kwargs) -> dict[str, dict]:
    """Composed resources serialized exactly as fn.py sends them."""
    p = kwargs.pop("params", params())
    return {name: to_dict(m) for name, m in core.build(xr_name, p, **kwargs).items()}


IN_CLUSTER = {core.OSS, core.FLUX, core.USAGE_GKE_BY_OSS, core.USAGE_GKE_BY_FLUX}


def test_only_network_and_gke_before_gke_is_ready():
    assert set(build()) == {core.NETWORK, core.GKE}
    assert set(build(observed={core.GKE: gke(state=NOT_READY)})) == {core.NETWORK, core.GKE}


def test_in_cluster_stack_follows_gke_ready():
    assert IN_CLUSTER <= set(build(observed={core.GKE: gke()}))


def test_existing_in_cluster_stack_survives_gke_not_ready():
    observed = {core.GKE: gke(state=NOT_READY), core.OSS: {}, core.FLUX: {}}
    assert IN_CLUSTER <= set(build(observed=observed))


def test_names_derive_from_the_xr_so_clusters_can_share_a_namespace():
    a, b = build("a"), build("b")
    for key in (core.NETWORK, core.GKE):
        assert a[key]["metadata"]["name"] != b[key]["metadata"]["name"]
    assert a[core.GKE]["metadata"]["name"] == "a-gke"


@pytest.mark.parametrize(("size", "machine_type"), core.MACHINE_TYPES.items())
def test_size_maps_to_a_machine_type(size, machine_type):
    composed = build(params=params(nodes={"count": 1, "size": size}))
    assert composed[core.GKE]["spec"]["parameters"]["nodes"]["instanceType"] == machine_type


def test_instance_type_overrides_size():
    composed = build(params=params(nodes={"count": 1, "size": "small", "instanceType": "e2-x"}))
    assert composed[core.GKE]["spec"]["parameters"]["nodes"]["instanceType"] == "e2-x"


def test_orphan_keeps_cloud_resources_in_each_domains_terms():
    composed = build(params=params(deletionPolicy="Orphan"), observed={core.GKE: gke()})
    for key in (core.NETWORK, core.GKE, core.FLUX):
        assert composed[key]["spec"]["parameters"]["managementPolicies"] == core.ORPHAN_POLICIES
    oss = composed[core.OSS]["spec"]["parameters"]["managementPolicies"]
    assert oss == core.OSS_ORPHAN_POLICIES


def test_operator_versions_default_to_the_platforms_and_accept_overrides():
    default = build(observed={core.GKE: gke()})
    pinned = build(
        params=params(operators={"flux-sync": {"version": "9.9.9"}}), observed={core.GKE: gke()}
    )
    flux = default[core.FLUX]["spec"]["parameters"]["operators"]
    assert flux == {
        "flux": {"version": core.FLUX_VERSION},
        "fluxSync": {"version": core.FLUX_SYNC_VERSION},
    }
    assert pinned[core.FLUX]["spec"]["parameters"]["operators"]["fluxSync"]["version"] == "9.9.9"


def test_apps_on_other_clusters_get_no_usage():
    apps = [
        {"metadata": {"name": "ghost"}, "spec": {"parameters": {"providerConfigName": ID}}},
        {"metadata": {"name": "other"}, "spec": {"parameters": {"providerConfigName": "x"}}},
    ]
    composed = build(apps=apps)
    assert core.USAGE_GKE_BY_APP + "ghost" in composed
    assert core.USAGE_GKE_BY_APP + "other" not in composed
    by = composed[core.USAGE_GKE_BY_APP + "ghost"]["spec"]["by"]
    assert by == {
        "apiVersion": "platform.upbound.io/v1alpha1",
        "kind": "App",
        "resourceRef": {"name": "ghost"},
    }


def test_serialized_resources_carry_api_version_and_kind():
    for composed in build(observed={core.GKE: gke()}).values():
        assert composed["apiVersion"] and composed["kind"]


def test_status_publishes_no_kubeconfig_before_gke_is_ready():
    published = core.status(params())
    assert published["kubernetes"] == {"ready": False, "providerConfigName": ID}
    assert published["network"] == {"id": ID, "ready": False}


def test_status_follows_the_observed_gke_name():
    # A Cluster created by the KCL implementation kept its GKE's fixed name.
    published = core.status(params(), observed={core.GKE: gke("composite-cluster-gke")})
    ref = published["kubernetes"]["kubeconfigSecretRef"]
    assert ref == {"name": "composite-cluster-gke-connection", "key": "kubeconfig"}
