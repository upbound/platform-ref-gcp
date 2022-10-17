#!/usr/bin/env bash
set -aeuo pipefail

UPTEST_GCP_PROJECT=${UPTEST_GCP_PROJECT:-crossplane-playground}

echo "Running setup.sh"
echo "Waiting until configuration package is healthy/installed..."
${KUBECTL} wait configuration.pkg platform-ref-gcp --for=condition=Healthy --timeout 5m
${KUBECTL} wait configuration.pkg platform-ref-gcp --for=condition=Installed --timeout 5m

echo "Creating cloud credential secret..."
${KUBECTL} -n upbound-system create secret generic gcp-creds --from-literal=credentials="${UPTEST_GCP_CREDS}" \
    --dry-run=client -o yaml | ${KUBECTL} apply -f -

echo "Waiting until provider-gcp is healthy..."
${KUBECTL} wait provider.pkg upbound-provider-gcp --for condition=Healthy --timeout 5m

echo_step "Waiting for all pods to come online"
"${KUBECTL}" -n upbound-system wait --for=condition=Available deployment --all --timeout=5m

echo "Creating a default provider config..."
cat <<EOF | ${KUBECTL} apply -f -
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
