#!/usr/bin/env bash
set -aeuo pipefail

# Delete the release before deleting the cluster not to orphan the release object
# Use explicit ordering of the sql resources to avoid database stuck
# Note(turkenh): This is a workaround for the infamous dependency problem during deletion.
${KUBECTL} delete release.helm.crossplane.io --all
