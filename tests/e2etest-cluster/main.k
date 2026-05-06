
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.io.k8s.api.core.v1 as corev1
import models.io.upbound.platformref.gcp.v1alpha1 as platformrefgcpv1alpha1
import models.io.upbound.platform.gcp.v1alpha1 as platformgcpv1alpha1
import models.io.upbound.platform.v1alpha1 as platformv1alpha1
import models.io.upbound.gcpm.v1beta1 as gcpmv1beta1

_items = [
    metav1alpha1.E2ETest{
        metadata.name = "platform-ref-gcp-cluster"
        spec = {
            crossplane.autoUpgrade.channel = "Rapid"
            defaultConditions = ["Ready"]
            manifests = [
                # Cluster XR
                platformrefgcpv1alpha1.Cluster{
                    metadata = {
                        name = "platform-ref-gcp-cluster"
                        namespace = "default"
                    }
                    spec.parameters = {
                        id = "e2e-platform-ref-gcp"
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
                }
                # SQLInstance (MySQL)
                platformgcpv1alpha1.SQLInstance{
                    metadata = {
                        name = "platform-ref-gcp-database-mysql-test"
                        namespace = "default"
                    }
                    spec.parameters = {
                        engine = "mysql"
                        engineVersion = "8_0"
                        region = "us-west2"
                        storageGB = 10
                        passwordSecretRef = {
                            namespace = "default"
                            name = "mysqlsecret"
                            key = "password"
                        }
                        networkRef = {
                            id = "e2e-platform-ref-gcp"
                        }
                    }
                }
                # App (Ghost)
                platformv1alpha1.App{
                    metadata = {
                        name = "platform-ref-gcp-ghost"
                        namespace = "default"
                        labels = {
                            "platform.upbound.io/deletion-ordering" = "enabled"
                        }
                    }
                    spec.parameters = {
                        providerConfigName = "e2e-platform-ref-gcp"
                        helm = {
                            chart = {
                                name = "ghost"
                                repo = "oci://registry-1.docker.io/bitnamicharts"
                                version = "25.0.4"
                            }
                            wait = False
                        }
                        passwordSecretRef = {
                            namespace = "default"
                            name = "platform-ref-gcp-database-mysql-test-connection"
                        }
                    }
                }
            ]
            extraResources = [
                # GCP ProviderConfig (v2 provider family group)
                gcpmv1beta1.ProviderConfig{
                    metadata = {
                        name = "default"
                        namespace = "default"
                    }
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
                # MySQL password secret
                corev1.Secret{
                    metadata = {
                        name = "mysqlsecret"
                        namespace = "default"
                    }
                    type = "Opaque"
                    data = {
                        password = "dXBiMHVuZHIwY2s1ITMxMzM3"
                    }
                }
            ]
            skipDelete = False
            timeoutSeconds = 4500
        }
    }
]
items = _items
