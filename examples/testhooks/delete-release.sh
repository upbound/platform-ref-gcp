#!/usr/bin/env bash
set -aeuo pipefail

# Delete the release before deleting the cluster not to orphan the release object
# Use explicit ordering of the sql resources to avoid database stuck
# Note(turkenh): This is a workaround for the infamous dependency problem during deletion.
# Note(ytsarev): In addition to helm Release deletion we also need to pause
# XService reconciler to prevent it from recreating the Release.
${KUBECTL} annotate xservices.gcp.platformref.upbound.io --all crossplane.io/paused="true"
${KUBECTL} delete release.helm.crossplane.io --all
