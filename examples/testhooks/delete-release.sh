#!/usr/bin/env bash
set -aeuo pipefail

# Delete the release before deleting the cluster not to orphan the release object
# Delete user.sql before deleteing the database instance for the similar reason
# Note(turkenh): This is a workaround for the infamous dependency problem during deletion.
${KUBECTL} delete release.helm.crossplane.io,user.sql.gcp.upbound.io --all
