
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.io.upbound.platform.gcp.v1alpha1 as gcpv1alpha1
import models.io.upbound.platform.gitops.v1alpha1 as gitopsv1alpha1
import models.io.upbound.platform.observe.v1alpha1 as observev1alpha1
import models.io.upbound.platformref.gcp.v1alpha1 as platformrefgcpv1alpha1
import models.io.crossplane.protection.v1beta1 as crossplaneprotectionv1beta1

_items = [
    metav1alpha1.CompositionTest{
        metadata.name = "test-cluster"
        spec = {
            compositionPath = "../../apis/cluster/composition.yaml"
            xrPath = "../../examples/cluster-xr.yaml"
            xrdPath = "../../apis/cluster/definition.yaml"
            timeoutSeconds = 60
            validate = False
            assertResources = [
                # Network composite resource
                gcpv1alpha1.Network{
                    metadata = {
                        name = "composite-network-gcp"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/composition-resource-name" = "composite-network-gcp"
                        }
                    }
                    spec = {
                        parameters = {
                            id = "platform-ref-gcp"
                            region = "us-west2"
                            managementPolicies = ["*"]
                            providerConfigName = "default"
                        }
                    }
                }
                # GKE composite resource
                gcpv1alpha1.GKE{
                    metadata = {
                        name = "composite-cluster-gke"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                            "xgke.gcp.platform.upbound.io/cluster-id" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/external-name" = "platform-ref-gcp"
                            "crossplane.io/composition-resource-name" = "composite-cluster-gke"
                        }
                    }
                    spec = {
                        parameters = {
                            id = "platform-ref-gcp"
                            region = "us-west2"
                            managementPolicies = ["*"]
                            providerConfigName = "default"
                            version = "latest"
                            nodes = {
                                count = 1
                                instanceType = "n1-standard-4"
                            }
                        }
                    }
                }
                # Oss observability resource
                observev1alpha1.Oss{
                    metadata = {
                        name = "composite-observability-oss"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/composition-resource-name" = "composite-observability-oss"
                        }
                    }
                    spec = {
                        parameters = {
                            managementPolicies = ["*"]
                            id = "platform-ref-gcp"
                            operators = {
                                prometheus = {
                                    version = "52.1.0"
                                }
                            }
                        }
                    }
                }
                # Flux GitOps resource
                gitopsv1alpha1.Flux{
                    metadata = {
                        name = "composite-gitops-flux"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/composition-resource-name" = "composite-gitops-flux"
                        }
                    }
                    spec = {
                        parameters = {
                            managementPolicies = ["*"]
                            providerConfigName = "platform-ref-gcp"
                            operators = {
                                flux = {
                                    version = "2.10.6"
                                }
                                fluxSync = {
                                    version = "1.7.2"
                                }
                            }
                            source = {
                                git = {
                                    url = "https://github.com/upbound/platform-ref-gcp/"
                                    path = "/"
                                    interval = "5m0s"
                                    timeout = "60s"
                                    ref = {
                                        name = "refs/heads/main"
                                    }
                                }
                            }
                        }
                    }
                }
                # Usage resources for dependency management (typed objects)
                crossplaneprotectionv1beta1.Usage{
                    metadata = {
                        name = "platform-ref-gcp-gke-by-flux"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/composition-resource-name" = "usage-gke-by-flux"
                        }
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
                crossplaneprotectionv1beta1.Usage{
                    metadata = {
                        name = "platform-ref-gcp-gke-by-oss"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/composition-resource-name" = "usage-gke-by-oss"
                        }
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
                crossplaneprotectionv1beta1.Usage{
                    metadata = {
                        name = "platform-ref-gcp-gke-by-labeled-release"
                        labels = {
                            "crossplane.io/composite" = "platform-ref-gcp"
                        }
                        annotations = {
                            "crossplane.io/composition-resource-name" = "platform-ref-gcp-gke-by-labeled-release"
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
            # Observed resources to simulate GKE being ready (triggers Oss and Flux creation)
            observedResources = [
                # GKE with Ready condition to trigger Oss and Flux creation
                gcpv1alpha1.GKE{
                    metadata = {
                        name = "composite-cluster-gke"
                        annotations = {
                            "crossplane.io/composition-resource-name" = "composite-cluster-gke"
                        }
                    }
                    spec = {
                        parameters = {
                            id = "platform-ref-gcp"
                            region = "us-west2"
                            managementPolicies = ["*"]
                            providerConfigName = "default"
                            version = "latest"
                            nodes = {
                                count = 1
                                instanceType = "n1-standard-4"
                            }
                        }
                    }
                    status = {
                        conditions = [{
                            type = "Ready"
                            status = "True"
                            reason = "Available"
                            lastTransitionTime = "2024-01-01T00:00:00Z"
                        }]
                    }
                }
            ]
        }
    }
]
items = _items
