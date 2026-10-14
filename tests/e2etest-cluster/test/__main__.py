"""Generate the Cluster E2ETest and print it as YAML."""

import yaml
from models.io.k8s.apimachinery.pkg.apis.meta import v1 as k8s
from models.io.upbound.dev.meta.e2etest import v1alpha1 as e2etest

NAMESPACE = "default"
CLUSTER_ID = "e2e-platform-ref-gcp"
DATABASE = "platform-ref-gcp-database-mysql-test"

test = e2etest.E2ETest(
    metadata=k8s.ObjectMeta(name="platform-ref-gcp-cluster"),
    spec=e2etest.Spec(
        crossplane=e2etest.Crossplane(
            autoUpgrade=e2etest.AutoUpgrade(channel="Rapid"),
        ),
        defaultConditions=["Ready"],
        manifests=[
            # A Cluster as a consumer writes it, relying on the platform for the rest.
            {
                "apiVersion": "gcp.platformref.upbound.io/v1alpha1",
                "kind": "Cluster",
                "metadata": {"name": "platform-ref-gcp-cluster", "namespace": NAMESPACE},
                "spec": {
                    "parameters": {
                        "id": CLUSTER_ID,
                        "region": "us-west2",
                        "nodes": {"count": 1, "size": "medium"},
                        "gitops": {
                            "git": {
                                "url": "https://github.com/upbound/platform-ref-gcp/",
                                "ref": {"name": "refs/heads/main"},
                            },
                        },
                    },
                },
            },
            # A MySQL database on the Cluster's network (status.network.id).
            {
                "apiVersion": "gcp.platform.upbound.io/v1alpha1",
                "kind": "SQLInstance",
                "metadata": {"name": DATABASE, "namespace": NAMESPACE},
                "spec": {
                    "parameters": {
                        "engine": "mysql",
                        "engineVersion": "8_0",
                        "region": "us-west2",
                        "storageGB": 10,
                        "passwordSecretRef": {"name": "mysqlsecret", "key": "password"},
                        "networkRef": {"id": CLUSTER_ID},
                        "providerConfigName": "default",
                    },
                },
            },
            # Ghost on the Cluster (status.kubernetes.providerConfigName), using the database's
            # connection Secret. The label keeps the cluster until the App is gone.
            {
                "apiVersion": "platform.upbound.io/v1alpha1",
                "kind": "App",
                "metadata": {
                    "name": "platform-ref-gcp-ghost",
                    "namespace": NAMESPACE,
                    "labels": {"platform.upbound.io/deletion-ordering": "enabled"},
                },
                "spec": {
                    "parameters": {
                        "providerConfigName": CLUSTER_ID,
                        "helm": {
                            "chart": {
                                "name": "ghost",
                                "repo": "oci://registry-1.docker.io/bitnamicharts",
                                "version": "25.0.4",
                            },
                            "wait": False,
                        },
                        "passwordSecretRef": {
                            "namespace": NAMESPACE,
                            "name": f"{DATABASE}-connection",
                        },
                    },
                },
            },
        ],
        extraResources=[
            {
                "apiVersion": "gcp.m.upbound.io/v1beta1",
                "kind": "ProviderConfig",
                "metadata": {"name": "default", "namespace": NAMESPACE},
                "spec": {
                    "projectID": "crossplane-playground",
                    "credentials": {
                        "source": "Upbound",
                        "upbound": {
                            "federation": {
                                "providerID": "projects/283222062215/locations/global/workloadIdentityPools/solutions-upbound-oidc-pool/providers/solutions-u5d-oidc-pool",
                                "serviceAccount": "solutions-u5d-service-account@crossplane-playground.iam.gserviceaccount.com",
                            },
                        },
                    },
                },
            },
            {
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {"name": "mysqlsecret", "namespace": NAMESPACE},
                "type": "Opaque",
                "data": {"password": "dXBiMHVuZHIwY2s1ITMxMzM3"},
            },
        ],
        # If True, skip cleanup of test resources and control plane after test
        # completion. Useful for debugging and inspecting test state. Defaults to
        # False.
        skipDelete=False,
        timeoutSeconds=4500,
    ),
)

# The test runner expects an "items" array, one entry per test.
output = {"items": [test.model_dump(by_alias=True, exclude_none=True)]}
print(yaml.dump(output))
