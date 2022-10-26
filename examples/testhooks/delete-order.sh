#!/usr/bin/env bash
set -aeuo pipefail

# Delete the release before deleting the cluster not to orphan the release object
# Use explicit ordering of the sql resources to avoid database stuck
# Note(ytsarev): order of `kubectl delete` matters as well, squashing it into a
# single command or reorder will break the test. Release should go last.
# Otherwise it will have time to be recreated by the Cluster XR.
# Note(turkenh): This is a workaround for the infamous dependency problem during deletion.
${KUBECTL} delete user.sql.gcp.upbound.io --all
${KUBECTL} delete postgresqlinstance.gcp.platformref.upbound.io --all
${KUBECTL} delete databaseinstance.sql.gcp.upbound.io --all
${KUBECTL} delete release.helm.crossplane.io --all
