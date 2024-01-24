#!/usr/bin/env bash
set -aeuo pipefail

UPTEST_GCP_PROJECT=${UPTEST_GCP_PROJECT:-official-provider-testing}

echo "Running setup.sh"
echo "Waiting until configuration package is healthy/installed..."
"${KUBECTL}" wait configuration.pkg platform-ref-gcp --for=condition=Healthy --timeout 5m
"${KUBECTL}" wait configuration.pkg platform-ref-gcp --for=condition=Installed --timeout 5m
"${KUBECTL}" wait configurationrevisions.pkg --all --for=condition=Healthy --timeout 5m

echo "Creating cloud credential secret..."
"${KUBECTL}" -n upbound-system create secret generic gcp-creds --from-literal=credentials="${UPTEST_CLOUD_CREDENTIALS}" \
    --dry-run=client -o yaml | "${KUBECTL}" apply -f -

echo "Waiting until all installed provider packages are healthy..."
"${KUBECTL}" wait provider.pkg --all --for condition=Healthy --timeout 5m

echo "Waiting for all pods to come online..."
"${KUBECTL}" -n upbound-system wait --for=condition=Available deployment --all --timeout=5m

echo "Waiting for all XRDs to be established..."
"${KUBECTL}" wait xrd --all --for condition=Established

echo "Creating a default provider config..."
cat <<EOF | "${KUBECTL}" apply -f -
apiVersion: gcp.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    secretRef:
      key: credentials
      name: gcp-creds
      namespace: upbound-system
    source: Secret
  projectID: ${UPTEST_GCP_PROJECT}
EOF
