
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.io.upbound.platformref.gcp.v1alpha1 as platformrefgcpv1alpha1
import models.io.upbound.gcp.v1beta1 as gcpv1beta1

_items = [
    metav1alpha1.E2ETest{
        metadata.name = "platform-ref-gcp-cluster"
        spec = {
            crossplane.autoUpgrade.channel = "Rapid"
            defaultConditions = ["Ready"]
            manifests = [
                # Create XCluster (not Claim) for E2E testing
                platformrefgcpv1alpha1.XCluster{
                    apiVersion = "gcp.platformref.upbound.io/v1alpha1"
                    kind = "XCluster"
                    metadata = {
                        name = "platform-ref-gcp-cluster"
                    }
                    spec = {
                        parameters = {
                            id = "platform-ref-gcp-cluster"
                            region = "us-west2"
                            version = "latest"
                            deletionPolicy = "Delete"
                            providerConfigName = "default"
                            nodes = {
                                count = 1
                                instanceType = "n1-standard-4"
                            }
                            operators = {
                                flux = {
                                    version = "2.10.6"
                                }
                                "flux-sync" = {
                                    version = "1.7.2"
                                }
                                prometheus = {
                                    version = "52.1.0"
                                }
                            }
                            gitops = {
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
                        writeConnectionSecretToRef = {
                            name = "platform-ref-gcp-cluster-kubeconfig"
                            namespace = "upbound-system"
                        }
                    }
                }
            ]
            extraResources = [
                # GCP ProviderConfig for authentication
                gcpv1beta1.ProviderConfig{
                    metadata.name = "default"
                    spec = {
                        projectID = "crossplane-playground"
                        credentials = {
                            source = "Upbound"
                            upbound = {
                                federation = {
                                    providerID = "projects/283222062215/locations/global/workloadIdentityPools/solutions-upbound-oidc-pool/providers/solutions-u5d-oidc-pool"
                                    serviceAccount = "solutions-u5d-service-account@crossplane-playground.iam.gserviceaccount.com"
                                }
                            }
                        }
                    }
                }
            ]
            skipDelete = False
            timeoutSeconds = 4500
        }
    }
]
items = _items