
import models.io.upbound.platform.gcp.v1alpha1 as gcpplatform
import models.io.upbound.platform.observe.v1alpha1 as observeplatform
import models.io.upbound.platform.gitops.v1alpha1 as gitopsplatform
import models.io.crossplane.protection.v1beta1 as crossplaneprotectionv1beta1

oxr = option("params").oxr
_ocds = option("params").ocds
_dxr = option("params").dxr
dcds = option("params").dcds

_metadata = lambda name: str -> any {
    {
        name = name
        annotations = { "krm.kcl.dev/composition-resource-name" = name }
    }
}

# Extract parameters from XR
params = oxr.spec.parameters
_id = params.id
_region = params.region
_deletion_policy = params.deletionPolicy  # Kept for backward compatibility, converted to managementPolicies
_provider_config_name = params.providerConfigName
_version = params.version
_nodes_count = params.nodes.count
_nodes_instance_type = params.nodes.instanceType
_operators = params.operators
_gitops = params.gitops

# Convert deletionPolicy to managementPolicies for v2
_management_policies = ["Create", "Observe", "Update", "LateInitialize"] if _deletion_policy == "Orphan" else ["*"]

# Check if GKE is ready before creating any dependent resources (they all need cluster to be ready)
_gkeResource = None
if _ocds and "composite-cluster-gke" in _ocds:
    _gkeResource = _ocds["composite-cluster-gke"]
_gkeReadyCondition = [condition for condition in (_gkeResource?.Resource?.status?.conditions or []) if condition.type == "Ready" and condition.status == "True"]
_isGkeReady = len(_gkeReadyCondition) > 0

# Check if dependent resources already exist (safety checks to prevent uninstalling)
_ossExists = "composite-observability-oss" in _ocds if _ocds else False
_fluxExists = "composite-gitops-flux" in _ocds if _ocds else False

_items = [
    # Connection details are automatically propagated from GKE since it has kubeconfig in its connection secrets

    # Network resource
    gcpplatform.Network {
        metadata = _metadata("composite-network-gcp")
        spec = {
            parameters = {
                id = _id
                region = _region
                managementPolicies = _management_policies
                providerConfigName = _provider_config_name
            }
        }
    },

    # GKE resource (connection details are automatically propagated to parent XR)
    gcpplatform.GKE {
        metadata = _metadata("composite-cluster-gke") | {
            labels = {
                "xgke.gcp.platform.upbound.io/cluster-id" = _id
            }
            annotations = {
                "crossplane.io/external-name" = _id
            }
        }
        spec = {
            parameters = {
                id = _id
                region = _region
                managementPolicies = _management_policies
                providerConfigName = _provider_config_name
                version = _version
                nodes = {
                    count = _nodes_count
                    instanceType = _nodes_instance_type
                }
            }
        }
    },

    # Oss observability resource - only create when GKE is ready (needs cluster to be available)
    # Also create if it already exists to prevent uninstalling
    if _isGkeReady or _ossExists:
        observeplatform.Oss {
            metadata = _metadata("composite-observability-oss")
            spec = {
                parameters = {
                    managementPolicies = _management_policies
                    id = _id
                    operators = {
                        prometheus = _operators.prometheus
                    }
                }
            }
        }

    # Flux GitOps resource - only create when GKE is ready (needs cluster kubeconfig)
    # Also create if it already exists to prevent uninstalling
    if _isGkeReady or _fluxExists:
        gitopsplatform.Flux {
            metadata = _metadata("composite-gitops-flux")
            spec = {
                parameters = {
                    managementPolicies = _management_policies
                    providerConfigName = _id
                    operators = {
                        flux = _operators.flux
                        fluxSync = _operators["flux-sync"]
                    }
                    source = _gitops
                }
            }
        }

    # Usage resources for dependency management (typed objects)
    crossplaneprotectionv1beta1.Usage {
        metadata = _metadata("usage-gke-by-flux") | {
            name = "{}-gke-by-flux".format(_id)
            namespace = oxr.metadata.namespace
        }
        spec = {
            replayDeletion = True
            by = {
                apiVersion = "gitops.platform.upbound.io/v1alpha1"
                kind = "Flux"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
            of = {
                apiVersion = "gcp.platform.upbound.io/v1alpha1"
                kind = "GKE"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
        }
    }

    crossplaneprotectionv1beta1.Usage {
        metadata = _metadata("usage-gke-by-oss") | {
            name = "{}-gke-by-oss".format(_id)
            namespace = oxr.metadata.namespace
        }
        spec = {
            replayDeletion = True
            by = {
                apiVersion = "observe.platform.upbound.io/v1alpha1"
                kind = "Oss"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
            of = {
                apiVersion = "gcp.platform.upbound.io/v1alpha1"
                kind = "GKE"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
        }
    }

    crossplaneprotectionv1beta1.Usage {
        metadata = _metadata("usage-gke-by-arbitrary-labeled-release") | {
            name = "{}-gke-by-labeled-release".format(_id)
            namespace = oxr.metadata.namespace
            annotations = {
                "krm.kcl.dev/ready" = "True"
            }
        }
        spec = {
            replayDeletion = True
            by = {
                apiVersion = "helm.crossplane.io/v1beta1"
                kind = "Release"
                resourceSelector = {
                    matchLabels = {
                        "platform.upbound.io/deletion-ordering" = "enabled"
                    }
                }
            }
            of = {
                apiVersion = "gcp.platform.upbound.io/v1alpha1"
                kind = "GKE"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
        }
    }

]

items = _items
