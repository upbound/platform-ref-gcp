#!/usr/bin/env bash
set -aeuo pipefail

# Delete the sql user before deleting the database not to orphan the user object
# Use explicit ordering of the sql resources to avoid database stuck
# Note(turkenh): This is a workaround for the infamous dependency problem during deletion.
${KUBECTL} delete user.sql.gcp.upbound.io --all
