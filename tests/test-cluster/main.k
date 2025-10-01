
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.io.upbound.platform.gcp.v1alpha1 as gcpv1alpha1
import models.io.upbound.platform.gitops.v1alpha1 as gitopsv1alpha1
import models.io.upbound.platform.observe.v1alpha1 as observev1alpha1
import models.io.upbound.platformref.gcp.v1alpha1 as platformrefgcpv1alpha1

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
                # XNetwork composite resource
                gcpv1alpha1.XNetwork{
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
                            deletionPolicy = "Delete"
                            providerConfigName = "default"
                        }
                    }
                }
                # XGKE composite resource
                gcpv1alpha1.XGKE{
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
                            deletionPolicy = "Delete"
                            providerConfigName = "default"
                            version = "latest"
                            nodes = {
                                count = 1
                                instanceType = "n1-standard-4"
                            }
                        }
                        writeConnectionSecretToRef = {
                            name = "test-uid-12345-gke"
                            namespace = "upbound-system"
                        }
                    }
                }
                # XOss observability resource
                observev1alpha1.XOss{
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
                            deletionPolicy = "Delete"
                            id = "platform-ref-gcp"
                            operators = {
                                prometheus = {
                                    version = "52.1.0"
                                }
                            }
                        }
                    }
                }
                # XFlux GitOps resource
                gitopsv1alpha1.XFlux{
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
                            deletionPolicy = "Delete"
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
            ]
            # Observed resources to simulate XGKE being ready (triggers XOss and XFlux creation)
            observedResources = [
                # XGKE with Ready condition to trigger XOss and XFlux creation
                gcpv1alpha1.XGKE{
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
                            deletionPolicy = "Delete"
                            providerConfigName = "default"
                            version = "latest"
                            nodes = {
                                count = 1
                                instanceType = "n1-standard-4"
                            }
                        }
                        writeConnectionSecretToRef = {
                            name = "test-uid-12345-gke"
                            namespace = "upbound-system"
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