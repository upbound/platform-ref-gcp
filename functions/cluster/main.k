
import models.io.upbound.platform.gcp.v1alpha1 as gcpplatform
import models.io.upbound.platform.observe.v1alpha1 as observeplatform
import models.io.upbound.platform.gitops.v1alpha1 as gitopsplatform
import models.io.crossplane.apiextensions.v1alpha1 as crossplaneapiextensionsv1alpha1

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
_deletion_policy = params.deletionPolicy
_provider_config_name = params.providerConfigName
_version = params.version
_nodes_count = params.nodes.count
_nodes_instance_type = params.nodes.instanceType
_operators = params.operators
_gitops = params.gitops

# XR connection secret details for XGKE
_xr_uid = oxr.metadata.uid
_connection_secret_namespace = _dxr.spec?.writeConnectionSecretToRef?.namespace or "upbound-system"

# Check if XGKE is ready before creating any dependent resources (they all need cluster to be ready)
_gkeResource = None
if _ocds and "composite-cluster-gke" in _ocds:
    _gkeResource = _ocds["composite-cluster-gke"]
_gkeReadyCondition = [condition for condition in (_gkeResource?.Resource?.status?.conditions or []) if condition.type == "Ready" and condition.status == "True"]
_isGkeReady = len(_gkeReadyCondition) > 0

# Check if dependent resources already exist (safety checks to prevent uninstalling)
_ossExists = "composite-observability-oss" in _ocds if _ocds else False
_fluxExists = "composite-gitops-flux" in _ocds if _ocds else False

_items = [
    # Connection details are automatically propagated from XGKE since it has kubeconfig in its connection secrets

    # XNetwork resource
    gcpplatform.XNetwork {
        metadata = _metadata("composite-network-gcp")
        spec = {
            parameters = {
                id = _id
                region = _region
                deletionPolicy = _deletion_policy
                providerConfigName = _provider_config_name
            }
        }
    },

    # XGKE resource with connection details
    gcpplatform.XGKE {
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
                deletionPolicy = _deletion_policy
                providerConfigName = _provider_config_name
                version = _version
                nodes = {
                    count = _nodes_count
                    instanceType = _nodes_instance_type
                }
            }
            writeConnectionSecretToRef = {
                name = "{}-gke".format(_xr_uid)
                namespace = _connection_secret_namespace
            }
        }
    },

    # XOss observability resource - only create when XGKE is ready (needs cluster to be available)
    # Also create if it already exists to prevent uninstalling
    if _isGkeReady or _ossExists:
        observeplatform.XOss {
            metadata = _metadata("composite-observability-oss")
            spec = {
                parameters = {
                    deletionPolicy = _deletion_policy
                    id = _id
                    operators = {
                        prometheus = _operators.prometheus
                    }
                }
            }
        }

    # XFlux GitOps resource - only create when XGKE is ready (needs cluster kubeconfig)
    # Also create if it already exists to prevent uninstalling
    if _isGkeReady or _fluxExists:
        gitopsplatform.XFlux {
            metadata = _metadata("composite-gitops-flux")
            spec = {
                parameters = {
                    deletionPolicy = _deletion_policy
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
    crossplaneapiextensionsv1alpha1.Usage {
        metadata = _metadata("usage-xgke-by-xflux") | {
            name = "{}-gke-by-flux".format(_id)
        }
        spec = {
            replayDeletion = True
            by = {
                apiVersion = "gitops.platform.upbound.io/v1alpha1"
                kind = "XFlux"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
            of = {
                apiVersion = "gcp.platform.upbound.io/v1alpha1"
                kind = "XGKE"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
        }
    }

    crossplaneapiextensionsv1alpha1.Usage {
        metadata = _metadata("usage-xgke-by-xoss") | {
            name = "{}-gke-by-oss".format(_id)
        }
        spec = {
            replayDeletion = True
            by = {
                apiVersion = "observe.platform.upbound.io/v1alpha1"
                kind = "XOss"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
            of = {
                apiVersion = "gcp.platform.upbound.io/v1alpha1"
                kind = "XGKE"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
        }
    }

    crossplaneapiextensionsv1alpha1.Usage {
        metadata = _metadata("usage-xgke-by-arbitrary-labeled-release") | {
            name = "{}-gke-by-labeled-release".format(_id)
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
                kind = "XGKE"
                resourceSelector = {
                    matchControllerRef = True
                }
            }
        }
    }

    # Forward connection details from XGKE
    {
        apiVersion = "meta.krm.kcl.dev/v1alpha1"
        kind = "CompositeConnectionDetails"
        if _gkeResource:
            data = {
                kubeconfig = _gkeResource.ConnectionDetails.kubeconfig
            }
        else:
            data = {}
    }
]

items = _items
