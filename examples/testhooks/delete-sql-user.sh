#!/usr/bin/env bash
set -aeuo pipefail

# Delete the sql user before deleting the cluster not to orphan the sql user object
# Note(turkenh): This is a workaround for the infamous dependency problem during deletion.
${KUBECTL} delete user.sql.gcp.upbound.io --all
