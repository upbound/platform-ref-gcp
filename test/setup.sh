#!/usr/bin/env bash
set -aeuo pipefail

UPTEST_GCP_PROJECT=${UPTEST_GCP_PROJECT:-crossplane-playground}

${KUBECTL} -n upbound-system create secret generic gcp-creds --from-literal=credentials="${UPTEST_GCP_CREDS}" \
    --dry-run=client -o yaml | ${KUBECTL} apply -f -

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
